#!/usr/bin/env bash
# Renderuje komplet widokow dla wszystkich trzech wariantow podparcia.
#   OPENSCAD='/c/Program Files/OpenSCAD/openscad.exe' ./render_base.sh
set -eu
OPENSCAD="${OPENSCAD:-openscad}"
SZ="--imgsize=1500,1200"
mkdir -p renders

ISO="0,0,160,62,0,205,1900"
TOP="0,0,120,0,0,0,1500"
BOT="0,0,120,180,0,0,1500"
SIDE="0,0,160,90,0,270,1700"
FRONT="0,0,160,90,0,180,1700"
STAB="0,0,60,32,0,205,1750"

r() { out="$1"; cam="$2"; shift 2
    "$OPENSCAD" -o "renders/$out" --preview $SZ --camera="$cam" "$@" main_base.scad \
        2>&1 | grep -E '^ERROR|WARNING: Assert' || true
    echo "  renders/$out"; }

for V in A B C; do
    r "var${V}_iso.png"    "$ISO"   -D "variant=\"$V\""
    r "var${V}_top.png"    "$TOP"   -D "variant=\"$V\"" -D show_skirts=false
    r "var${V}_bottom.png" "$BOT"   -D "variant=\"$V\"" -D show_battery=false -D show_electronics=false
    r "var${V}_side.png"   "$SIDE"  -D "variant=\"$V\""
    r "var${V}_stab.png"   "$STAB"  -D "variant=\"$V\"" -D show_stability=true \
        -D show_frame=false -D show_cnc=false -D show_battery=false -D show_electronics=false -D show_column=false
done
r "recommended_iso.png"  "$ISO"  -D 'variant="A"' -D show_skirts=true
r "dimensions.png"       "$FRONT" -D 'variant="A"' -D show_dimensions=true
echo done
