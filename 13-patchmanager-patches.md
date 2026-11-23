# 13 — Patchmanager patches

**Read when:** you want to change a system file Jolla owns (keyboard, homescreen, settings
QML, a `.conf`), or a patch that used to work stopped applying after an OS update.
**Skip when:** you are building a normal app — ship a package, not a patch.

A patch is the only sane way to tweak closed Jolla QML. It is also the most fragile thing in
this folder: it is a text diff against files that Jolla edits without notice. A working patch
is a patch plus a maintenance loop.

`14-patch-color-emoji-5.2.md` is a full worked example of a real patch breaking on 5.2 and
what it takes to rebase it.

---

## What a Patchmanager patch actually is

A patch is one GNU unified diff plus metadata, installed as a directory:

```
/usr/share/patchmanager/patches/<name>/
    unified_diff.patch     the diff; applied to / with  patch -p1
    patch.json             Patchmanager 3 metadata (name, version, compatible versions, …)
    translation_<lang>.qm  optional
```

**VERIFIED 2026-10-15** — read out of the device (`sfos-patch-keyboard-color-stock-emojis`
1.5.4). Older Patchmanager 2 packages use a `CONFIG` file instead; the source repos below use
`CONFIG`, and the build tool turns it into `patch.json`. The diff is the same either way.

Apply/unapply is literally:

```sh
patch -p1 -d / < unified_diff.patch      # apply
patch -p1 -R -d / < unified_diff.patch   # reverse (unapply)
```

so `-p1` strips one path component and the paths *inside* the diff are relative to `/` with no
leading slash: `usr/share/...`, not `/usr/share/...`.

**VERIFIED 2026-10-15** — the 1.5.4 `unified_diff.patch`: `diff --git a/usr/... b/usr/...`,
new files use `--- /dev/null` and `+++ b/usr/...`. Both header styles work; the `diff --git`
lines are cosmetic to `patch`, only the `---`/`+++`/`@@` lines matter.

### Fuzz is a trap

GNU `patch` accepts a hunk if its context matches with up to **2 lines of fuzz** by default
(it can walk the hunk ±2 lines and drop mismatching context). That is why a patch can print
`Hunk #3 succeeded at 35 with fuzz 2` and still "work" — for now. Every fuzz warning is a
place where Jolla has already drifted and a future change will turn it into `FAILED`.

**VERIFIED 2026-10-15** — reproducing the 5.2 failure gave exactly these warnings.
**Read the warnings.** A rebuild that removes fuzz is worth doing.

---

## Where patch sources live

The community keeps patch sources in git, one directory per patch. The main one for this
ecosystem:

- `https://codeberg.org/ichthyosaurus/sailfish-public-patch-sources` — ichthyosaurus' patches,
  including the color emoji keyboard patch.
- The build tool: `https://codeberg.org/ichthyosaurus/sailfish-patch`.

Each patch directory has a `CONFIG` (metadata; the human-edited form of `patch.json`),
`COPYING`, screenshots, and `unified_diff.patch`. From the upstream README:

```sh
sailfish-patch -u     # fetch + prepare the original package sources
sailfish-patch -b     # build the patch
sailfish-patch -p     # install to the device over SSH
sailfish-patch -u -b -p
```

`-u` needs an SSH connection to a phone for packages Jolla does not publish. `sailfish-patch`
restarts `maliit-server` for keyboard patches automatically; the manual command is
`systemctl --user restart maliit-server`. (Upstream README; **unverified** by us.)

Note the repo carries a `LicenseRef-NO-AI-1.0` header: **do not feed it to AI training or
data-mining.** Work with it, don't train on it.

---

## Writing a patch by hand (when there is no source repo, or you are just fixing one)

You do **not** need the SDK. You need the stock file, a text editor, and a device.

1. **Get pristine originals.** Pull the files the patch touches from the device *before*
   applying anything. Keep them under a `orig/` tree that mirrors `/`:
   ```sh
   scp defaultuser@<phone>:/usr/share/maliit/plugins/com/jolla/Popper.qml  orig/usr/share/maliit/plugins/com/jolla/
   ```
   If the patch is already applied, unapply it first (Patchmanager) or use the pristine copy
   in the source repo.
2. **Copy to `patched/` and edit.** Make the smallest change that does the job.
3. **Generate the diff.** `diff -ruN orig patched` or `git diff --no-index orig patched`.
   Rewrite the paths so the diff says `a/usr/...` / `b/usr/...` (or `--- /dev/null` for new
   files). GNU `patch` creates missing parent directories for new files, so a new
   `/usr/lib64/qt5/qml/.../ichthyo_color_emojis/` directory is fine.
4. **Dry-run against the real system, read-only:**
   ```sh
   patch -p1 --dry-run -d / < unified_diff.patch
   ```
   Fix every `FAILED` hunk and every `fuzz` warning before installing.
5. **Install / apply**, then restart the service the patch affects (keyboard:
   `systemctl --user restart maliit-server`; homescreen: settings → utilities →
   restart homescreen). Verify by eye — a patch that applies can still be logically wrong.
6. **Unapply** with `-R` (or Patchmanager) and confirm the originals come back byte-for-byte.

### Finding *why* an old patch fails

The rebase loop is always the same:

```sh
patch -p1 --dry-run -d / < unified_diff.patch      # shows FAILED hunks + fuzz
```

Then, per failed file, compare the patch's context with the current stock file:

```sh
diff -u <patch's expected base> /path/to/current/stock/file
```

The cause is almost always one of:

| Cause | Tell |
|---|---|
| Jolla added/removed a **blank line** | `FAILED` / `fuzz` right at the hunk edge |
| Jolla added an **import** or a property | context line missing |
| The **file moved** (often `share` → `lib64`) | "can't find file to patch" |
| Jolla **refactored** the component | context genuinely changed; re-write the hunk |

A hunk that fails with `fuzz 2` today may still apply, but fix it anyway: add the new blank
line to the context, or anchor the hunk on lines that don't move.

---

## 64-bit (`aarch64`) path mangling — the trap that eats patches

Patchmanager rewrites a few known library paths on 64-bit devices at apply time:

```
/usr/lib/qt5/qml            → /usr/lib64/qt5/qml
/usr/lib/jolla-mediaplayer  → /usr/lib64/jolla-mediaplayer
/usr/lib/maliit/plugins     → /usr/lib64/maliit/plugins
```

**VERIFIED 2026-10-15** — Patchmanager's own log on the device says
`Converting library path reference /usr/lib/qt5/qml … OK` (also discussed on the forum in
2023). So a source patch can keep saying `/usr/lib/qt5/qml` and Patchmanager fixes it on an
aarch64 phone.

**But it only knows those three directories.** A file that moved anywhere else must be
updated by hand in the patch. And a **QML `import "relative/dir"` is not mangled** — it
resolves next to the file it appears in, so if the file moved, the import breaks even though
the patch applied. This is the subtle half of the 5.2 emoji-patch failure.

Keep `lib` **or** `lib64` consistently inside one patch. Mixing them is how you get the
`module "…" is not installed` runtime error (forum, SFOS 4.6/5.0, fixed by a Patchmanager
release — not in the patch).

---

## Checklist before calling a patch done

- [ ] `patch -p1 --dry-run -d / < …` → zero `FAILED`, ideally zero `fuzz`.
- [ ] Every existing file the patch edits is present at the path the patch names.
- [ ] Every new file's parent directory either exists or is created by `patch`.
- [ ] Relative `import "…"` paths still point at the right directory after any file move.
- [ ] `patch.json` (`compatible`) lists the OS versions you actually tested; the version
      string in the UI (if the patch has a settings page) matches the metadata.
- [ ] Unapply restores the originals.
- [ ] For keyboard patches: restart `maliit-server` before testing.

## Sources

- `codeberg.org/ichthyosaurus/sailfish-public-patch-sources` (patches, `patch.json`/`CONFIG`)
- `codeberg.org/ichthyosaurus/sailfish-patch` (build tool)
- Patchmanager logs quoted from the forum thread *Patches by ichthyosaurus*
  (<https://forum.sailfishos.org/t/patches-by-ichthyosaurus/15387>)
- Device reads on SFOS 5.2.0.20 (this doc's VERIFIED markers)
