# 04 — QML and Sailfish Silica

**Read when:** you are writing or reviewing any QML, or a UI looks wrong on the device.
**Skip when:** you are only touching the engine.

This file exists because the build toolchain **does not validate QML at all**. An unknown component
or a name collision compiles fine and fails on the phone. Read this before writing UI on autopilot.

---

## The Qt 5.6 floor

Silica is frozen on Qt 5.6. **VERIFIED 2026-10-11.** Things that will silently or loudly break:

| Don't use | Because | Do instead |
|---|---|---|
| `Qt.callLater` | not in 5.6 | restart a zero-interval `Timer` |
| `Connections { enabled: … }` | `enabled` is 5.7+ | set `target: null` to disable |
| inline `component Foo: …` | 5.15+ | a separate `.qml` file in `qml/` |
| `Screen.hasCutouts` / cutout APIs | newer | `typeof`-guarded, e.g. `Screen.topCutout ? Screen.topCutout.height : 0` |
| modern JS (`?.`, `??`) | unsafe here | plain checks |
| `Column { topPadding: … }` | positioner padding is newer than `import QtQuick 2.0` | use `spacing`, or an explicit spacer `Item` |

**`import QtQuick 2.0` is the norm** in these projects, and `import Sailfish.Silica 1.0`.

---

## Check a component exists before you use it

**VERIFIED 2026-10-12:** `ButtonLayout` **does not exist** in this Silica version. Using it would
have shipped a broken onboarding page — there is no `ButtonLayout.qml` on device.

The Silica QML components live at:

```
/usr/lib64/qt5/qml/Sailfish/Silica/*.qml
```

Before using anything unfamiliar, check it is really there:

```sh
ssh defaultuser@<phone-ip> 'ls /usr/lib64/qt5/qml/Sailfish/Silica/ | grep -i <name>'
```

**Note the path: `/usr/lib64/`, not `/usr/lib/`.** Looking in the wrong tree is why a whole plugin
was once declared "not installed" when it was present.

A cheap sanity check that catches typos across the whole repo: list every `Something {` component in
`qml/`, then diff that set against the Silica directory plus your own components plus Qt's. Anything
left over is suspicious.

Components actually used and known present in these projects: `ApplicationWindow`, `Page`,
`PageHeader`, `SectionHeader`, `DetailItem`, `Button`, `Label`, `Icon`, `IconButton`, `Image`,
`TextSwitch`, `ComboBox`, `ContextMenu`, `MenuItem`, `PullDownMenu`, `SilicaFlickable`,
`VerticalScrollDecorator`, `BusyIndicator`, `SearchField`, `GridView`, `CoverBackground`,
`CoverActionList`, `CoverAction`, `Slider`, `MenuLabel`, `TimePickerDialog`, `ValueButton`.

## Validate QML before it reaches the phone

The build does not parse QML, but a Qt 5 `qmllint` in a throwaway container catches syntax errors
and unbalanced braces in a second:

```sh
podman run --rm -v "$PWD:/w:Z" --entrypoint bash quay.io/fedora/fedora:43 -lc \
  'dnf -q install -y qt5-qtdeclarative-devel >/dev/null && qmllint /w/qml/pages/Foo.qml'
```

It is a **syntax check only**: it does not know `Sailfish.Silica` or `Nemo.*` types, so a clean run
does not prove the properties exist. It does catch the unbalanced-brace/QML-parse class early, which
otherwise only appears on the phone. **VERIFIED 2026-11-23** (Fedora 43, Qt 5.15 `qmllint`,
parse-only against the Qt 5.6 app).

## Static art: an Image, never a Canvas

**VERIFIED 2026-10-12 (Nekofish).** A `Canvas` draws once and its content does **not** survive a
scene-graph rebuild: it vanishes when the app is minimised *and* after the screen locks and unlocks.
`renderTarget: Canvas.Image` plus a repaint on `ApplicationWindow.applicationActiveChanged` fixed the
first but **not** the second — lock/unlock does not change `Qt.application.active`, so the hook never
fires, and a Canvas has nothing left to upload.

For static decoration, generate a PNG and draw it with an `Image`. To keep it theme-aware, tint a
white one with `QtGraphicalEffects` (shipped with Qt; `ColorOverlay` is present on device):

```qml
import QtGraphicalEffects 1.0
Image {
    anchors.fill: parent
    source: Qt.resolvedUrl("../images/overlay.png")
    fillMode: Image.Stretch
    layer.enabled: true
    layer.effect: ColorOverlay { color: Theme.primaryColor }
}
```

It has no paint lifecycle to get wrong.

## `ListModel.get()` is a snapshot

`ListModel.get(i)` returns a JavaScript copy of the row. Writing to it does nothing:

```qml
model.get(i)._seen = true           // silently lost
model.setProperty(i, '_seen', true) // persists
```

A guard written the first way is always false, so the work it guards runs again on every event — for
a history pagination check that means one network request per scroll event and duplicate rows. Use
`setProperty` for bookkeeping roles too. This is standard `ListModel` behaviour; a one-line test
catches it.

## Do not force a layout for every row

`onCountChanged: listView.forceLayout()` turns every appended item into a synchronous full relayout.
A 30-message history load does that 30 times. Let the view handle the insert, or debounce it:

```qml
Timer { id: relayout; interval: 50; onTriggered: listView.forceLayout() }
onCountChanged: relayout.restart()
```

The same applies to scroll handlers: `onContentYChanged` fires per pixel. Put the "load more" check
behind a `Timer` (300–500 ms) instead of running it on every change. The cost is app-specific; profile
before and after if the list is long.

## Pickers, cover actions and MediaPlayer — small API traps

- **`TimePicker` alone is an empty dial.** The digits and hands come from `ClockItem`, which lives in
  `Sailfish/Silica/private/` but is **not an exported type** (absent from that qmldir; importing
  `Sailfish.Silica.private 1.0` yields *"ClockItem is not a type"*). Use the public
  **`TimePickerDialog`**: set `hour`/`minute`, `open()`, read them in `onAccepted` (Dollfin's pattern).
  A `ValueButton` showing the chosen time is a readable summary on the page.
- **`CoverAction` has only `iconSource` (a QUrl) and `triggered()`** — no text. An icon that comes from
  `image://theme/…` is themed; a custom PNG is drawn **as-is**, so coloured flags work, and you can
  force a tint by appending `?<colour>` to the URL.
- **`MediaPlayer` and `Audio` are the same Qt type and have no `playing` property** — only a `playing`
  *signal*. Derive a bool from the state:
  `onPlaybackStateChanged: playing = (playbackState === MediaPlayer.PlayingState)`. There is no
  separate `AudioOutput`; audio output is built in.

## Theming

- Use `Theme.*` for **every** colour, margin, font and duration. `Theme.paddingLarge`,
  `Theme.itemSizeSmall`, `Theme.fontSizeMedium`, `Theme.horizontalPageMargin`, …
- `Theme.highlightColor` is the accent, `Theme.primaryColor` the body text, `Theme.secondaryColor`
  the quieter text, `Theme.rgba(colour, alpha)` for translucency.
- **`Theme.backgroundColor` does not exist** on this Silica — do not reach for it.
- Icons: monochrome theme icons under
  `/usr/share/themes/sailfish-default/silica/z1.5/icons-monochrome/`. Check the name exists;
  `icon-m-like` and `icon-m-outline-like` do, `icon-m-more` does not. The **launcher** icon (the
  artwork under `icons/hicolor/`) is a different thing — `15-icons-and-art.md`.

### Icons and spinners are tintable

- `Icon` has a `color` property (defaults to `Theme.primaryColor`).
- `IconButton` exposes `icon.color`.
- `BusyIndicator` has a `color` property (aliased to its inner image) and defaults to the highlight
  colour.
- `Label` descends from `Text`, so `style: Text.Outline` + `styleColor` work on it.

## Contrast over video — the rule that took three attempts

**VERIFIED 2026-10-12.** Anything floating over media has to survive *two* backgrounds at once,
because a letterboxed video leaves the app's own background visible around it:

- icons, spinners → **translucent dark disc + white glyph**
  (`Rectangle { radius: width/2; color: Theme.rgba("black", 0.35..0.45) }` with an `Icon` or
  `BusyIndicator` painted white)
- text → **white with a dark outline**
  (`color: "white"; style: Text.Outline; styleColor: Theme.rgba("black", 0.55)`)

Why not one flat colour: `Theme.primaryColor`/`secondaryColor` are dark and vanish on dark video;
pure white vanishes on a light theme colour. Both were shipped and both were wrong.

## Keep the display awake

```qml
import Nemo.KeepAlive 1.2
DisplayBlanking { preventBlanking: true }
```

**VERIFIED 2026-10-12:** the `Nemo.KeepAlive` plugin ships inside the **`libkeepalive` package** at
`/usr/lib64/qt5/qml/Nemo/KeepAlive/` — it is *not* a separate `nemo-qml-plugin-keepalive` RPM, which
is why a package search comes up empty and people conclude it is missing. Wrap it in a `Loader` so a
device without it degrades quietly instead of throwing.

## Foreground vs background

`Qt.application.state` is the reliable signal:

```qml
property bool active: Qt.application.state === Qt.ApplicationActive
```

Use it to pause animations/GIFs and to feed the engine
(`onActiveChanged: py.runUpdate('active', active)`). A page's `PageStatus.Active` is not the same
thing: the page stays active when the app is on the cover.

## Notifications

`Nemo.Notifications 1.0` publishes from a sandboxed app with no extra sailjail permission. The
simplest form is a `Notification` object with `summary`/`body` and `publish()`.

For per-channel chat-style notifications, create one `Notification` per channel at runtime and keep
the object; its `replacesId` is filled in after the first `publish()` and later publishes update the
same entry instead of stacking:

```qml
function notify(channelId, summary, body) {
    var n = _notifications[channelId]
    if (!n) n = _notifications[channelId] = Qt.createQmlObject(
        'import Nemo.Notifications 1.0; Notification { isTransient: false; expireTimeout: -1 }',
        root)
    n.summary = summary
    n.body = body
    n.previewSummary = summary  // lock-screen/preview text
    n.urgency = Notification.Normal
    n.publish()
}
```

- A replacement publish does **not** alert again; use `itemCount` and grouping rather than one
  notification per message.
- `clicked`/`actionInvoked` only fire while the process is alive. A tap when the app is closed just
  opens the app; jumping to a specific page needs a D-Bus remote action (`remoteActions`).
- `close()` on the stored object clears that channel's entry; do it when the user opens the channel.
- `Notification.Critical` can surface through the lock screen/notification list; use it for mentions,
  `Normal` for the rest.

The catch is the app lifecycle: notifications only arrive while the process runs. A minimised
Sailfish app is suspended; see the background options below.

## Keeping a connection alive in the background

Three levels, all in `Nemo.KeepAlive 1.2`:

| Type | What it does | Use |
|---|---|---|
| `DisplayBlanking { preventBlanking: true }` | keeps the screen on | video, visible timers |
| `KeepAlive { enabled: true }` | prevents device suspend | realtime network connection while minimised; battery cost |
| `BackgroundJob { frequency: …; onTriggered: … }` | wakes the process periodically (30 s – 24 h), then you call `finished()` | periodic polling/catch-up; delayed |

- Wrap the component in a file loaded through a `Loader`, so a device without the plugin starts
  normally. The import belongs in that separate file.
- `BackgroundJob` holds suspend off between `triggered` and `finished()`; always release it, including
  on error (a watchdog `Timer` is cheap insurance).
- `KeepAlive` is a real battery trade-off. Make it an explicit setting, default off, and say so in
  the UI.
- Neither survives the user closing the app from the task switcher. True background delivery needs a
  separate daemon/service (OpenRepos territory, not a Harbour app).
- **VERIFIED 2026-11-23** for the QML types, imports and Loader pattern. Whether `KeepAlive` beats
  the platform's app suspension on a given OS release is **unverified** — test with a real message
  while on the cover.

## Layout habits

- A `Page` containing a `SilicaFlickable` with a `Column` and a `VerticalScrollDecorator` is the
  standard scrollable page.
- Offer **pull-down menus** for page-level actions (`PullDownMenu`), and respect edge swipes.
- Keep views dumb: bind to properties on a `Backend` object (`app.backend`), never call the engine
  directly from a delegate. See `05-python-pyotherside.md`.
- For "result of an action", put the feedback **directly under the control that caused it**. A single
  shared status string rendered at the bottom of the page means "yt-dlp installed" appears nowhere
  near the button — a real bug that looked like a layout preference.

## Animation

- `NumberAnimation`, `ParallelAnimation`, `FadeAnimation` (Silica) are available and used.
- Reset animated items in `onStopped` (`visible = false; opacity = 1; scale = 1`) or they stay in
  whatever state they finished in and reappear oddly.

## The definition of done

Jolla's UI bar expects: no dummy or half-finished states, recovery from errors, translation hooks,
unit tests, reasonable memory, smooth animation, and scaling with data. See
<https://docs.sailfishos.org/Develop/Apps/UI/Definition_of_Done/>.

**Be honest about translations:** wrapping strings in `qsTr()` costs nothing and is worth doing, but
shipping `.ts`/`.qm` machinery with nothing to translate buys an empty file and a build step. Kibble
kept the `qsTr()` wrappers and skipped the rest.
