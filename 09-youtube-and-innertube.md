# 09 — YouTube: yt-dlp, PO tokens, InnerTube

**Read when:** the app talks to YouTube, or playback suddenly stopped working.
**Skip when:** it does not.

Everything here is **date-sensitive**. YouTube changes without notice; if something below does not
match what you observe, **the observation wins** and this file should be corrected.

---

## Rule zero: manage yt-dlp yourself

**Do not make yt-dlp an RPM dependency.** The distro copy will be stale exactly when extraction
breaks — which is often, because extraction is the part YouTube keeps changing. Every project here
fetches and updates its own.

The working recipe (**VERIFIED 2026-10-11**):

- Asset: **`yt-dlp_linux_aarch64`** from the **nightly** builds repo
  (`github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/…`). It is a self-contained
  binary — no Python, no dependencies. The nightly channel carries extraction fixes first.
- **Verify it**: each release publishes `SHA2-256SUMS`; check the download against it.
- Download to a `.part` file, `chmod 0755`, `os.replace` into place, then **run it** and keep it only
  if it prints a version.
- Install to a **shared** path (`~/.local/bin/yt-dlp`) so sibling apps find the same copy, and look
  for existing copies (PATH, other apps' data dirs) before downloading.
- Track **staleness** from the version's date (`YYYY.MM.DD…`) and offer an update in Settings.
- Run it **nice**d and on a worker thread (`05-python-pyotherside.md`).

FinTube additionally runs an **importable zipapp in-process** for the hot path, because the frozen
binary pays a ~1.1 s unpack on *every* spawn. If resolve latency matters, that is the biggest single
win available. If you do it, **keep binary and zipapp on the same channel** — the two-form split is a
known footgun.

## Format selection: by property, never by itag

- Rank by **properties** — codec family, height, fps, language — not by a hardcoded itag list. Itags
  rotate and a fixed list silently loses variants.
- **Exclude AV1 (`av01`)**: there is no on-device decoder.
- Prefer H.264 for software decode, VP9 when leaner/decodable, and expose a quality cap.

### The dub bug (read this before writing the audio picker)

**VERIFIED 2026-10-12.** YouTube lists every language dub as a **separate audio format with the same
itag**, and **dubs frequently have a higher bitrate than the original**:

```
251-19  opus  131.3 kbps  lang=ta     "Tamil, medium"
251-20  opus  119.6 kbps  lang=en-US  "English (US) original (default), medium"   ← wanted
```

So "sort by bitrate" plays a random language. Select the track yt-dlp marks **`original (default)`
in `format_note`**, and let bitrate only break ties between unmarked tracks.

**And do not read meaning into the `-N` suffix** (`251-19`). It is a **track index, not a language
code** — `251-17` was the *English* original for one video and the Tamil dub for another. It caused a
*wrong* diagnosis once already.

## PO tokens: the current reality

**VERIFIED 2026-10-12.** If the app cannot play anything and looks "blocked", this is almost
certainly why.

- **Anonymous** extraction may be bot-walled: `Sign in to confirm you're not a bot`, across *all*
  player clients. It is **per connection/IP and transient**.
- **Authenticated** (cookies) extraction returns **storyboards only** — SABR-only responses, no
  fetchable media — because YouTube now requires a **Proof-of-Origin token** for signed-in clients.
- **Neither** is fixable by choosing a different client. `web`, `mweb`, `ios`, `tv`, `android_vr`,
  `web_safari`, `web_embedded`, `tv_simply`, `web_creator`, `android_producer`, `visionos`: all
  either bot-walled or empty.

### What actually fixes it

A PO-token provider, plus a Deno runtime. Both, and the second is the trap:

1. **Deno** (aarch64 build), checksum-verified, plus the **bgutil PO-token provider** (a yt-dlp plugin
   and a local Deno HTTP server that keeps a BotGuard VM warm and mints a token per video).
2. **Deno must be on `PATH`** — not only to *run* the provider server, but because yt-dlp's bundled
   **EJS challenge solver needs a JS runtime to solve the n-signature challenge**. Without it you get
   `n challenge solving failed` → **storyboards only**, which looks *identical* to the SABR gate and
   will send you hunting in the wrong place.
3. **The plugin directory must be the repo root** — yt-dlp globs `<dir>/*/yt_dlp_plugins`, so
   pointing at the repo's `plugin/` subdirectory finds nothing.
4. Pass `--no-plugin-dirs` **first**, then `--plugin-dirs <repo root>` — otherwise yt-dlp also scans
   `~/.config/yt-dlp/plugins` and a stray manual install there silently shadows yours.

The working invocation, verified to yield 26 formats including 1080p:

```sh
PATH="$HOME/.local/bin:$PATH" yt-dlp --cookies <jar> \
  --no-plugin-dirs --plugin-dirs <repo-root> \
  --extractor-args "youtube:getpot_bgutil_baseurl=http://127.0.0.1:4416" \
  --list-formats <url>
```

Server, sandboxed to least privilege:

```sh
deno run --allow-net --allow-env --allow-read=<server-dir> \
         --deny-write --deny-run --deny-ffi \
         --v8-flags=--max-old-space-size=8192 src/main.ts
```

(The BotGuard VM peaks above the default heap.)

### Operational details that cost time

- **Liveness is an HTTP `/ping`, not a TCP connect.** A bare `connect()` succeeds against a socket
  that is already dying, so the app reported "server is running" without ever starting one.
- **Do not trust an open port.** Reusing "whoever is on port 4416" is asking for a stale server.
- **Log the sidecar to a file**, never `DEVNULL`. Its startup line is the only way to tell a crashed
  server from a slow one.
- **`PR_SET_PDEATHSIG` is thread-scoped.** If you tie a helper's lifetime to the parent, spawn it from
  a dedicated long-lived thread; forking it from a short-lived caller gets it SIGKILLed when that
  caller returns (FinTube learned this the hard way).
- Budget the cost: a mint is ~1 s and a token'd resolve landed around **6–7 s** end to end. A resolve
  per item at 7 s cannot keep up with a user browsing at 4 s — plan the pipeline around that number
  (see the gating notes in `08-media-playback.md`).

Honest summary of what a PO token buys: **age-restricted and members-only media start working, and
authenticated identity is preserved** — at the cost of a ~40 MB Deno runtime and a supervised local
process. If the app only ever plays public media and anonymous extraction is not walled *for that
user*, the dependency is optional. It was not optional here.

## InnerTube: talking to YouTube as the user

The feed, likes and watch state come from YouTube's own private API, driven with the imported
session. Two endpoint families:

- **Browse** — `FEwhat_to_watch` (home), `FEsubscriptions`, etc. Grid responses. In a grid, a Short
  is a `shortsLockupViewModel`; its id lives at `onTap…reelWatchEndpoint.videoId` (or the `entityId`
  tail). A page may contain **no** Shorts at all, so page past them rather than assuming.
- **The Shorts reel** — `browse FEshorts` **400s**; the working route is a **seedless reel
  sequence**: `GET https://www.youtube.com/shorts/` → read `ytInitialData` for the first reel and the
  top-level **`sequenceContinuation`**, then `POST reel/reel_watch_sequence {continuation}` for more.
  Each response carries entries *and* a new continuation.

### The continuation-token trap

**VERIFIED 2026-10-12.** A naive recursive walk for "the first `continuationCommand`" finds a
**per-entry token first** — a reel entry carries two of its own, for comments. Paging with one of
those asks YouTube to continue a *comment thread* and re-serves **the same short**, which looks
exactly like "the feed is repeating items" and starves any prefetcher downstream.

**Preference order: the page-level `continuationEndpoint`, then a `continuationItemRenderer`, and
only then any `continuationCommand`.** Fixing this took one page from "1 item, already seen" to
"8–14 items, all new".

### Other InnerTube facts

- **The desktop `User-Agent` is load-bearing** for the `/shorts/` seed: a mobile Android UA returns
  **no data at all**.
- **Session cookies must come from `.youtube.com` rows**, not `.google.com` — the two hosts hold
  *different* `SID`/`SAPISID` values, and a name-keyed merge silently lets `google.com` win and
  reports the user as signed out.
- **Hand yt-dlp an ephemeral `0600` cookie file** for the duration of a call and delete it after,
  rather than leaving a plaintext jar on disk.
- Both the browser and the app share the account's watch state, so their "resume position" is not
  something you can pin down. `/shorts/` returns a rotating `replacementEndpoint` per request, with
  or without cookies.
- **Watched reporting:** yt-dlp `--mark-watched` with the session reports *watched / not watched*.
  Real view counts need the player's periodic beacons, which is a much bigger project — decide
  explicitly whether you care.
- **Be gentle with volume.** Heavy command-line testing from a single connection is a plausible cause
  of an IP-level bot wall that then breaks the app under test. Space out probing.

## The discipline this file is really about

Every expensive mistake in this area came from accepting a plausible story instead of a measurement:
"authenticated requests must be faster", "the decoder is dropping frames", "`251-17` means Tamil".
Write down what you measured, with the date, and prefer it to the explanation.
