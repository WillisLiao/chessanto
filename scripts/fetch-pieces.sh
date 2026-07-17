#!/bin/sh
# Fetches the lichess-org/lila cburnett piece SVGs (Colin M.L. Burnett,
# GPLv2+, compatible with Chessanto's GPLv3 license) and writes them into
# App/Resources/Pieces.xcassets as 12 image sets, named cburnett-<color><kind>
# (e.g. cburnett-wK, cburnett-bP).
#
# The committed asset catalog is network-free at build time; this script
# exists only for regenerating it (e.g. if the upstream artwork changes).
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
catalog="$root/App/Resources/Pieces.xcassets"

cat > "$catalog.tmp.Contents.json" <<'JSON'
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
JSON
mkdir -p "$catalog"
mv "$catalog.tmp.Contents.json" "$catalog/Contents.json"

pieces="K Q R B N P"
colors="w b"

for color in $colors; do
    for piece in $pieces; do
        name="cburnett-${color}${piece}"
        imageset="$catalog/$name.imageset"
        mkdir -p "$imageset"
        echo "fetching ${color}${piece}.svg ..."
        curl -sSfL -o "$imageset/${color}${piece}.svg" \
            "https://raw.githubusercontent.com/lichess-org/lila/master/public/piece/cburnett/${color}${piece}.svg"

        cat > "$imageset/Contents.json" <<JSON
{
  "images": [
    {
      "filename": "${color}${piece}.svg",
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "original"
  }
}
JSON
    done
done

echo "wrote 12 piece image sets to $catalog"
