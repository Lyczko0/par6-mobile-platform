#!/usr/bin/env bash
# Renders every documentation view into renders/.
#   ./render.sh
#   OPENSCAD='/c/Program Files/OpenSCAD/openscad.exe' ./render.sh
#
# --preview uses the fast OpenCSG pipeline and keeps the colours. Swap it for
# --render if you want a CGAL-accurate image (about 40x slower).
set -eu
OPENSCAD="${OPENSCAD:-openscad}"
SZ="--imgsize=1500,1500"
mkdir -p renders

ISO="0,20,430,72,0,200,2400"
ISO_X="0,20,430,72,0,200,3000"
FRONT="0,20,430,90,0,180,2300"
SIDE="0,-60,430,90,0,270,2500"

r() { # r <file> <camera> <extra -D flags...>
    out="$1"; cam="$2"; shift 2
    "$OPENSCAD" -o "renders/$out" --preview $SZ --camera="$cam" "$@" main.scad \
        2>&1 | grep -E '^(ERROR|WARNING: Ass)' || true
    echo "  renders/$out"
}

echo "rendering..."
r iso_assembled.png   "$ISO"
r front.png           "$FRONT"
r side.png            "$SIDE"
r exploded.png        "$ISO_X"  -D explode=45 -D 'view="exploded"'
r pos_low.png         "$FRONT"  -D carriage_position_mm=0
r pos_mid.png         "$FRONT"  -D carriage_position_mm=287
r pos_high.png        "$FRONT"  -D carriage_position_mm=575
r mechanism.png       "$ISO"    -D show_enclosure=false
r dual_arm.png        "$ISO"    -D show_dual_arm_mount=true -D show_enclosure=false
DIM="0,60,430,90,0,180,3400"
r dimensions.png      "$DIM"    -D show_dimensions=true -D show_enclosure=false
echo "done."
