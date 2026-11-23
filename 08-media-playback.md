# 08 — Media playback

**Read when:** the app plays video or audio, or you are fighting stutter.
**Skip when:** it does not.

Dense, because this is the area with the most non-obvious, hard-won facts. All **VERIFIED** on a
Jolla Phone 2026 unless stated.

---

## The one fact that dictates the architecture

**GStreamer's libsoup HTTP stack gets an unfixable 403 from googlevideo. `urllib` with byte-identical
headers gets a 206.**

So streaming media in a Qt/GStreamer app here requires an **in-process localhost HTTP proxy**: the
player is given `http://127.0.0.1:<port>/…`, and the proxy re-fetches the real URL with the format's
own `User-Agent` and serves backpressured byte ranges.

Consequences worth stating up front:

- The proxy is why such an app **must run unsandboxed** and therefore **cannot ship on Jolla
  Harbour**.
- **HLS manifests pass through unproxied.** Proxying a manifest rewrites/breaks the segment URLs.
- Give the proxy a **token per stream** (`/<kind>/<n>`) rather than passing URLs in, so the player
  never handles the real URL and the server can swap it underneath when it expires.

## Not every stream needs the proxy

The proxy above exists **only** for googlevideo's 403. A plain HTTPS stream plays fine sandboxed —
LISTEN.moe's Ogg Opus radio (Nekofish) is `audio/ogg`, 48 kHz stereo, and plays through QtMultimedia
under Sailjail with no proxy, no helper and no C++. That is what keeps such an app Harbour-eligible.

**The `Audio` sailjail permission is required for playback.** With `Internet` only, the app fetches
metadata and opens the stream, then the sink logs `GST_MESSAGE_STREAM_COLLECTION` followed by
`Warning: "Failed to connect: Connection refused"` and stays silent — the sandbox is blocking
PulseAudio. `Audio.permission` whitelists `${RUNUSER}/pulse`; set `Permissions=Internet;Audio`.
**VERIFIED 2026-10-12** (Nekofish). Ogg/Opus decode needs `libgstogg`/`libgstopus` (present by
default). Do not add the proxy reflexively.

## Lockscreen now-playing and media keys (MPRIS)

Use **`Amber.Mpris`** (`import Amber.Mpris 1.0`; package `amber-qml-plugin-mpris`, shipped with the
OS). An `MprisPlayer` with `serviceName`, `identity` and grouped
`metaData { title; contributingArtist; albumTitle; artUrl }` (`contributingArtist` → `xesam:artist`)
puts the track on the lockscreen, and its `playRequested`/`pauseRequested`/`stopRequested` signals
route back to the app. The `Audio` permission already grants
`dbus-user.own org.mpris.MediaPlayer2.*`. **VERIFIED 2026-10-12** (Nekofish).

**`org.nemomobile.mpris` no longer exists** on SFOS 5.x — a file importing it silently fails to load
(FinTube shipped one). Load the MPRIS object through a `Loader` so a missing plugin degrades quietly.

## Formats and seeking

- **`qtdemux` cannot push-seek.** So: `mp4`/`m4a` branches get an on-disk **`downloadbuffer`** plus
  `KEY_UNIT` seeks; `webm`/`matroska` seek exactly with `FLUSH | ACCURATE`.
- **Set `videoExt`/`audioExt` *before* the URL properties.** They choose the per-branch seek plan when
  the pipeline is built, so the order is part of the API. (Muxed mode must *clear* them.)
- **`/tmp` is tmpfs on Sailfish** — a downloadbuffer there grows in RAM until the phone dies.
  Redirect `TMPDIR` to a flash path **in `main()`, before anything reads it**, and clear stale spill
  from a previous crash.
- Separate video-only + audio-only DASH tracks are the norm; YouTube retired the muxed fallback
  years ago. Forcing a muxed path will eventually fail.

## Hardware decode

- The path is a **`droidvdec` → `droideglsink`** chain with an EGLImage (zero-copy) rendered into a
  `QQuickPaintedItem`.
- **Demote `droidvdec` to `GST_RANK_NONE` in `main()`** and instantiate it *explicitly* in the
  pipeline — autoplug will not reliably select it.
- **Software decode is the safer default**; hardware decode power/latency benefits may be real but
  were not demonstrated. Ship hardware behind a toggle.

## The stutter lesson (worth internalising)

An earlier conclusion was "hardware decode renders nothing, software only". That was **wrong on both
counts**:

1. The actual bug was a reveal gate — the "first frame arrived" flag was only ever set on the
   software path, so hardware output stayed hidden.
2. The remaining stutter lined up with the **pre-warm competing for bandwidth**, not with the decoder.
   Throttling the pre-warm and not warming the currently-playing stream removed it.

**Do not attribute stutter to the decoder without a measurement.** Check what else is using the
network — usually the thing you just added for performance.

## Pre-warming: making a transition feel instant

The trick is to fetch the **first bytes of the next item into memory** before it is needed, so the
player's first read is a memory hit rather than a round trip.

Rules that came out of measuring this:

- **Warm only what is not playing.** Warming the stream you are about to play races the player's own
  buffering and causes first-play stutter.
- **Throttle it.** An unthrottled pre-warm starves the playing stream, and the sink drops frames. A
  rate cap of a few Mbit/s was enough to make it invisible.
- **Warm roughly one second of read-ahead, not several.** Warming 2 MB where ~0.5 MB is needed cost
  ~4 s of waiting per item at the capped rate — and that wait was the biggest single component of a
  "preparing" spinner.
- **Do it on a background thread, and expose a "is it ready" query.** A boolean per item
  (`stream_ready(id)`) lets the UI gate on readiness without blocking anything. A *failed* warm must
  still count as ready, or an error wedges the gate forever.
- **Count every track.** A video has a separate audio track, and the audio warm finishes seconds
  before the video one. Opening the gate on the first finished warm let playback start with a cold
  video track — the exact stutter the warm existed to prevent. Count in-flight warms per item and open
  the gate only at zero.

## If you gate the UI on readiness

Optionally, refusing to advance until the next item is primed removes stutter entirely. If you do:

- Gate on **primed**, and make the wait **visible** ("Preparing the next short…") and **self-releasing**
  — auto-advance the moment it becomes ready rather than making the user swipe again.
- Make sure one slow item can never trap the user; allow going *back* unconditionally (it has just
  been played, so it is already warm).
- **Recompute what you are waiting on every tick.** Watching a single id meant a later prefetch
  overwrote it, the awaited item stopped being checked, and the gate never released.
- **Expect it to be wrong if the pipeline cannot keep up.** If a transition takes ~7 s and the user
  browses every ~4 s, gating guarantees a wait on every item. Measure the pipeline rate, then either
  parallelise it or do not gate.

## Mid-stream failures

URLs expire and 403. Keep a **re-resolve path**: on a 403, re-resolve and resume at the same byte
offset with the same format id, so the client sees a seamless continuation. Do not surface an
expired URL as a playback error.

**Unverified:** whether the player recovers cleanly from a 403 mid-stream without a restart was never
confirmed; treat a track dying on a 403 as an open risk and test it.
