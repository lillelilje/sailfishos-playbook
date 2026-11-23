# Sailfish OS development — one girl's playbook

This is **one girl's attempt** to write down a clear playbook for making **compliant, functional
Sailfish OS apps** for people to read and for LLMs to follow directly as a working reference. It
is not official Jolla documentation, not a tutorial, and not a complete map of the platform: it is
the distillation of building and shipping several apps to a real **Jolla Phone 2026**
(**FinTube**, **Kibble**, **Dollfin**, **Emojinal Support**, **Nekofish**).

It is aimed at **current Sailfish OS** (5.2 on the Jolla Phone 2026), because that is the device
these notes were measured on. Older Xperia devices on 4.x/5.0/5.1 follow most of it, but a few
facts will not.

The goal: point an agent here and it pulls in only what the current task needs, writes an app that
actually works and can pass Harbour review, and stops guessing about Sailfish from memory.

---

## How to use this folder

1. **Read this file, then the one or two files the table points at. Do not read the whole folder.**
2. Every file opens with `Read when` / `Skip when`. Honour it.
3. Facts carry a marker, and the markers are the point:
   - **VERIFIED `<date>`** — measured on real hardware, or read out of the device's own files.
     Trust this over theory, and over anything an LLM *remembers* about Sailfish.
   - **unverified** — derived, believed, or copied from docs. Check before relying on it.
   - **date-sensitive** — OS releases and YouTube internals change; re-verify by measurement.
4. **When a measurement contradicts a plausible theory, the measurement wins.** Several entries here
   exist only because a confident theory turned out to be wrong. See `12-pitfalls.md`.

---

## Route by task

| You are about to… | Read |
|---|---|
| start a brand-new app | [`NEW-PROJECT.md`](NEW-PROJECT.md) then [`01-platform.md`](01-platform.md) |
| set up the build | [`02-build-and-package.md`](02-build-and-package.md) |
| get it onto the phone | [`03-device.md`](03-device.md) |
| debug on the phone (logs, SSH launch, processes) | [`03-device.md`](03-device.md) |
| write QML / Silica UI | [`04-qml-and-silica.md`](04-qml-and-silica.md) |
| show notifications / keep a connection alive in the background | [`04-qml-and-silica.md`](04-qml-and-silica.md) |
| give the app an icon (or placeholder art for now) | [`15-icons-and-art.md`](15-icons-and-art.md) |
| call Python from QML | [`05-python-pyotherside.md`](05-python-pyotherside.md) |
| write C++, add a QML type, edit a `.pro` | [`06-cpp-and-pro.md`](06-cpp-and-pro.md) |
| save data | [`07-storage.md`](07-storage.md) |
| play video or audio | [`08-media-playback.md`](08-media-playback.md) |
| touch YouTube / yt-dlp | [`09-youtube-and-innertube.md`](09-youtube-and-innertube.md) |
| publish or package for users | [`10-publishing.md`](10-publishing.md) |
| run the project *as a project* | [`11-working-method.md`](11-working-method.md) |
| avoid the classic traps | [`12-pitfalls.md`](12-pitfalls.md) |
| write or fix a Patchmanager patch | [`13-patchmanager-patches.md`](13-patchmanager-patches.md) |

---

## What's in here

```
README.md            you are here — the router; read this, then stop
NEW-PROJECT.md       start-a-project checklist (do this before writing features)
01-platform.md       OS, devices, Qt 5.6/Silica, sandboxing, allowed APIs, deprecations
02-build-and-package.md   container build, .spec, .pro, rpmlint, packaged-file checks
03-device.md         phone prep, deploy, logs, and launching the app from SSH
04-qml-and-silica.md QML/Silica patterns, Qt 5.6 floor, models, notifications, background modes
05-python-pyotherside.md  the engine bridge, parallel lanes, silent-future errors, the test suite
06-cpp-and-pro.md    C++, native QML types, main() overrides
07-storage.md        JSON stores, atomic writes, permissions
08-media-playback.md proxy, seeking, hardware decode, pre-warming
09-youtube-and-innertube.md  yt-dlp, PO tokens, InnerTube, format selection
10-publishing.md     channels, signing, listing, release checklist
11-working-method.md docs set, decision log, devlog, verification, LLM collaboration
12-pitfalls.md       symptom → cause → fix, condensed
13-patchmanager-patches.md  GNU diff patches, fuzz, lib64 mangling, rebase loop
14-patch-color-emoji-5.2.md  worked example: the color emoji patch on 5.2
15-icons-and-art.md  launcher icons: four sizes, Sailfish style, generating placeholder art

templates/           copy-paste skeletons: AGENTS.md, DECISIONS.md, DEVLOG.md,
                     icon-master.svg + make-icons.sh (SVG master → the four PNGs)
```

### Pointing an agent at this folder

A useful opening instruction for a new project:

> Read `../SailfishOS-development-docs/README.md`, then **only** the files it routes you to for the
> current task. Prefer `verified` facts over your own recollection of Sailfish OS, and say which is
> which when you state something.

---

## The 60-second version

- **Sailfish OS 5.2 (Finlayson) is current, aarch64 only** (Jolla Phone 2026). Latest release
  `5.2.0.22`, out to all devices 2026-10-26; a 5.3 update was previewed in November 2026 but is not
  shipped yet, and the SDK container's build target is still `5.2.0.15`. **date-sensitive**.
  `armv7hl` is legacy. **VERIFIED**.
- Apps are **Qt 5.6 + QML + Sailfish Silica**. Silica is frozen on Qt 5.6, so the floor is real —
  see `04-qml-and-silica.md`. A Qt 6 path exists (**Keel** + **Reef** store) but is beta and not the
  default.
- Build with the **community Platform SDK container** through podman: no SDK install, no sudo.
- Every app is **sandboxed (Sailjail)** unless you disable it in the `.desktop`. Sandboxed apps can
  submit to **Jolla Harbour**; unsandboxed ones ship via **OpenRepos/Storeman** (or Chum).
- Structure the app as **dumb QML UI → async bridge → engine**. That shape is why the engines in
  these projects are unit-testable on the host with plain Python, and it is the single most useful
  architectural habit here.
- Keep a **decision log**, a **devlog of device measurements**, and an **`AGENTS.md`**. It is the
  difference between a project an LLM can continue and one it will wreck.
- To change a **system** file (keyboard, homescreen), ship a **Patchmanager patch**, not an app.
  A patch is a GNU diff against Jolla's files and breaks on almost every OS update — see
  `13-patchmanager-patches.md` for the format and the rebase loop.

---

## Where the source material lives

Each project's own `docs/` folder is the long form. This folder is the distillation; when something
here feels too terse, the originals have the full reasoning:

| Project | What it contributed |
|---|---|
| **FinTube** | media proxy, GStreamer player, yt-dlp + PO-token management, format selection |
| **Kibble** | PO tokens end to end, InnerTube feed paging, streaming proxy, on-device debugging loop |
| **Dollfin** | platform/sandbox/API survey, container build, reminders and calendar, publishing |
| **Emojinal Support** | Silica component inventory, sailor-emoji packs, in-process unzip, sailjail profiles |
| **Nekofish** | plain-stream playback with no proxy, the `Audio` permission, WebSocket metadata, `Amber.Mpris` lockscreen, engine-scheduled timers, the Image-not-Canvas rule |
