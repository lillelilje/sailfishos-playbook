# 12 — Pitfalls

**Read when:** something is broken, or before you write a class of code for the first time.
**Skip when:** you have read the relevant topic file — most of these are cross-references.

Each entry: **symptom → cause → fix.** Almost all are real, dated failures from these projects.
The pattern to notice: the *symptom* usually points somewhere other than the cause.

---

## Build & packaging

| Symptom | Cause | Fix |
|---|---|---|
| `SailfishApp::main()` unresolved | adding `PKGCONFIG` dropped the sailfishapp libs from the link line | keep the explicit `LIBS += -lsailfishapp -lmdeclarativecache5` and `-pie -rdynamic` |
| A file is missing from the installed app | it was not in an `INSTALLS` stanza; `sailfishapp.prf` only installs `qml/` + `.desktop` | add the stanza, and **always check `rpm -qlp`** |
| Whole build fails with odd UID errors | rootless podman cannot run the image's UID 100000 user, and `mb2` refuses to run as root | copy the sibling `build-rpm.sh` (`usermod` + `chroot --userspec`) and set `ignore_chown_errors` |
| rpmlint `unstripped-binary-or-object` | normal for Qt apps | ignore it; you want **0 errors**, not 0 warnings |
| Build exits 0 but rpmlint printed hundreds of `E:` lines | the Platform SDK image sets `TreatErrorsAsWarnings` | read the rpmlint output; exit code is not the verdict (`02-build-and-package.md`) |
| A rebuilt RPM does not replace the installed one | same `name-version-release`, and `rpm -Uvh` refuses | `--force`, or bump `Release` (`03-device.md`) |
| `pkcon install-local` over SSH ends `user declined simulation` | no polkit agent in the SSH session | `devel-su rpm -Uvh --force`, or run `pkcon` from the device UI |
| rpmlint `explicit-lib-dependency` | a hard `Requires: lib*` for an optional QML plugin | Load the QML through a `Loader`; require the QML plugin package only if it is mandatory |

## QML & Silica

| Symptom | Cause | Fix |
|---|---|---|
| A component "is not a type" at runtime, nothing at build time | the type does not exist in this Silica version (e.g. **`ButtonLayout`**) | the build never validates QML — check `/usr/lib64/qt5/qml/Sailfish/Silica/` first |
| `TypeError: Property 'x' is not a function`, repeating forever | a `function x()` **shadowed a `property … x`** of the same name | rename one; add the name-collision test (`05-python-pyotherside.md`) |
| UI dead on arrival with no obvious error | the above, thrown inside a `Timer` | mirror Qt warnings into the app's log (`03-device.md`) — this is invisible otherwise |
| Text/icons invisible on some screens | one flat colour cannot survive both a dark video and a light theme background | white glyph on a translucent dark disc; outlined white text (`04-qml-and-silica.md`) |
| `Qt.callLater`, inline `component`, `Connections.enabled`, `Screen.hasCutouts` misbehave | Qt 5.6 floor | see the table in `04-qml-and-silica.md` |
| A "missing" plugin you know is installed | looked in `/usr/lib/qt5/qml`, but 64-bit lives in **`/usr/lib64/qt5/qml`** | fix the path (`Nemo.KeepAlive` lives in the **`libkeepalive`** package) |
| Canvas art vanishes on minimise, or after lock/unlock | a `Canvas` keeps nothing across a scene-graph rebuild, and lock/unlock does not change `Qt.application.active` so the repaint never fires | draw it as an `Image` overlay (`04-qml-and-silica.md`) |
| A `TimePicker` shows a dial but no time | the digits/hands come from `ClockItem`, which is **not** an exported type | use the public `TimePickerDialog` |
| `playing` / `onPlayingChanged` "does not exist" on `MediaPlayer` | `MediaPlayer`/`Audio` have no `playing` property, only a `playing` signal | `onPlaybackStateChanged: playing = (playbackState === MediaPlayer.PlayingState)` |
| Page fails with "Column.topPadding is not available in QtQuick 2.0" | positioner padding is newer than the `import QtQuick 2.0` floor | use `spacing` or a spacer `Item` |
| A flag written on `ListModel.get(i)` never sticks | `get()` returns a JavaScript copy, not a live row | `model.setProperty(i, role, value)` (`04-qml-and-silica.md`) |
| History reloads / duplicate rows on every scroll | a `get()`-copy guard is always false, so the fetch repeats | persist the guard with `setProperty`, and debounce the scroll handler |
| Message load janks | `onCountChanged: forceLayout()` does a full synchronous relayout per item | remove it or debounce with a 50 ms `Timer` |
| Notification not delivered while minimised | the app is suspended; notifications only run with the process | `KeepAlive` for realtime (battery) or `BackgroundJob` for periodic; neither survives closing the app (`04-qml-and-silica.md`) |

## PyOtherSide & the engine

| Symptom | Cause | Fix |
|---|---|---|
| Host tests cannot import the engine | `import pyotherside` (or other device-only module) at module top level | import it *inside* the function that needs it |
| UI stutters while a slow engine call runs | everything shares one worker lane | give slow work its own `Python` element (`05-python-pyotherside.md`) |
| A long operation blocks the lane the UI needs now | the lane queues instead of refusing | return `{ok:false, error:"busy"}` immediately and retry later |
| Prefetching cannot keep up with the user | one lane is serial; a token'd resolve is 6–7 s | add a second lane — parallel lanes are the fix that worked |
| A Python traceback is invisible | `onError` not wired, or not mirrored to a log | wire it on every `Python` element |
| A scheduled task silently does nothing | `run_coroutine_threadsafe(...)` future's exception was never read | add a done-callback that logs `future.exception()` (`05-python-pyotherside.md`) |
| A user reports an error you cannot reproduce | it was only shown in a transient notification | also `logging.error()` in the shared `show_error` helper |

## Media

| Symptom | Cause | Fix |
|---|---|---|
| 403 on playback, identical headers work elsewhere | GStreamer's libsoup stack is rejected by googlevideo | loopback proxy (`08-media-playback.md`) |
| Seeking mangles mp4 audio, or the app OOMs | `qtdemux` cannot push-seek; a downloadbuffer in `/tmp` (tmpfs) grows in RAM | downloadbuffer + `KEY_UNIT` for mp4; redirect `TMPDIR` to flash **in `main()`** |
| Seeking picks the wrong branch | `videoExt`/`audioExt` were set *after* the URLs | set extensions first — they choose the seek plan |
| Stutter blamed on the decoder | it was the pre-warm competing for bandwidth | throttle the pre-warm; never warm the playing stream; **measure before blaming the decoder** |
| A partially warmed item plays with a stutter | the audio warm finished first, and the readiness flag was set by *whichever* warm finished | count in-flight warms per item; open the gate only at zero |
| The "preparing" wait is seconds long | the warm fetched far more than the player's ~1 s read-ahead, at a capped rate | warm ~1 s of read-ahead, not megabytes |
| Gated swiping waits forever | the readiness poll watched one id, which a later prefetch overwrote | recompute the awaited id every tick; auto-release when ready |
| Video keeps looping and nothing advances | a gate refused the swipe and never released — and a finished item loops | check your gate's release path before blaming the feed |
| Sandboxed playback is silent, no error at build time | the `Audio` sailjail permission is missing, so the sink cannot reach PulseAudio (`Failed to connect: Connection refused`) | `Permissions=Internet;Audio` (`08-media-playback.md`) |
| Reached for a loopback proxy and got complexity for nothing | only googlevideo needs it | plain HTTPS streams (e.g. LISTEN.moe Ogg Opus) play fine sandboxed |

## YouTube

| Symptom | Cause | Fix |
|---|---|---|
| "Sign in to confirm you're not a bot", all clients | per-connection rate-limiting | transient; also caused by hammering from the command line while testing |
| Authenticated extraction returns storyboards only | no PO token (SABR) | Deno + bgprovider, `09-youtube-and-innertube.md` |
| Storyboards only **with** a PO provider installed | Deno is not on `PATH`, so yt-dlp's EJS solver fails the n-signature challenge | put Deno first on `PATH` — this looks *identical* to the SABR gate |
| The provider's plugin never loads | `--plugin-dirs` pointed at `plugin/`, but yt-dlp globs `<dir>/*/yt_dlp_plugins` | point it at the **repo root**; `--no-plugin-dirs` first |
| The feed repeats items / pages arrive as "1 item, already seen" | paged with a **per-entry** continuation token (a comment thread) | prefer the page-level `continuationEndpoint` |
| Random languages in audio | sorted audio formats by bitrate; **dubs often out-rank the original** | pick the track marked `original (default)` |
| Wrong diagnosis from format ids | the `-N` suffix is a **track index**, not a language code | never infer language from it |
| User shown as signed out with a valid session | merged `.google.com` cookies over `.youtube.com` ones (different `SID` values) | select the `.youtube.com` rows |
| The `/shorts/` request returns nothing | a mobile `User-Agent` gets no data | use the desktop UA for that endpoint |
| A "server is running" that is not | a bare TCP connect succeeded against a dying socket | HTTP-ping for liveness |
| A helper dies seconds after starting | `PR_SET_PDEATHSIG` is thread-scoped | spawn it from a dedicated long-lived thread |

## Process

| Symptom | Cause | Fix |
|---|---|---|
| Two versions disagree | the engine's version constant and the RPM `Version:` drifted, and shipped | a test asserting they match |
| `journalctl` says `insufficient permissions` | `defaultuser` is not in `systemd-journal`; `--user` does not help | `devel-su journalctl`, or launch via `invoker` with output redirected (`03-device.md`) |
| An SSH one-liner dies with exit 255 after `pkill` | `pkill -f /usr/bin/harbour-myapp` also matched the shell running the command | use `pkill -x <comm>` or kill the PID from `/proc` |
| `pgrep -x harbour-myapplication` finds nothing | Linux `comm` is truncated to 15 characters | match the truncated name, or read `/proc/*/comm` |
| `devel-su -c "…"` fails with `Failed to exec` | `devel-su` has no `-c`; it executes its arguments directly | `devel-su rpm -Uvh --force …`, with `ssh -t` for the prompt |
| `ps -p <pid>` is an invalid option | BusyBox `ps` on the device | plain `ps`, `ps -o pid,args`, or `/proc` |
| "It worked yesterday" with no explanation | no devlog | log measurements, not just changes |
| Fixing it again next week | the *reason* was never written down | decision log entry, including the cost |
| A plausible fix that changes nothing | it was a theory, not a reproduction | instrument → reproduce → then change one lever |
| Stale screenshots in the store listing | the UI changed after publishing | re-shoot as part of the release checklist |
| A reset the user cannot reach | state lives in the app process with no UI for it | either persist it, or give it a "start fresh" control |
