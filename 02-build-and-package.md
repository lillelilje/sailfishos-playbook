# 02 — Build and package

**Read when:** you are setting up the build, or an RPM fails, or you need to add a dependency.
**Skip when:** the build already works.

Everything below is **VERIFIED 2026-10-10/12 and 2026-11-23** on a Bazzite host with podman and no
Sailfish SDK.

---

## The default: container build, no SDK, no sudo

The community **Platform SDK container**
([`coderus/sailfishos-platform-sdk`](https://hub.docker.com/r/coderus/sailfishos-platform-sdk/tags))
ships a `5.2.0.15` aarch64 target and builds with `mb2`. That is the default path in all the sibling
projects, via a `scripts/build-rpm.sh`.

```
scripts/build-rpm.sh                # 5.2.0.15 aarch64
scripts/build-rpm.sh 5.1.0.11       # other target
→ RPMS/harbour-<name>-<version>-1.aarch64.rpm
```

Requirements: **podman**, and ~6 GB free (first pull is ~5 GB).

**The one host tweak that is easy to miss:** the image contains files owned by UID 100000, outside
the default rootless subuid range, so add `~/.config/containers/storage.conf`:

```toml
[storage]
driver = "overlay"

[storage.options.overlay]
ignore_chown_errors = "true"
```

Why the script looks strange: `mersdk` (the image's build user) is UID 100000 and **`mb2` refuses to
run as root**. So the script starts as container root, moves `mersdk` into the subuid range
(`usermod -u 1000`), and drops to it with **`chroot --userspec`** (no PAM, unlike `su`/`runuser`).
Copy that script rather than reinventing it.

Alternatives, only if you need them: the full **Sailfish SDK** (`sfdk`) for the emulator or
`sfdk deploy`, or the CLI-only Platform SDK chroot (needs sudo). Neither is needed day to day.

---

## The `.spec` — what actually matters

```spec
Name:       harbour-myapp
Summary:    One line, no trailing period
Version:    1.0.0
Release:    1
Group:      Qt/Qt
License:    GPLv3+
URL:        https://github.com/<you>/harbour-myapp
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  desktop-file-utils
Requires:   sailfishsilica-qt5 >= 0.10.9

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/86x86/apps/%{name}.png
# …108, 128, 172
```

Rules learned the hard way:

- **`sailfishsilica-qt5` is a runtime `Requires`, always.**
- **Do not require a binary your app downloads for itself.** Kibble and FinTube install/update
  yt-dlp at runtime, so yt-dlp is deliberately *not* a dependency. If you add it, you will ship a
  broken app the day the distro copy is stale.
- **A runtime `Requires` for tools you actually shell out to** (FinTube requires `git` because it
  clones the PO-token provider at runtime).
- **Version must match the code's own version constant.** Kibble shipped twice with the About screen
  one version behind because they drifted. There is now a test asserting the engine's version equals
  the spec's `Version:` — steal that idea.
- **Icons are checked by their pixel size, not just their presence.** A PNG at 1024 named
  `86x86.png` is a Harbour *error*. Render all four from `icons/icon-master.svg` —
  `15-icons-and-art.md` has the sizes, the `.pro` line and the script.
- **Python dependencies are ABI-bound to the interpreter minor version.** `pip --target` produces
  `*.cpython-311-aarch64-linux-gnu.so`; those will not import on a 3.13 target. Rebuild the deps
  against the target's Python, and declare `Requires: python3-base >= 3.11` only as a floor — never
  an exact micro pin. **VERIFIED 2026-11-23.**
- **A first release gets one changelog entry**, not your whole development history.

rpmlint should end `0 errors`. One warning is normal for Qt apps:
`unstripped-binary-or-object /usr/bin/harbour-<name>`. That is cosmetic.

---

## The `.pro` file, briefly

```qmake
TARGET = harbour-myapp
CONFIG += sailfishapp
QT += opengl network
PKGCONFIG += gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0
LIBS += -lsailfishapp -lmdeclarativecache5
QMAKE_LFLAGS += -pie -rdynamic
SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172   # files: icons/<W>x<H>/$$TARGET.png
```

Two things bite here, both **VERIFIED** (FinTube):

- **Adding `PKGCONFIG` can drop the sailfishapp libs from the link line**, so the explicit `LIBS` +
  `-pie -rdynamic` are load-bearing. If `SailfishApp::main()` suddenly goes unresolved, this is why.
- `sailfishapp.prf` installs the `qml/` tree and the `.desktop` for you; extra files (a Python
  engine, extra data) need their own `INSTALLS` stanza. See `06-cpp-and-pro.md`.

---

## Verify what you actually packaged

The container copies the working tree and `mb2` installs whatever the `.pro` finds; it does not tell
you whether a changed file made it in. After a build, extract and compare the files you touched:

```sh
rm -rf /tmp/pkg && mkdir /tmp/pkg
rpm2cpio RPMS/harbour-myapp-*.aarch64.rpm | (cd /tmp/pkg && cpio -idm --quiet)
cmp /tmp/pkg/usr/share/harbour-myapp/qml/pages/Foo.qml qml/pages/Foo.qml
```

Do that for the QML, Python and data files in the change. `rpm -qpl` is necessary but not
sufficient: it proves a path exists, not that it has your change. This catches a stale workspace, a
missing `DISTFILES` entry and a bad `INSTALLS` path. **VERIFIED 2026-11-23.**

## "Build done" is not "package clean"

The community Platform SDK image configures rpmlint to **treat errors as warnings** (the log says
`TreatErrorsAsWarnings set in options so returning success instead of 64`). A build can finish with
hundreds of `E:` lines and exit 0. Read the rpmlint output before calling a package good.

Common pre-existing errors from Python-heavy apps:

- `arch-dependent-file-in-usr-share` for compiled `.so` files under `/usr/share/<app>/lib/deps`
- `python-bytecode-inconsistent-mtime` when pip-installed `.pyc` files are newer than their sources
- `no-changelogname-tag` when no `%changelog` exists
- `description-shorter-than-summary`

They do not stop a local install, but they matter for a Harbour submission. **VERIFIED 2026-11-23.**

## Optional QML plugins are not library dependencies

Adding `Requires: libkeepalive` (or another `lib*` package) just to make one optional QML import
available produces rpmlint `E: explicit-lib-dependency` and prevents installation on a variant that
does not ship the package. If the feature is optional, load that QML file through a `Loader` and let
the plugin be absent; if it is required, require the **QML plugin package** the OS actually provides,
not the underlying library. **VERIFIED 2026-11-23** (`libkeepalive` exists on 5.2, and the app still
starts without it).

---

## Checklist before you call a build good

- [ ] `scripts/build-rpm.sh` ends `0 errors`
- [ ] `scripts/run-tests.sh` is green
- [ ] `rpm -qip` shows the right name/version/licence/summary
- [ ] `rpm -qlp` contains the binary, the `.desktop`, the icons **and your extra files**
- [ ] the files you changed are byte-identical inside the RPM (`cmp` above)
- [ ] rpmlint `E:` lines reviewed, not just the exit code
- [ ] it installs and launches on a real phone (`03-device.md`)

**Note:** the container build installs the files it finds in the tree. A file you forgot to add to
an `INSTALLS` stanza will be silently absent from the package — always check `rpm -qlp`, never
assume.
