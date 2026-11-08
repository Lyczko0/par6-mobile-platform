#!/usr/bin/env bash
# Runs every interference test in check_collisions.scad.
#
#   pass       - the two sub-assemblies share no volume
#   touching   - they share a zero-thickness face (a bolted joint, or a hard
#                stop contact face). Not a collision.
#   CLASH      - they share real volume; the bounding box is printed
#   ERROR      - OpenSCAD failed, or the test name does not exist
#
# WHY THE PASS DETECTION LOOKS FUSSY
#   OpenSCAD writes NO output file and exits 1 with "Current top level object
#   is empty." when an intersection is empty - which is exactly what a PASS
#   looks like. So neither "no file" nor "exit 1" can mean failure on its own,
#   and a typo'd test name produces the same silent nothing. A pass therefore
#   has to be positively identified: the test name must exist in the .scad,
#   the log must carry the empty-object message, and it must be free of
#   ERROR/assert lines, AND free of "Ignoring unknown variable". Without all
#   four, a broken test reads as a pass. The fourth condition was added after
#   seven tests silently passed on a variable deleted in a refactor.
#
#   ./check_collisions.sh
#   OPENSCAD='/c/Program Files/OpenSCAD/openscad.exe' ./check_collisions.sh

set -u
cd "$(dirname "$0")"
OPENSCAD="${OPENSCAD:-openscad}"
command -v "$OPENSCAD" >/dev/null 2>&1 || OPENSCAD='/c/Program Files/OpenSCAD/openscad.com'
OUT=".chk"
SCAD="check_collisions.scad"
rm -rf "$OUT"; mkdir -p "$OUT"

TESTS="
carriage_vs_bearings carriage_vs_frame carriage_vs_screw carriage_vs_rails
carriage_vs_blocks carriage_vs_stops_lo carriage_vs_stops_mid carriage_vs_stops_hi
blocks_vs_frame
tie_vs_profiles
baseplate_vs_profiles
enclosure_vs_profiles enclosure_vs_frame_extras
chain_end_vs_enclosure chain_end_vs_moving chain_end_vs_profiles
rotating_vs_pads screw_vs_bearings pads_vs_motor_bolts bf12_pad_vs_tie
chain_vs_screw chain_vs_rails chain_vs_blocks chain_vs_risers
chain_vs_enclosure chain_vs_stops chain_vs_bearings
enclosure_vs_moving enclosure_vs_blocks enclosure_vs_bearings enclosure_vs_screw
switches_vs_moving switches_vs_blocks stops_vs_rails
motorbay_vs_battery motorbay_vs_structure motor_bare_vs_battery
"
DUAL_TESTS="dualarm_vs_rails dualarm_vs_enclosure"
INFO_TESTS="motorbay_bore_in_plate"

measure() {
    python - "$1" <<'PY'
import re, sys, os
f = sys.argv[1]
if not os.path.exists(f):
    print("pass"); sys.exit(0)
txt = open(f).read()
tris = []
for fac in txt.split("facet normal")[1:]:
    vs = re.findall(r'vertex\s+(\S+)\s+(\S+)\s+(\S+)', fac)[:3]
    if len(vs) == 3:
        tris.append([tuple(round(float(c), 4) for c in v) for v in vs])
if not tris:
    print("pass"); sys.exit(0)

# Union-find over triangles sharing a vertex. WHY: the bounding box of the
# WHOLE result cannot tell a solid overlap from two separate face-to-face
# contacts lying in different planes. The tie plate touching both posts at
# X +/-110 measured 220 mm wide and read as a clash; the column enclosure
# touching a profile at Y 0 and again at Z 850 measured as the entire post.
# Judging each connected piece on its own kills that whole class of false
# alarm - and it is the reason tests no longer have to be split per side.
parent = list(range(len(tris)))
def find(a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]; a = parent[a]
    return a
def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb: parent[ra] = rb
seen = {}
for i, t in enumerate(tris):
    for v in t:
        if v in seen: union(i, seen[v])
        else: seen[v] = i

groups = {}
for i, t in enumerate(tris):
    groups.setdefault(find(i), []).append(t)

# Zero enclosed volume = parts merely touching. Not "flat bounding box": two
# contacts on faces that share an edge make one L-shaped piece with a 3-D box
# and 0 mm3 (mobile_base/check_covers.sh, drive hanger, 2026-10-07).
worst = None
for g in groups.values():
    vol = abs(sum(a[0] * (b[1] * c[2] - b[2] * c[1]) + a[1] * (b[2] * c[0] - b[0] * c[2])
                  + a[2] * (b[0] * c[1] - b[1] * c[0]) for a, b, c in g)) / 6
    xs, ys, zs = zip(*[v for t in g for v in t])
    d = [max(a) - min(a) for a in (xs, ys, zs)]
    if vol < 0.01 or min(d) < 0.01:
        continue
    if worst is None or vol > worst[0]:
        worst = (vol, d, xs, ys, zs)

if worst is None:
    print("touching  (zero thickness)"); sys.exit(0)
_, d, xs, ys, zs = worst
print("CLASH  %.0f x %.0f x %.0f mm   X %.1f..%.1f  Y %.1f..%.1f  Z %.1f..%.1f"
      % (d[0], d[1], d[2], min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
sys.exit(1)
PY
}

run_one() { # run_one <test> <extra -D flags...>
    t="$1"; shift
    if ! grep -q "test == \"$t\"" "$SCAD"; then
        echo "ERROR  no such test in $SCAD"; return 2
    fi
    "$OPENSCAD" -o "$OUT/$t.stl" --export-format=asciistl \
        -D "test=\"$t\"" "$@" "$SCAD" >"$OUT/$t.log" 2>&1
    if grep -qE "^ERROR|WARNING: Assert|Parser error" "$OUT/$t.log"; then
        echo "ERROR  see $OUT/$t.log"; return 2
    fi
    # An undefined variable makes the geometry undef, which makes the
    # intersection EMPTY, which reads exactly like a pass. On 2026-08-19 seven
    # stop/switch tests had been passing this way since the backbone rebuild,
    # because check_collisions.scad still referenced rail_riser_w. A test that
    # cannot resolve its own variables has not tested anything.
    if grep -q "Ignoring unknown variable" "$OUT/$t.log"; then
        echo "ERROR  undefined variable - the test proved nothing. See $OUT/$t.log"
        grep -m2 "Ignoring unknown variable" "$OUT/$t.log" | sed "s/^/         /"
        return 2
    fi
    if [ ! -f "$OUT/$t.stl" ] && ! grep -q "top level object is empty" "$OUT/$t.log"; then
        echo "ERROR  no output and no empty-object message - see $OUT/$t.log"; return 2
    fi
    measure "$OUT/$t.stl"
}

FAILED=0
printf '%-26s %s\n' "TEST" "RESULT"
printf -- '------------------------------------------------------------\n'
for t in $TESTS; do
    printf '%-26s ' "$t"; run_one "$t" || FAILED=$((FAILED+1))
done
for t in $DUAL_TESTS; do
    printf '%-26s ' "$t"; run_one "$t" -D 'show_dual_arm_mount=true' || FAILED=$((FAILED+1))
done

echo
echo "informational - an intersection here is the bore to machine, not a fault:"
for t in $INFO_TESTS; do
    printf '%-26s ' "$t"; run_one "$t" >/dev/null 2>&1
    if [ -f "$OUT/$t.stl" ]; then measure "$OUT/$t.stl" | sed 's/^CLASH /bore  /'
    else echo "no bore needed"; fi
done

echo
if [ "$FAILED" -eq 0 ]; then
    echo "ALL CLEAR - no interference in the modelled geometry."
else
    echo "$FAILED test(s) need attention. Open the .stl in $OUT to see the shared volume."
fi
echo "This checks the MODEL only. It says nothing about deflection, fastener"
echo "strength, or whether the axis back-drives. See README.md."
exit "$FAILED"
