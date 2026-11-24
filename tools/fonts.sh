#!/usr/bin/env bash
# Regenerate the bitmap fonts for both screen sizes from the OFL sources in fonts-src/.
set -euo pipefail
cd "$(dirname "$0")/.."
BOLD=fonts-src/SairaSemiCondensed-SemiBold.ttf
gen() { # dir clock val lab
  local d="resources-round-$1/fonts"; rm -rf "$d"; mkdir -p "$d"
  python3 tools/mkfont.py $BOLD "$2" "0123456789" "$d/clock"
  python3 tools/mkfont.py fonts-src/Saira.ttf "$2" "0123456789" "$d/thin" --axes 300,88
  python3 tools/mkfont.py $BOLD "$3" "0123456789-%K,.°" "$d/val"
  python3 tools/mkfont.py $BOLD "$4" "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -+%°:/" "$d/lab"
  cat > "$d/fonts.xml" <<XML
<fonts>
    <font id="Clock" filename="clock.fnt" antialias="true"/>
    <font id="Thin" filename="thin.fnt" antialias="true"/>
    <font id="Val" filename="val.fnt" antialias="true"/>
    <font id="Lab" filename="lab.fnt" antialias="true"/>
</fonts>
XML
}
gen 454x454 172 44 30
gen 390x390 148 38 26
