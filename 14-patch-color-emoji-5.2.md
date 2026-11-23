# 14 — Case study: the color emoji keyboard patch on SFOS 5.2

**Read when:** you want to fix `sfos-patch-keyboard-color-stock-emojis`, or you want a concrete
walkthrough of the patch-rebase loop in `13-patchmanager-patches.md`.
**Skip when:** you only want to write a new patch — read 13.

Sister project: **Emojinal Support** consumes the same `sailor-emoji` packs and documents the
rendering side in `../harbour-emojinal-support/docs/PLATFORM.md`. It has no answer for the
patch itself; the cause is entirely in Jolla's keyboard QML.

---

## What the patch does

`sfos-patch-keyboard-color-stock-emojis` (author ichthyosaurus) replaces the stock emoji
keyboard's black-and-white text with images from the shared `sailor-emoji` packs. It also adds
skin-tone/emoji variations in the popup and a "recently used" row, and a config page. It is
shipped as a Patchmanager RPM.

Relevant pieces:

- New QML module `com.jolla.keyboard.ichthyo_color_emojis`: `EmojiConfig` (dconf-backed),
  `EmojiSearch` (singleton), `EmojiKey`/`EmojiGroupKey`/`EmojiPlaceholder`, and `emoji.js`
  (a trimmed Twemoji parser that turns an emoji into a pack file URL).
- Edits to four stock files: `HorizontalPredictionListView.qml`, `PasteInputHandler.qml`,
  `Popper.qml`, `PopperCell.qml`, plus `layouts/emojis.qml` and `layouts_emojis.conf`.

## Where it stands on 5.2.0.20

**VERIFIED 2026-10-15** on the Jolla Phone 2026, SFOS 5.2.0.20 (Finlayson), aarch64:

- installed patch is **1.5.4-1**, whose `compatible` list ends at `5.0.0.78`;
- `jolla-keyboard-0.10.4-1.18.1.jolla.aarch64`;
- the patch is **not** currently applied;
- the diff still targets `/usr/share/maliit/plugins/com/jolla/HorizontalPredictionListView.qml`.

Forum history (thread *Patches by ichthyosaurus*): koza found the whitespace/import drift on
2026-08-01 (#144), nephros found the file move on 2026-08-17 (#147), and as of 2026-08-24 no
fixed patch has been published (#148).

## Reproduce it (read-only)

Pull the stock files (or copy them off the phone) and dry-run the real patch. With GNU patch
2.8 locally against the 5.2 originals, the output is:

```
checking file usr/lib64/qt5/qml/com/jolla/keyboard/HorizontalPredictionListView.qml
Hunk #3 succeeded at 35 with fuzz 2.
Hunk #4 succeeded at 46 (offset -1 lines).
Hunk #5 succeeded at 68 (offset 1 line).
checking file usr/share/maliit/plugins/com/jolla/PasteInputHandler.qml
Hunk #1 FAILED at 4.
...
checking file usr/share/maliit/plugins/com/jolla/Popper.qml
Hunk #2 succeeded at 51 (offset 1 line).
Hunk #3 FAILED at 80.
...
checking file usr/share/maliit/plugins/com/jolla/PopperCell.qml
Hunk #2 succeeded at 12 with fuzz 2 (offset -3 lines).
...
1 out of 3 hunks FAILED      (PasteInputHandler)
1 out of 10 hunks FAILED     (Popper)
```

(the numbers match the forum report from koza). Note `HorizontalPredictionListView.qml` is
reported under `lib64` only because we patched the path by hand to test; the shipped patch
says `share/…` and stops at "can't find file to patch".

---

## Root causes (all confirmed against the 5.2 stock files)

### 1. `HorizontalPredictionListView.qml` moved out of `share/`

```
old: /usr/share/maliit/plugins/com/jolla/HorizontalPredictionListView.qml
new: /usr/lib64/qt5/qml/com/jolla/keyboard/HorizontalPredictionListView.qml
```

The patch writes to the old path. This is not one of the three paths Patchmanager auto-mangles,
so the path in the diff must change by hand. **VERIFIED** (both files on device).

### 2. Even with the path fixed, its `import "ichthyo_color_emojis"` points at the wrong place

`HorizontalPredictionListView.qml` gets `EmojiSearch` from the module
`com.jolla.keyboard.ichthyo_color_emojis` (installed under `lib64/qt5/qml/com/jolla/keyboard/
ichthyo_color_emojis/`, which only declares the `EmojiSearch` singleton), and it gets
`EmojiConfig` from the **directory import** `import "ichthyo_color_emojis"`.

A quoted QML import is resolved **relative to the file it appears in**. It used to be in
`/usr/share/maliit/plugins/com/jolla/`, next to the full `ichthyo_color_emojis/` directory, so
`EmojiConfig` resolved. Now it is in `…/lib64/qt5/qml/com/jolla/keyboard/`, next to the
*module* directory, which has only `EmojiSearch`. So a naïve path fix applies but the component
is missing `EmojiConfig` at runtime. This is why nephros' path replacement "does make it fail
in other places". **VERIFIED by file layout; QML relative-import semantics are standard.**

Two ways out (pick one in the rebase):

- minimal: change the directory import to
  `import "../../../../../../share/maliit/plugins/com/jolla/ichthyo_color_emojis"`; or
- cleaner: move the whole `ichthyo_color_emojis` module (all QML + `emoji.js`) into
  `lib64/qt5/qml/com/jolla/keyboard/ichthyo_color_emojis/`, declare every type in its
  `qmldir`, and have all consumers import the module instead of a relative directory.

### 3. `PasteInputHandler.qml` — Jolla added an import

Patch context (base):
```qml
import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as SilicaPrivate
+import com.jolla.keyboard.ichthyo_color_emojis 1.0
+import "ichthyo_color_emojis"

InputHandler {
```
5.2 stock:
```qml
import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as SilicaPrivate
import com.jolla.keyboard 1.0          // ← added by Jolla; hunk #1 has no line for it

InputHandler {
```
The extra line shifts the context, so hunk #1 fails. Fix: add
` import com.jolla.keyboard 1.0` to the hunk and bump its counts. **VERIFIED.**

### 4. `Popper.qml` — Jolla added a blank line after `id: contentRow`

Patch context (base):
```qml
    Row {
        id: contentRow
        height: parent.height
```
5.2 stock:
```qml
    Row {
        id: contentRow

        height: parent.height
```
The new blank line is why hunk #3 fails. The patch's change itself (turn the `Row` into a
multi-row `Grid`, add `property int itemIndex`/`isEmoji`) is still wanted; only the context is
stale. Fix the hunk so it removes `height: parent.height` and keeps the blank line. **VERIFIED.**

### 5. Cosmetic drift (fuzz, not failure)

Two stock files gained blank lines that GNU patch absorbed with `fuzz 2`:

- `PopperCell.qml`: blank line below `id: popperCell` (the patch's own comment already warns
  about this one).
- `HorizontalPredictionListView.qml`: blank line between `height: view.height` and
  `clip: marginAnimation.running`.

They apply today, but they are exactly the kind of drift that becomes a `FAILED` next release.
Fix them while rebasing. **VERIFIED.**

### Not a cause: the `/usr/lib/qt5/qml/…/EmojiSearch.qml` new files

The patch installs the `EmojiSearch` singleton module under `/usr/lib/qt5/qml/…`. On aarch64
that directory does not exist, but Patchmanager's lib→lib64 mangling rewrites it at apply time
(`Converting library path reference /usr/lib/qt5/qml 2 times OK`), so it lands in `lib64`.
This bit people in 2024/#114 before the mangling fix; on 5.2 it is fine. Leave it as `/usr/lib`
in the source patch and let Patchmanager convert it. **VERIFIED** (PNP: patch file says
`/usr/lib`, device hasn't applied it; mangling quoted from Patchmanager log).

---

### Runtime gotcha (not a rebase cause): the `?` placeholder

Once the patch applies, each emoji image is looked up by `emoji.js`, which has a **hard-coded list of
known pack versions** per style. If the installed pack directory name is not in that list,
`getStylePath()` finds nothing, `getUrl()` returns `''`, and `EmojiPlaceholder.qml` shows a `?` for
every emoji (an actual bad URL shows `!` instead).

**VERIFIED 2026-10-15** on this device: the sister app (Emojinal Support) installs
`~/.local/share/sailor-emoji/openmoji/17.0.0/` and `.../twemoji/17.0.3/`, but the patch only knows
twemoji `['15.1.0','14.0.2','13.0.1']` and openmoji `['15.0.0','14.0.0','13.1.0','13.0.0']`. Hence `?`
everywhere. The base path is correct (`StandardPaths.genericData + /sailor-emoji`, same as the app).

Fix for a user, either:

- prepend the installed version to `versions:` in `emoji.js` for the active style, or
- install the pack version the patch expects (e.g. twemoji `15.1.0`).

For the contribution, adding the current pack versions is a reasonable 1.5.5 line item, but keep it
separate from the 5.2 rebase.

---

## Outcome — tested working (2026-10-15)

**VERIFIED:** on the Jolla Phone 2026 / SFOS 5.2.0.20, the rebased patch
(`HorizontalPredictionListView` retargeted to lib64, the three context/hunk fixes, and the
six-`..` import) applied with zero `FAILED` and zero `fuzz`, and the emoji keyboard then rendered
colour emojis after the installed pack versions (`twemoji 17.0.3`, `openmoji 17.0.0`) were added to
`emoji.js`.

So the 5.2 rebase is done; the remaining work is packaging/publishing it, plus deciding whether the
pack-version bump belongs in the same release. The manual test is **not** a Patchmanager install:
Patchmanager still has the old 1.5.4 patch unapplied, and a `jolla-keyboard` package update would
overwrite the hand-patched files. For day-to-day use, build the rebased `unified_diff.patch` into a
patch and apply it through Patchmanager (or keep the manual files knowing they are unmanaged).

---

## Plan to make it work on 5.2 (and keep it maintainable)

### Phase 0 — decide and de-risk (no device changes)
- Confirm the stock files we based the 5.2 context on (already read: `Popper.qml`,
  `PopperCell.qml`, `PasteInputHandler.qml`, `HorizontalPredictionListView.qml`,
  `layouts/emojis.qml`, `layouts_emojis.conf`).
- Decide cause #2: minimal relative path vs. full module move. **Recommend the module move** —
  it is the layout Qt expects on 64-bit and removes the fragile 6×`..` import.
- Decide whether to keep pre-5.2 compatibility. The import in cause #3 exists only on 5.2+;
  a single `unified_diff.patch` can't have both contexts, so either target 5.2 only or accept
  a second hunk/patch for older OSes. **Recommend: target 5.2+**, bump `compatible`.

### Phase 1 — rebase the patch (mechanical, local, no phone)
1. Copy the 1.5.4 `unified_diff.patch` as the base.
2. `HorizontalPredictionListView.qml`: retarget to
   `/usr/lib64/qt5/qml/com/jolla/keyboard/HorizontalPredictionListView.qml`; resolve cause #2.
3. `PasteInputHandler.qml`: add ` import com.jolla.keyboard 1.0` to hunk #1.
4. `Popper.qml`: fix hunk #3 for the blank line (and drop `height: parent.height`).
5. `PopperCell.qml` + `HorizontalPredictionListView.qml`: fold the fuzz fixes into context.
6. Re-run `patch -p1 --dry-run -d / < new.patch` against a pristine 5.2 `orig/` tree until
   **zero** `FAILED` and **zero** `fuzz`.
7. Update `patch.json` (`version`, `compatible` += `5.2.0.20`) and the config page's version
   string if it is bumped.

Deliverable: a new `unified_diff.patch` (and a small README of what changed).

### Phase 2 — verify on the phone (needs your go-ahead before touching the device)
- Backup the four stock files.
- Dry-run, then apply via `patch -p1 -d /`.
- `systemctl --user restart maliit-server`.
- Check: color emojis render; skin-tone popup has multiple rows; recents appear; changing the
  style / key width in the config page works; **every other keyboard still works** (the
  `Popper.qml` change is shared with all keyboards — this is the risky one).
- Unapply and confirm originals restored.

### Phase 3 — publish
- Package/Patchmanager Web Catalog, or upstream PR to
  `codeberg.org/ichthyosaurus/sailfish-public-patch-sources` with the rebased diff and an
  updated `CONFIG` (`CompatibleVersions`, changelog entry `1.5.5`).
- The repo has a no-AI-training license; send the diff and let the author own the commit.

## Open questions / risks

- The `Popper.qml` multi-row `Grid` change affects **all** keyboards with many popup options,
  not just emoji. Any regression here is high-visibility.
- Emoji `emoji_data*.js` in 1.5.4 is newer than the repo's 1.5.2; don't lose it when rebasing.
  Diff the device patch against the repo patch first.
- We have not run the patched keyboard yet — everything above is static analysis plus a
  dry-run. The rebase must be tested on the device before it can be called fixed.
- `sailor-emoji` packs must already be installed (`/usr/local/share/sailor-emoji` or
  `~/.local/share/sailor-emoji`) for the images to resolve; that is the Emojinal Support side.

## Sources

- Device reads, SFOS 5.2.0.20 / jolla-keyboard 0.10.4, 2026-10-15 (VERIFIED markers).
- Forum thread *Patches by ichthyosaurus*, posts #114, #143, #144, #147, #148
  (<https://forum.sailfishos.org/t/patches-by-ichthyosaurus/15387>).
- `codeberg.org/ichthyosaurus/sailfish-public-patch-sources`, patch dir
  `sfos-patch-keyboard-color-stock-emojis`.
- `../harbour-emojinal-support/docs/PLATFORM.md` (sailor-emoji packs, rendering).

---

## Appendix — the hand rebase (what you change yourself)

Everything below is done in the patch's source directory from the Codeberg repo. You do **not**
need to touch the phone for this part.

Three logical changes fix it. Do them in the source files, then let `sailfish-patch` regenerate the
diff — that avoids hand-counting hunk lines.

### Route A — with `sailfish-patch` (recommended)

1. Run `sailfish-patch -u` in the patch directory with the 5.2 phone reachable by SSH. It fills
   `original/` and copies to `patched/`. The old diff will not apply cleanly; that is fine, you
   are about to fix `patched/` by hand.
2. In `patched/`, make these edits:
   - **`usr/lib64/qt5/qml/com/jolla/keyboard/HorizontalPredictionListView.qml`** — the file moved;
     change its import from `import "ichthyo_color_emojis"` to

     ```qml
     import "../../../../../../share/maliit/plugins/com/jolla/ichthyo_color_emojis"
     ```

     (six `..`: from `lib64/qt5/qml/com/jolla/keyboard/` up to `/usr`, then into `share/maliit/…`).
   - **`usr/share/maliit/plugins/com/jolla/PasteInputHandler.qml`** — Jolla added
     `import com.jolla.keyboard 1.0`; keep it and add the two emoji imports after it.
   - **`usr/share/maliit/plugins/com/jolla/Popper.qml`** — in the `contentRow` block make sure the
     blank line after `id: contentRow` is kept and `height: parent.height` is removed (the diff's
     intended `Grid` with `width`/`columns`/`rowSpacing` stays).
   - `PopperCell.qml` and the rest of `HorizontalPredictionListView.qml` need **no logical change**;
     regenerating the diff absorbs the blank-line drift automatically.
3. Run `sailfish-patch -b`. That rewrites `unified_diff.patch` with exact context (no fuzz).
4. Update `CONFIG`: `Version: 1.5.5`, a changelog line for 5.2, and add `5.2.0.20` to
   `CompatibleVersions`. Bump the patchVersion string in
   `patched/maliit/plugins/com/jolla/ichthyo_color_emojis/EmojiConfigOverlay.qml` if the project
   wants them in sync.
5. Verify: build the diff, then dry-run it against the stock tree (`patch -p1 --dry-run -d / <
   unified_diff.patch`) on the device, or use `sailfish-patch -p`.

### Route B — edit `unified_diff.patch` directly

Only if you cannot use `sailfish-patch`. Four edits:

**1. Move the one file** (3 lines at the top of that file's section):

```diff
-diff --git a/usr/share/maliit/plugins/com/jolla/HorizontalPredictionListView.qml b/usr/share/maliit/plugins/com/jolla/HorizontalPredictionListView.qml
+diff --git a/usr/lib64/qt5/qml/com/jolla/keyboard/HorizontalPredictionListView.qml b/usr/lib64/qt5/qml/com/jolla/keyboard/HorizontalPredictionListView.qml
---- a/usr/share/maliit/plugins/com/jolla/HorizontalPredictionListView.qml
-+++ b/usr/share/maliit/plugins/com/jolla/HorizontalPredictionListView.qml
+--- a/usr/lib64/qt5/qml/com/jolla/keyboard/HorizontalPredictionListView.qml
++++ b/usr/lib64/qt5/qml/com/jolla/keyboard/HorizontalPredictionListView.qml
```

**2. Fix its directory import** (first hunk, the second added line; counts do not change):

```diff
 import QtQuick 2.6
 import Sailfish.Silica 1.0
+import com.jolla.keyboard.ichthyo_color_emojis 1.0
+import "../../../../../../share/maliit/plugins/com/jolla/ichthyo_color_emojis"
```

**3. `PasteInputHandler.qml`** — add the missing context line and bump the counts `6→7` / `8→9`:

```diff
@@ -4,7 +4,9 @@
 import QtQuick 2.0
 import Sailfish.Silica 1.0
 import Sailfish.Silica.private 1.0 as SilicaPrivate
 import com.jolla.keyboard 1.0
+import com.jolla.keyboard.ichthyo_color_emojis 1.0
+import "ichthyo_color_emojis"
 
 InputHandler {
     id: pasteHandler
```

**4. `Popper.qml`** — add the blank context line after `id: contentRow` and bump the counts `13→14` /
`23→24`:

```diff
@@ -66,14 +80,24 @@ Rectangle {
         id: accents
     }
 
-    Row {
+    Grid {
         id: contentRow
 
-        height: parent.height
+        width: Math.min(itemsCount, cellsPerRow) * geometry.accentPopperCellWidth + 2 * geometry.accentPopperMargin
+        columns: Math.min(itemsCount, cellsPerRow)
+        rowSpacing: -2 * Math.abs(geometry.accentPopperMargin)
 
         Repeater {
             model: accents
+
             PopperCell {
+                property int itemIndex: index
+
+                // isEmoji: (typeof KeyboardSupport.isEmoji === 'undefined') ?
+                //              _emojiLookupSFOS34.hasOwnProperty(labelText) :
+                //              KeyboardSupport.isEmoji(labelText)
+                // --> KeyboardSupport.isEmoji appears to be unable to recognize skin tone variations
+                isEmoji: _emojiLookupSFOS34.hasOwnProperty(labelText)
                 character: labelText
                 active: index === popper.activeCell
                 textVisible: popper.expanded || index === popper.activeCell
```

Everything else in the diff stays. The `EmojiSearch.qml`/`qmldir` paths stay as `/usr/lib/qt5/qml/…`
**on purpose**: Patchmanager's `manglelist.conf` converts `/usr/lib/qt5/qml` ↔ `/usr/lib64/qt5/qml`
both ways, so a patch that says `/usr/lib64/…` for the moved keyboard file works on 32-bit too.

**Imports do not get mangled.** That is the whole reason edit 2 exists: the file moved, so its
relative `import` must be repointed by hand.

### Sanity check

After either route:

```sh
patch -p1 --dry-run -d / < unified_diff.patch
```

Wanted: every file reports `checking file …`, no `FAILED`, and ideally no `fuzz`. Then restart the
keyboard (`systemctl --user restart maliit-server`) and try the keyboard; unapply must restore the
stock files.
