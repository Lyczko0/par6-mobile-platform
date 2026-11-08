#!/usr/bin/env bash
# Runs every interference test in check_covers.scad.
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
#   ERROR/assert lines. Without all three, a broken test reads as a pass.
#
#   ./check_collisions.sh
#   OPENSCAD='/c/Program Files/OpenSCAD/openscad.exe' ./check_collisions.sh

set -u
# The check list runs this from the repo root. Without the cd, OpenSCAD could not
# open check_covers.scad, and the matrix below took "no file" for a pass:
# 117 cells of "." that checked nothing (found 2026-10-03).
cd "$(dirname "$0")"
OPENSCAD="${OPENSCAD:-openscad}"
command -v "$OPENSCAD" >/dev/null 2>&1 || OPENSCAD='/c/Program Files/OpenSCAD/openscad.com'
OUT=".chk"
SCAD="check_covers.scad"
rm -rf "$OUT"; mkdir -p "$OUT"

COVERS="A B C D E F G I J K"
KEEPS="wheel caster antitip column battery cable ground wheelout estop charger fuse mainsw ballast axle"

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

# Zero enclosed volume = parts merely touching. Not "flat bounding box": the
# drive hanger wraps the beam's bottom corner, plate under it and leg on its
# face, and the two contacts share an edge - one L-shaped piece, 60 x 16 x 16
# mm and 0 mm3, reported as a CLASH (2026-10-07).
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
    # An undefined variable yields undef geometry, an empty intersection and
    # a PASS that proved nothing. Seven z_lift tests passed this way after a
    # refactor deleted a variable the test still referenced. Treat it as fatal.
    if grep -q "Ignoring unknown variable" "$OUT/$t.log"; then
        echo "ERROR  undefined variable - the test proved nothing, see $OUT/$t.log"
        return 2
    fi
    if grep -qE "^ERROR|WARNING: Assert|Parser error" "$OUT/$t.log"; then
        echo "ERROR  see $OUT/$t.log"; return 2
    fi
    if [ ! -f "$OUT/$t.stl" ] && ! grep -q "top level object is empty" "$OUT/$t.log"; then
        echo "ERROR  no output and no empty-object message - see $OUT/$t.log"; return 2
    fi
    measure "$OUT/$t.stl"
}

FAILED=0
printf '%-6s' ""; for k in $KEEPS; do printf '%-9.8s' "$k"; done; echo
printf -- '--------------------------------------------------------------------------------------------------------
'
for c in $COVERS; do
    printf '%-6s' "$c"
    for k in $KEEPS; do
        "$OPENSCAD" -o "$OUT/${c}_$k.stl" --export-format=asciistl             -D "cover_id=\"$c\"" -D "keep_id=\"$k\"" check_covers.scad             >"$OUT/${c}_$k.log" 2>&1
        if grep -q "Ignoring unknown variable" "$OUT/${c}_$k.log"; then
            # Undefined -> undef -> empty geometry -> empty intersection -> a
            # test that proved nothing. It printed ERR! and then walked past
            # without touching FAILED, so the script still exited 0. That is
            # exactly the false pass that must be fatal.
            printf '%-9s' "ERR!"; FAILED=$((FAILED+1)); continue
        fi
        if grep -qE "^ERROR|WARNING: Assert|Parser error" "$OUT/${c}_$k.log"; then
            printf '%-9s' "ERR"; FAILED=$((FAILED+1))
        elif [ ! -f "$OUT/${c}_$k.stl" ]; then
            # no file is a PASS only with the empty-object message - the
            # fourth condition, which this loop did not have until 2026-10-03
            if grep -q "top level object is empty" "$OUT/${c}_$k.log"; then
                printf '%-9s' "."
            else
                printf '%-9s' "ERR"; FAILED=$((FAILED+1))
            fi
        else
            R=$(measure "$OUT/${c}_$k.stl")
            case "$R" in
                pass*)     printf '%-9s' "." ;;
                touching*) printf '%-9s' "styk" ;;
                *)         printf '%-9s' "FAIL"; FAILED=$((FAILED+1)) ;;
            esac
        fi
    done
    echo
done

echo
echo "oslona vs oslona:"
"$OPENSCAD" -o "$OUT/cc.stl" --export-format=asciistl -D 'test="covers_vs_covers"'     check_covers.scad >"$OUT/cc.log" 2>&1
if [ -f "$OUT/cc.stl" ]; then
    R=$(measure "$OUT/cc.stl")
    case "$R" in
        pass*)     echo "  pass" ;;
        touching*) echo "  styk (dopuszczalne - panele stykaja sie licami)" ;;
        *) echo "  $R"; FAILED=$((FAILED+1)) ;;
    esac
elif grep -qE "^ERROR|WARNING: Assert|Parser error|Ignoring unknown variable" "$OUT/cc.log" \
     || ! grep -q "top level object is empty" "$OUT/cc.log"; then
    echo "  ERROR  see $OUT/cc.log"; FAILED=$((FAILED+1))
else
    echo "  pass"
fi

echo
echo "architektura (bryly, nie oslony):"
# caster_vs_battery i caster_vs_tray byly zdefiniowane w check_covers.scad od
# poczatku, ale ten skrypt nigdy ich nie wywolywal - test, ktory nie biegnie,
# niczego nie dowodzi, a wyglada jak pokrycie. run_one ma pelna czterowarunkowa
# ochrone przed pustym PASS; tu uzywamy jej, zamiast pisac petle drugi raz.
ARCH="caster_vs_battery caster_vs_cradle caster_vs_cable cable_vs_column
      ballast_vs_caster ballast_vs_wheels ballast_vs_battery
      ballast_vs_drive ballast_vs_endplate ballast_vs_elec
      drive_vs_covers drive_vs_wheels drive_vs_axle
      axle_vs_battery axle_vs_cradle axle_vs_cable axle_vs_frame axle_vs_elec
      axle_vs_column axle_vs_ballast drive_vs_battery drive_vs_cradle
      battery_vs_frame"
for t in $ARCH; do
    R=$(run_one "$t"); RC=$?
    printf '  %-22s ' "$t"
    if [ "$RC" -eq 2 ]; then
        echo "$R"; FAILED=$((FAILED+1)); continue
    fi
    case "$R" in
        pass*)     echo "pass" ;;
        touching*) echo "styk" ;;
        *)         echo "$R"; FAILED=$((FAILED+1)) ;;
    esac
done

echo
echo "pary, ktore MUSZA sie stykac (czesc przykrecona, nie wiszaca):"
# Every other test passes on "no shared volume". For a joint that is the
# wrong answer: a bracket in mid-air shares nothing and would pass. Here a
# plain pass is the FAIL (2026-10-03, when the cover fastening was drawn).
for t in drive_vs_frame brackets_vs_frame brackets_vs_covers tubes_vs_endplates cradle_vs_frame; do
    R=$(run_one "$t"); RC=$?
    printf '  %-22s ' "$t"
    if [ "$RC" -eq 2 ]; then
        echo "$R"; FAILED=$((FAILED+1)); continue
    fi
    case "$R" in
        touching*) echo "styk" ;;
        pass*)     echo "FAIL - nie styka sie, czesc wisi"; FAILED=$((FAILED+1)) ;;
        *)         echo "$R"; FAILED=$((FAILED+1)) ;;
    esac
done

echo
echo "ramie PAR6 i jego wspornik:"
# check_arm.scad had these four since the adapter was drawn, and nothing ran
# them (found 2026-09-25, when the adapter was about to change). Same run_one.
SCAD="check_arm.scad"
for t in swing_vs_covers_low swing_vs_covers_high swing_vs_base_low bracket_vs_covers; do
    R=$(run_one "$t"); RC=$?
    printf '  %-22s ' "$t"
    if [ "$RC" -eq 2 ]; then
        echo "$R"; FAILED=$((FAILED+1)); continue
    fi
    case "$R" in
        pass*)     echo "pass" ;;
        touching*) echo "styk" ;;
        *)         echo "$R"; FAILED=$((FAILED+1)) ;;
    esac
done
SCAD="check_covers.scad"

echo
echo "legenda:  . = PASS (brak wspolnej objetosci)   styk = zerowa grubosc   FAIL = kolizja"
echo
if [ "$FAILED" -eq 0 ]; then
    echo "ALL CLEAR - no interference in the modelled geometry."
else
    echo "$FAILED test(s) need attention. Open the .stl in $OUT to see the shared volume."
fi
echo "This checks the MODEL only. It says nothing about deflection, fastener"
echo "strength, or whether the axis back-drives. See README.md."
exit "$FAILED"
