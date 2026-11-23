#!/bin/sh
# Render the icon master SVG into the four launcher sizes, the 86x86 root copy
# that libsailfishapp expects, and a preview sheet to eyeball.  See 15-icons-and-art.md.
#
#   scripts/make-icons.sh harbour-myapp [icons/icon-master.svg]
#
# Needs ImageMagick only.  Master must have viewBox="0 0 86 86".
set -eu

NAME=${1:?usage: make-icons.sh <app-name> [master.svg]}
SRC=${2:-icons/icon-master.svg}

[ -f "$SRC" ] || { echo "make-icons: missing master SVG: $SRC" >&2; exit 1; }

# ImageMagick 7 renamed convert/montage under `magick`
if command -v magick >/dev/null 2>&1; then IM=magick; MONTAGE="magick montage"
else IM=convert; MONTAGE=montage; fi

for s in 86 108 128 172; do
    out="icons/${s}x${s}/${NAME}.png"
    mkdir -p "icons/${s}x${s}"
    $IM -background none "$SRC" -resize "${s}x${s}" "PNG32:$out"
    got=$($IM identify -format '%wx%h' "$out")
    [ "$got" = "${s}x${s}" ] || { echo "make-icons: $out is $got, expected ${s}x${s}" >&2; exit 1; }
done

# libsailfishapp installs this one from the project root
cp "icons/86x86/${NAME}.png" "./${NAME}.png"

# legibility check: launcher-grid size next to the shipped sizes
tmp=$(mktemp -d)
$IM -background none "$SRC" -resize 40x40 "PNG32:$tmp/40.png"
$MONTAGE "icons/172x172/${NAME}.png" "icons/86x86/${NAME}.png" "$tmp/40.png" \
    -tile 3x1 -geometry +12+12 -background '#3a3a3a' "icons/preview.png"
rm -rf "$tmp"

echo "make-icons: icons/{86,108,128,172}/${NAME}.png + ./${NAME}.png + icons/preview.png"
echo "make-icons: now open icons/preview.png — the 40px one has to be recognisable"
