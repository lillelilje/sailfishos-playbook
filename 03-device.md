# 03 — Device workflow

**Read when:** you need to get a build onto a phone, read its logs, or debug something that only
happens on hardware.
**Skip when:** you are still working on the host.

All **VERIFIED 2026-10-10/12 and 2026-11-23** against a Jolla Phone 2026 over USB and WLAN.

---

## One-time phone prep

In **Settings → Developer tools**:

1. Turn on **Developer mode** (asks for your security code).
2. Turn on **Remote connection**.
3. **Set password for SSH and root access.** This password is *both* the SSH password and the
   `devel-su` password.

The phone must be **awake and unlocked** or SSH will refuse.

## Connecting

- **USB (recommended):** plug in and pick **Developer mode** in the USB dialog. The phone then sits
  on its own little network at a fixed address — **`192.168.2.15` is the Sailfish USB default**, a
  platform constant rather than a personal one.
- **WLAN:** join the same network; the IP is shown in Developer tools.

```sh
ssh defaultuser@<phone-ip>
```

> **Do not commit your phone's address.** Public repos should use a placeholder. Kibble had to
> scrub a real LAN IP out of its docs after publishing.

## Build → copy → install

```sh
scripts/build-rpm.sh
scripts/deploy-device.sh <user@host>      # scp + `devel-su rpm -Uvh --force`
```

**`devel-su` prompts for a password**, which is why device installs normally stay a human step. If
you are automating, expect `ssh -t` so the prompt has a TTY:

```sh
ssh -t defaultuser@<phone-ip> "devel-su rpm -Uvh --force ~/harbour-myapp-1.0.0-1.aarch64.rpm"
```

`rpm -Uvh --force` on a locally built RPM is fine; no signature checks are done.

**Same version, local reinstall.** `rpm -Uvh` does *not* replace an installed package with the same
`name-version-release`. Add `--force` (or bump `Release`) when you rebuild the same version for
testing. **VERIFIED 2026-11-23.**

**When `pkcon` is not an option.** `pkcon install-local --allow-untrusted <rpm>` from an SSH session
ends in `Fatal error: user declined simulation`: there is no polkit agent attached to the SSH
session, so the approval dialog cannot appear. Use `devel-su rpm -Uvh --force`, or trigger `pkcon`
from the device UI where the prompt can be shown. **VERIFIED 2026-11-23.**

**`devel-su` syntax.** It executes the command directly; there is no `-c` flag:

```sh
devel-su rpm -Uvh --force ~/harbour-myapp-1.0.0-1.aarch64.rpm   # correct
devel-su -c "rpm -Uvh …"                                        # Failed to exec: No such file or directory
```

Use `ssh -t` when a password prompt is involved. **VERIFIED 2026-11-23.**

**The phone drops off the network intermittently.** Any `scp`/`ssh` you script here should retry a
few times with a short sleep rather than failing the whole task.

---

## Reading logs — the part worth copying

**The journal**, for the app's stdout/stderr and Qt warnings:

```sh
ssh defaultuser@<phone-ip> "devel-su journalctl -f _COMM=harbour-myapp"
ssh defaultuser@<phone-ip> "devel-su journalctl _COMM=harbour-myapp | tail -100"
```

**But the journal is awkward** for a long-running agent session, so the sibling apps also write their
own log file. Kibble's pattern, which works well:

- The app writes `~/.local/share/harbour-<name>/dev.log`.
- It is **off by default**; it turns on if a marker file `…/dev.log`'s sibling `debug` exists, or if
  `MYAPP_DEBUG=1` is set.
- The C++ `main()` installs a Qt message handler that mirrors Qt output into the same file, so QML
  warnings and engine lines land in one place.

Then debugging a device issue is one command:

```sh
ssh defaultuser@<phone-ip> "tail -50 ~/.local/share/harbour-myapp/dev.log"
```

**Make QML warnings visible this way.** The single most expensive bug class in this project was a
`TypeError: Property 'x' is not a function` that had been firing every 350 ms — invisible without the
mirrored log, obvious with it. See `12-pitfalls.md`.

**`defaultuser` cannot read the journal.** Both `journalctl` and `journalctl --user` end in
`No journal files were opened due to insufficient permissions`; only `devel-su journalctl` works
unless the user is added to `systemd-journal`. **VERIFIED 2026-11-23.** If you do not want to use
`devel-su` just to follow logs, read the next section.

---

## Launch the app yourself and capture its log (no root)

`invoker` launches an app through `mapplauncherd` and Sailjail, exactly like the app grid, and the
child inherits its stdout/stderr. Redirect those to a file and you get the journal contents without
`devel-su`:

```sh
ssh defaultuser@<phone-ip> \
  'nohup invoker --type=silica-qt5 --single-instance \
     --desktop-file=harbour-myapp.desktop /usr/bin/harbour-myapp \
     </dev/null >~/harbour-myapp.log 2>&1 &'

ssh defaultuser@<phone-ip> 'tail -f ~/harbour-myapp.log'
```

- `--single-instance --desktop-file=…` makes it behave like a launch from the app grid instead of
  starting a second copy.
- The process still runs through `invoker`/`mapplauncherd`, Sailjail and firejail. This is a real
  sandboxed run, not a debug escape hatch.
- The file contains Qt warnings, QML errors and anything the Python engine writes to stderr, the
  same as the journal. **VERIFIED 2026-11-23.**
- `nohup … &` plus the redirect is enough for the app to survive the SSH connection closing. The
  process is not tied to the terminal.

**Normal launch noise, not your bug.** A sandboxed launch prints lines like these:

```
Error: can't chdir to privileged
library "libselinux.so" not found
library "/vendor/lib64/egl/.../libGLES_mali.so" is not accessible for the namespace "(default)"
[WARN] EGLDisplay ... was not properly terminated by the application
```

Do not spend time on them. Look for `Traceback`, `TypeError`, `AttributeError`, your own log lines,
or a QML parse/runtime error.

---

## Processes, `comm`, and killing the app

- `ps` on the device is **BusyBox**: `ps -p <pid>` and `ps -ef` are not supported. Use plain `ps`,
  `ps -o pid,args`, or read `/proc/<pid>/comm` and `/proc/<pid>/cmdline`.
- Linux truncates `comm` to **15 characters**. `harbour-myapp` fits, but `harbour-myapplication`
  appears as `harbour-myappl`, and `pgrep -x harbour-myapplication` finds nothing. Read
  `/proc/*/comm` when in doubt. **VERIFIED 2026-11-23.**
- **Never use `pkill -f /usr/bin/harbour-myapp` in an SSH one-liner.** The shell running your
  command has that path in its own command line, so `pkill -f` matches the shell and kills your
  session (exit 255). Use `pkill -x <comm>` or kill the PID found through `/proc`:

```sh
for p in /proc/[0-9]*; do
    [ "$(cat "$p/comm" 2>/dev/null)" = "harbour-myapp" ] && kill "${p##*/}"
done
```

- A process that logs `Client was disconnected successfully` and exits is shutting down cleanly; it
  is not a crash.

## Read app settings without root

Settings stored with `Nemo.Configuration` (`ConfigurationGroup`) live in dconf under the group's
`path`. Verify a toggle without opening the UI:

```sh
ssh defaultuser@<phone-ip> 'dconf read /apps/harbour-myapp/settings/foo'
```

Use the exact `path` from the QML. Empty output means "not set", and QML uses the property default.
**VERIFIED 2026-11-23.**

---

## What the engine can tell you

Log the things you *cannot* see otherwise, at the points where you would otherwise guess:

- Every external call and its outcome, with the identifier: `stream <id>: v=… a=… (path, 2.3s)`.
- Which *path* was taken — `auth+pot` vs `anon` — not just "it worked". Kibble spent hours unsure
  whether its token path was in use; the log now says so explicitly.
- Timings around anything that can stall, so "it feels slow" becomes a number.
- UI-side breadcrumbs for user actions that have no engine trace: `swipe blocked: <id>`,
  `swipe released: <id>`, `feed refresh`.

**Rule of thumb:** if you find yourself reasoning about what the app *probably* did, add a log line
instead. Every one of those lines paid for itself within a day.

---

## Debugging without a screen

- Check the app is running: `ps | grep [h]arbour-myapp` (not `ps ax -p`; BusyBox has no `-p`)
- Check the process name: `cat /proc/<pid>/comm` (15 characters, truncated)
- Check its data: `ls -la ~/.local/share/harbour-myapp/`
- Check a listening port: `ss -ltn | grep <port>`
- Stop it by PID or by the truncated `comm`, not `pkill -f <full path>` (see above)
- Check a `Nemo.Configuration` setting: `dconf read /apps/harbour-myapp/settings/foo`

Tooling that is **absent** on the device (do not assume it): **`timeout` is missing**, and `date`
has no `%N`. If you script measurements, do the timing in Python.
