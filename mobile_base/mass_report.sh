#!/usr/bin/env bash
# ############################################################################
#  mass_report.sh  -  mass budget + centre of mass + stability verdict
#
#  One command, whole answer. Prints the itemised budget, the CoM interval and
#  the stability margin at three arm poses.
#
#    bash mobile_base/mass_report.sh              # variant A, carriage LOW
#    bash mobile_base/mass_report.sh C 961        # variant C, carriage HIGH
#
#  Windows: OPENSCAD='/c/Program Files/OpenSCAD/openscad.com' bash mass_report.sh
#
#  Exit 1 with "Current top level object is empty" is EXPECTED - this script
#  renders no geometry, only echoes. Do not treat that as failure; the pass
#  condition is the absence of ERROR/assert lines, checked below.
# ############################################################################
set -u
cd "$(dirname "$0")"

OPENSCAD="${OPENSCAD:-openscad}"
command -v "$OPENSCAD" >/dev/null 2>&1 || OPENSCAD='/c/Program Files/OpenSCAD/openscad.com'

VARIANT="${1:-A}"
CARRIAGE="${2:-}"

# The generated file must sit next to the .scad sources: OpenSCAD resolves
# include paths relative to the TOP-LEVEL file, and the Windows build does not
# accept Git-Bash /c/... paths.
GEN=_mass_report_gen.scad
LOG=_mass_report_gen.log
trap 'rm -f "$GEN" "$LOG" _mass_report_gen.stl' EXIT

cat > "$GEN" <<EOF
include <base_stability.scad>
mass_report();
zlift_echo();
stability_report("$VARIANT");
EOF

ARGS=()
[ -n "$CARRIAGE" ] && ARGS+=(-D "carriage_z=$CARRIAGE")

"$OPENSCAD" -o _mass_report_gen.stl --export-format=asciistl     "${ARGS[@]}" "$GEN" > "$LOG" 2>&1

if grep -qE '^(ERROR|.*Assertion)' "$LOG"; then
    echo "FAIL - model zglosil blad:"
    grep -E '^(ERROR|WARNING|.*Assertion)' "$LOG"
    exit 1
fi

sed -n 's/^ECHO: "\(.*\)"$/\1/p' "$LOG"

WARN=$(grep -c '^WARNING' "$LOG" || true)
[ "$WARN" -gt 0 ] && { echo; echo "$WARN ostrzezen:"; grep '^WARNING' "$LOG"; }
exit 0
