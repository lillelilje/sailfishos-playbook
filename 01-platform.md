# 01 — The platform

**Read when:** you need to know what the OS gives you, what is forbidden, or why something is the
way it is. Start here for any new project.
**Skip when:** you already know the target and just need the build or the UI.

---

## OS versions and devices

**VERIFIED 2026-10-10, version refreshed 2026-11-23** (from release notes, sibling project research):

| Train | Version | Notes |
|---|---|---|
| **Finlayson** | 5.2.0.x | latest **`5.2.0.22`**, released to **all** supported devices 2026-10-26 (`5.2.0.15`…`5.2.0.20` were Jolla Phone only) |
| *(5.3)* | — | previewed at Slush on a Jolla Phone in Nov 2026, **not released**. **date-sensitive** |
| Pispala | 5.1.0.11 | broad release, 2026-06-16 |
| Tampella | 5.0.0.x | previous train |

- **Jolla Phone 2026** is the reference device and runs 5.2. **The container build still targets
  `5.2.0.15`** — SDK targets lag the device patch level, and building against an older patch level
  is the safe default.
- Architecture: Xperia XA2 / Xperia 10 are `armv7hl`; **10 II+, Jolla C2 and Jolla Phone 2026 are
  `aarch64`.** New projects: **aarch64 only**.
- The user account is **`defaultuser`** on Sailfish 5.x (`nemo` only on ancient releases).

## App framework

- Apps are **Qt 5.6 + QML + Sailfish Silica**. Silica is upstream-unsupported since 2023 but is the
  only stable native toolkit. **The Qt 5.6 floor is real** — see `04-qml-and-silica.md` before you
  write QML on autopilot.
- Native pieces: `Sailfish.Silica`, `libsailfishapp`, the `SailfishApp` booster.
- **Keel** is a beta Qt 6 reimplementation of the Silica API (MIT), distributed via the **Reef**
  store, tested only on Jolla Phone 2026 / 5.2.0.18. "Qt 6 today" effectively means "Reef today",
  not Storeman. Treat as a future port, not a target. **date-sensitive**.
- Jolla's own guidance discourages new language runtimes; C++ + QML is the sanctioned pairing.
  Python via PyOtherSide works in practice and is used by the sibling apps, but it is a decided
  departure — put it in the decision log.

## Sandboxing (Sailjail)

- Every app is sandboxed unless the `.desktop` says otherwise.
- Declared in the desktop file:
  ```ini
  [X-Sailjail]
  Permissions=Internet
  OrganizationName=org.myapp
  ApplicationName=MyApp
  ```
- Harbour-allowed permissions include: `Audio`, `Bluetooth`, `Camera`, `Internet`, `Location`,
  `MediaIndexing`, `Microphone`, `NFC`, `RemovableMedia`, `UserDirs`, `WebView`, `Documents`,
  `Downloads`, `Music`, `Pictures`, `PublicDir`, `Videos`, `Compatibility`, `Secrets`, `Contacts`,
  `Accounts`.
- Notable **not** allowed by Harbour: `Calendar` (which is why calendar-based reminders push an app
  off Harbour).
- **The sandbox is disabled when you launch from an IDE/terminal.** Test the real profile
  explicitly: `sailjail /usr/bin/harbour-myapp`.
- Unsandboxed is a legitimate choice — but it means **no Jolla Harbour**, so OpenRepos/Storeman. Apps
  that spawn helper binaries (yt-dlp, a PO-token server) or run a localhost proxy have no choice.

## APIs worth knowing

Base: `Qt5Core/Quick/Qml/Gui`. Storage: `libQt5Sql` + `libsqlite3`, or `QtQuick.LocalStorage 2.0`.
Notable plugins (with the current import names — older names are deprecated, see below):

- `Nemo.Notifications 1.0` — persistent user notifications (`nemo-qml-plugin-notifications-qt5`).
  Per-channel grouping and lifecycle: see `04-qml-and-silica.md`.
- `Nemo.Configuration 1.0`, `Nemo.DBus 2.0`.
- `Nemo.Alarms` (`nemo-qml-plugin-alarms-qt5`) — creates `timed` alarms with **no permission**;
  recurrence is weekdays only, and they appear in the Clock app.
- `Nemo.KeepAlive 1.2` — `DisplayBlanking` (screen), `KeepAlive` (prevent device suspend) and
  `BackgroundJob` (periodic wake). Plugin in `libkeepalive` at
  `/usr/lib64/qt5/qml/Nemo/KeepAlive`; choosing between them: `04-qml-and-silica.md`.
- `Sailfish.Secrets` — secure storage.
- Calendar via `nemo-qml-plugin-calendar` needs the `Calendar` permission (not Harbour-allowed).

**VERIFIED 2026-10-12:** reading or writing the clipboard needs **no** sailjail permission.

## Platform services, and their traps

- **Notifications** while the app runs are easy and need no extra permission. A *suspended* app
  cannot receive or reschedule them, so anything that must fire later has to go through the OS, or
  the app must opt into staying alive:
  - realtime (network/socket) while minimised: `Nemo.KeepAlive` `KeepAlive` — prevents device
    suspend, battery cost; make it an explicit setting;
  - periodic polling: `BackgroundJob` — wakes the process on a 30 s–24 h interval, notifications are
    delayed;
  - anything that must fire after the app is closed: a separate daemon/service, or OS scheduling
    (`timed` alarms via `Nemo.Alarms`, or a calendar event). Recurring "every N days" is not
    expressible as a `timed` alarm (weekdays only) — a calendar event is the usual answer.

  **VERIFIED 2026-10-10** (Dollfin) for the OS scheduling; **VERIFIED 2026-11-23** for the
  `Nemo.Notifications` QML path. Whether `KeepAlive` beats suspension on a given OS release is
  **unverified** — test on that release. Implementation: `04-qml-and-silica.md`.
- **Colour emoji do not render** through plain Qt text: the device's Noto Color Emoji is COLRv1 and
  Qt 5.6/FreeType cannot draw it, so you silently get monochrome. The community fix is the
  **sailor-emoji** packs under `~/.local/share/sailor-emoji/` plus the shared dconf key
  `/apps/sailor-emoji/currentStyle`; reading them from a sandboxed app needs a read-only sailjail
  profile installed to `/etc/sailjail/permissions/`. **VERIFIED 2026-10-10** (Emojinal Support).
- **`unzip`/`tar` processes are blocked by the sandbox's `private-bin`.** Unpack in-process instead
  (e.g. `QZipReader` from `QtGui/5.6.3/.../private/qzipreader_p.h`, needs `QT += gui-private`).
- **Audio playback needs the `Audio` sailjail permission.** With `Internet` alone the app fetches
  metadata and opens the stream but the sink cannot reach PulseAudio
  (`Failed to connect: Connection refused`). Use `Permissions=Internet;Audio` (`08-media-playback.md`).
- **Lockscreen "now playing" and media keys are MPRIS** via `Amber.Mpris`
  (`amber-qml-plugin-mpris`); the `Audio` permission is what allows owning
  `org.mpris.MediaPlayer2.*`. **`org.nemomobile.mpris` is gone** on 5.x — files importing it silently
  fail (`08-media-playback.md`).
- **The system volume cannot be read or set from a sandboxed app.** `Nemo.Mce` is read-only,
  `Nemo.Policy` exposes audio *priority* not volume, the PulseAudio D-Bus has no volume node, and
  `private-bin` blocks `pactl`. Do not chase PulseAudio's sink volume with `dlopen` and hand-declared
  ABI — one attempt crashed the app, and it is not worth it for a warning.
- **Timers that must fire later cannot live in the app alone.** A suspended app cannot wake itself and
  a sandboxed one cannot relaunch itself, so an in-app timer only works while the app is open (say so
  in the UI), or go through the OS (`Nemo.Alarms` `timed` alarms, weekdays only, or a calendar event).

## Deprecations to avoid (since 5.1)

- Libraries: `libssl.so.1.1` / `libcrypto.so.1.1` deprecated; `libpng15`, `libssl.so.10`,
  `libcrypto.so.10` dropped.
- **QML imports were renamed** — use the new names in new code:
  - `org.nemomobile.notifications 1.0` → **`Nemo.Notifications 1.0`**
  - `org.nemomobile.dbus 2.0` → **`Nemo.DBus 2.0`**
  - `org.nemomobile.configuration 1.0` → **`Nemo.Configuration 1.0`**

## Reference reading

- <https://docs.sailfishos.org/Develop/Apps/> — the app docs index.
- <https://docs.sailfishos.org/Develop/Apps/Application_Permissions/> and
  <https://docs.sailfishos.org/Develop/Apps/Harbour/Allowed_Permissions/>
- <https://docs.sailfishos.org/Develop/Apps/UI/Definition_of_Done/> — the UI quality bar.
- <https://github.com/sailfishos/sailjail-permissions> — what each permission actually grants.
