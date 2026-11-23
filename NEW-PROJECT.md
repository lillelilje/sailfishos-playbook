# Starting a new Sailfish project

**Read when:** you are creating a new app, or scaffolding one from scratch.
**Skip when:** you are working inside an existing project — its own `AGENTS.md` is the map.

The order below is not arbitrary: each step removes a class of failure that is tedious to debug
afterwards. Steps 1–4 take minutes and save hours.

---

## 1. Decide the two things that change everything

**Which OS/arch?** Target **Sailfish OS 5.x, aarch64 only**. Do not add `armv7hl` "for compatibility"
— **VERIFIED 2026-10-10**, the reference device (Jolla Phone 2026) is aarch64 and armv7 devices are
legacy. Adding a second arch doubles your build matrix for nobody.

**Sandboxed or not?** This decides your distribution channel, so decide first:

| | Sandboxed (default) | Unsandboxed |
|---|---|---|
| `.desktop` | `[X-Sailjail] Permissions=…` | `Sandboxing=Disabled` |
| Can submit to | **Jolla Harbour** (curated) | not Harbour |
| Ships via | Jolla Store | **OpenRepos/Storeman** (or Chum) |
| Needs it if | plain UI + allowed APIs | spawning processes, a localhost proxy, own binary downloads |

Practical rule from real projects: an app that shells out to helper binaries or runs a localhost
server **cannot** be sandboxed, so it must go to OpenRepos. A data-only app should stay sandboxed
and aim for Harbour.

---

## 2. Name and identifiers

- Package/binary: `harbour-<name>`, all lowercase, no underscores.
- QML `ApplicationWindow` file: `qml/harbour-<name>.qml` (must match `TARGET`).
- RPM: `rpm/harbour-<name>.spec`.
- Sandbox identity (only if sandboxed): `OrganizationName` / `ApplicationName` in the desktop file,
  e.g. `org.dollfin` / `Dollfin`.
- Data dir: `~/.local/share/harbour-<name>`.
- Icons at four densities: `86x86`, `108x108`, `128x128`, `172x172`, all PNG, at exactly those
  pixel sizes. Generate them from one vector — `15-icons-and-art.md`.

---

## 3. Decide where the logic lives

Copy the three-layer shape. It is why these projects are testable:

```
qml/            UI only. Dumb views. No network, no parsing, no policy.
qml/Backend.qml Async facade over the engine. Exposes properties + callbacks.
python/*.py     The engine: pure stdlib where possible, unit-testable on the host.
src/*.cpp       Only what QML cannot do: a custom QML type, or a native sink.
```

**Why it matters:** the engine runs under plain `python3` on your laptop, so
`python/test_<name>.py` gives you a real safety net with no device and no network. Every project
here has one and runs it in a script before every build.

Do **not** put parsing, retry logic or state machines in QML. You cannot unit-test QML here, and
the build does not even syntax-check it (see `12-pitfalls.md`).

---

## 4. Lay down the tracking docs before the code

The habit that makes a project survivable by a *different* agent later:

```
AGENTS.md            working instructions for whoever edits the repo next
docs/PLAN.md         scope, phases, risks
docs/DECISIONS.md    numbered decision log (D-001…), with context and consequences
docs/PLATFORM.md     facts learned about THIS platform, with dates
docs/BUILD.md        how to build, and how to get it on the device
docs/PUBLISH.md      channel, signing, listing text, checklist
docs/TODO.md         ordered tasks, one "Now" section at the top
docs/DEVLOG.md       dated log of measurements and bugs  (the highest-value file)
```

See `11-working-method.md` for how to keep them useful rather than ceremonial.

---

## 5. Scaffold the skeleton

```sh
mkdir harbour-<name> && cd harbour-<name>
# copy a sibling's shape:
#   harbour-<name>.pro, rpm/harbour-<name>.spec, .desktop,
#   qml/harbour-<name>.qml (+ qml/pages/, qml/cover/),
#   python/<engine>.py + python/test_<engine>.py,
#   scripts/{build-rpm.sh,deploy-device.sh,run-tests.sh},
#   icons/{86x86,108x108,128x128,172x172}/ + icons/icon-master.svg
#   scripts/make-icons.sh          (templates/ → renders the SVG at all four sizes)
#   AGENTS.md, docs/*, README.md, LICENSE, .gitignore
```

Then, in order — each is "does the toolchain work at all":

0. **Copy the skeletons** from `../SailfishOS-development-docs/templates/` — `AGENTS.md`,
   `DECISIONS.md`, `DEVLOG.md` — and fill them in as you go. Starting them later never happens.
1. `scripts/build-rpm.sh` produces an RPM. (See `02-build-and-package.md`.)
2. Install on the phone and **launch it**. (See `03-device.md`.)
3. `scripts/run-tests.sh` is green (even with one trivial test).
4. Commit. **Only now start writing features.**

Getting this far before feature work is the whole trick: a scaffold that builds, deploys and logs
turns every later bug into a small question instead of a mystery.

---

## 6. Then, and only then, read what you actually need

- UI work → `04-qml-and-silica.md`
- The app icon → `15-icons-and-art.md` (copy `templates/icon-master.svg` + `make-icons.sh`)
- Python bridge → `05-python-pyotherside.md`
- C++ / native → `06-cpp-and-pro.md`
- Anything media → `08-media-playback.md`, then `09-youtube-and-innertube.md`

---

## The `.desktop` file

```ini
[Desktop Entry]
Type=Application
Name=My App
Exec=harbour-myapp
Icon=harbour-myapp
X-Nemo-Application-Type=silica-qt5

[X-Sailjail]
OrganizationName=org.myapp
ApplicationName=MyApp
Permissions=Internet            # sandboxed only; omit entirely if unsandboxed
```

**VERIFIED 2026-10-11:** the app can only reach the network if `Internet` is listed *and* the app is
sandboxed; an unsandboxed app has full access and needs none of this.

---

## Don't

- Don't add features before step 4 passes on the device.
- Don't hardcode itags, pixel sizes, or theme colours — see `12-pitfalls.md`.
- Don't skip `AGENTS.md` because "it's a small app". Especially not then; small apps are the ones
  that get resumed six months later with no memory of why anything is the way it is.
