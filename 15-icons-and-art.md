# 15 — Icons and art

**Read when:** the app needs an icon, the launcher thumbnail looks wrong, or you are about to
generate placeholder art.
**Skip when:** you are styling the UI itself — that is `04-qml-and-silica.md` (§ Theming, § Icons and
spinners are tintable).

**VERIFIED 2026-11-21**, from two primary sources rather than from memory:

- Jolla's own `Sailfish-Apps-icon-template.zip` / `-library.zip` (<https://sailfishos.org/design/icons/>,
  CC BY 3.0) — opened, measured, rendered.
- `sailfish-sdk/sdk-harbour-rpmvalidator`: `rpmvalidation.conf` (`ICON_SIZES`, `ICON_NAMES_REGEX`)
  and `validateicon()` — i.e. what Harbour actually checks.
- The render pipeline below was run on the host: ImageMagick 7 + librsvg 2.63, PNG32, alpha kept.

---

## 1. Setup: four PNGs, exact sizes, exact paths

The launcher picks a density from the hicolor theme, so ship all four. Both the path and the pixel
size are checked.

| Path | Pixels |
|---|---|
| `/usr/share/icons/hicolor/86x86/apps/<name>.png` | 86x86 |
| `/usr/share/icons/hicolor/108x108/apps/<name>.png` | 108x108 |
| `/usr/share/icons/hicolor/128x128/apps/<name>.png` | 128x128 |
| `/usr/share/icons/hicolor/172x172/apps/<name>.png` | 172x172 |

`<name>` is the package/binary name (`harbour-myapp`), the same string as `Icon=` in the `.desktop`
and `TARGET` in the `.pro`.

**`.pro`** — libsailfishapp installs them, if you list the sizes and keep the files where it looks:

```qmake
SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172
# files must be at icons/<W>x<H>/$$TARGET.png in the source tree
```

`SAILFISHAPP_ICONS` is the documented route (`docs.sailfishos.org/Develop/Apps/Packaging`).
Hand-rolled `.pro` files without it need four `INSTALLS` stanzas instead — see `06-cpp-and-pro.md`.
Either way libsailfishapp *also* expects a plain `$$TARGET.png` (86x86) in the project root, which is
why `make-icons.sh` writes that copy too. Do not delete it.

**`.spec`** — `%files` must list what actually got installed:

```spec
%{_datadir}/icons/hicolor/86x86/apps/%{name}.png
# … 108x108, 128x128, 172x172
```

### What Harbour rejects

Straight from `validateicon()` / `check_for_icons()`:

- a PNG whose **pixels are not exactly** 86/108/128/172 → **error** `Wrong size, must be 86x86`.
  A beautiful 1024px master named `86x86.png` fails the build of your release.
- anything that is not a PNG (an `.svg` in the hicolor dir, a JPEG) → **error**.
- **some** sizes missing → **warning** `Not all icons found!`.
- **all** missing → **error** `No icons found!`.
- `Icon=` in the `.desktop` not equal to the package name → **error**. It does not need to be a
  path, and it must not be one.

So "I ship 86x86 only" is not a pass, it is a warning you ship and a blurry icon on high-DPI
devices. Render all four from one vector and the question disappears.

---

## 2. What a Sailfish icon is supposed to look like

Jolla's system is **one shape family, many glyphs**. The design story: a square and a circle merged,
rotated and mixed, gives 16 base shapes, so icons look related without every app being forced into
the same rounded rectangle.

Measured from the template file (86 canvas, so these are the numbers you use):

- **Art boundary 85.4 × 85.4**, inset **0.3** on every side. That gap is deliberate: it keeps the
  antialiased outline clean and stops clipping. Draw the base shape to those bounds, not to 0…86.
- **Corners are rounded by half the side (42.7)** where they are rounded at all — the leaf shape has
  two of them at opposite corners, the other two nearly square (r≈1.4).
- **One base colour, at most one lighter tone on top of it, then the glyph.** Flat fills.
- **Glyph occupies roughly the middle 45–65%** of the width, optically centred (a triangle or a
  play mark sits visually low — nudge it up about 1 unit at 86).

Base colours measured out of the official library (they are mid-tone and slightly muted, not neon):

| Use | Base | Second tone | Glyph |
|---|---|---|---|
| green / messaging, mail | `#0D955E` | `#35B68E` | `#F7F6E7` |
| teal / notes, tools | `#05B6A6` | `#0FC7B4` | `#E7D9A8` |
| amber / settings, utilities | `#DDA015` | `#F2BE69` | `#F1E9B2` |
| red-orange / media, alerts | `#FF6352` | `#E37C6D` | `#EEEDDB` |
| blue / web, weather | `#10AAFE` | `#48C7FB` | `#F7F9F3` |
| purple / audio | `#B93B9F` | `#C393C3` | `#FEA5A3` |

Rules that matter more than the palette:

- **No text.** Not even one letter. A letterform does not survive 86px, and every launcher icon with
  a letter in it looks like an afterthought.
- **No thin strokes.** Nothing under ~2 units at 86 (≈4 at 172). Hairlines vanish into the
  background of a wallpaper.
- **No shadows, gloss, bevels, glow, drop-shadows on the glyph.** The launcher already sits the icon
  on the wallpaper; a fake 3D edge reads as a 2013 Android icon.
- **No gradients except a two-tone fill of the same hue** — the official set does exactly one thing
  like this and never a rainbow.
- **No photos or multi-hue glyphs.** Two hues, one idea.
- **It must read at 40px.** That is roughly launcher-grid size. Look at it, do not assume.
- **The empty corners show the wallpaper**, because the launcher does not paint a plate behind the
  icon (unverified on 5.x — check on the phone). That is why the official light-on-midtone
  combination is safe and a black glyph on a transparent base is not.

The community does notice. The 2026 forum reminder on icon shapes exists because publishers (and
their LLMs) keep shipping off-style icons; the official shapes are CC BY 3.0 and explicitly meant to
be edited, so use them instead of inventing a new silhouette.

---

## 3. Generating a decent icon (placeholder now, replaced later)

Treat the icon like the app's other assets: **one vector master in the repo**, rendered to the four
sizes by a script, committed next to the PNGs. That way packaging never changes, and the day you
draw the real icon you replace one file and re-run one command.

Copy `templates/icon-master.svg` and `templates/make-icons.sh` into the project:

```sh
scripts/make-icons.sh harbour-myapp
→ icons/{86x86,108x108,128x128,172x172}/harbour-myapp.png   # what ships
→ harbour-myapp.png                                        # the 86x86 root copy
→ icons/preview.png     # 172 / 86 / 40 px on grey — open it and look
```

The script needs ImageMagick only (`magick`, or `convert`+`montage` on IM6); on the host it renders
through librsvg, keeps alpha (`PNG32`), asserts the output dimensions, and fails loudly if the SVG
renders at the wrong size. No Inkscape, no `rsvg-convert`, no SDK, no container.

**Why an 86×86 `viewBox` and not a big canvas:** the sizes then differ only by scale, the 0.3 gap
stays a vector property, and a `-resize` from 86 to 172 is a clean 2× — no resampling surprises.
Render from the SVG every time; never upscale a PNG.

### Writing the master

Three things get swapped, everything else stays:

1. **Base shape** — pick one and delete the others:

```svg
<!-- leaf: two opposite corners rounded to half the side (Jolla template default) -->
<path fill="#0D955E" d="M84.277.3H43C19.417.3.3 19.418.3 43v41.277c0 .786.637 1.423 1.423 1.423H43c23.583 0 42.7-19.118 42.7-42.7V1.723C85.7.937 85.063.3 84.277.3z"/>
<!-- circle -->
<circle cx="43" cy="43" r="42.7" fill="#0D955E"/>
<!-- soft square (radius ~14) -->
<rect x=".3" y=".3" width="85.4" height="85.4" rx="14" fill="#0D955E"/>
```

2. **Base fill** — one row from the palette table.
3. **Glyph** — 2–6 primitives in the light tone, centred in the middle ~50 units, no strokes thinner
   than 2.

Glyph recipes that actually read at 40px, all buildable from a `<circle>`, `<rect rx>` and one
`<path>`:

| App kind | Glyph |
|---|---|
| media / player | solid play triangle (rounded corners help) |
| downloader | arrow down into an open tray (three rects + path) |
| reference / library | 3 stacked rounded bars, last one shorter |
| notes / docs | page rect with a folded corner + 2 bars |
| chat / social | rounded speech bubble + one bar |
| search / discovery | ring (stroke 5) + 45° bar |
| map / location | pin = circle + downward triangle |
| music | note = circle + stem + small flag |
| settings / utility | dot grid 3×3, or a single bold gear silhouette — *not* an 8-tooth outline |

Keep the master's `id`/comment structure so the next editor (or agent) sees which layer is the base
and which is the glyph. Name it `icons/icon-master.svg`, never `86x86.svg`.

### Check before committing

- [ ] `magick identify icons/*/harbour-<name>.png` → `86x86`, `108x108`, `128x128`, `172x172`, PNG,
      alpha channel present
- [ ] `icons/preview.png` opened: shape still obvious at 40px, glyph not touching the edge, nothing
      thinner than a hairline
- [ ] installed on the phone and seen on the **homescreen / launcher grid**, not just opened as a file
- [ ] `rpm -qlp RPMS/*.rpm | grep icons/hicolor` lists all four
- [ ] the SVG master is committed next to the PNGs

---

## 4. In-app icons are a separate problem

Your app icon is a picture; icons *inside* the UI are Silica theme icons and behave differently:
monochrome, tintable with `Icon.color`, chosen by `image://theme/icon-m-…` name, and forced into a
white-on-translucent-disc treatment when they float over video. All of that, including the names that
exist and the ones that do not, is in `04-qml-and-silica.md`. `CoverAction` takes `iconSource` only —
a theme icon, not your app icon.

A custom monochrome glyph can be shipped as `images/<name>.svg` and used through `Icon { source: … }`
(**unverified**: check it tints and scales on the device before relying on it; SVG must survive
`Icon.color`).

---

## Where the material is

- Icon guidelines, story PDF, template + library zip: <https://sailfishos.org/design/icons/>
  (CC BY 3.0, no attribution required, editing encouraged)
- Icon sizes FAQ: <https://harbour.jolla.com/faq#Icons>
- The validator that enforces them: <https://github.com/sailfishos/sdk-harbour-rpmvalidator>
- In-app theme icons: `04-qml-and-silica.md`; store listing icon + screenshots: `10-publishing.md`
