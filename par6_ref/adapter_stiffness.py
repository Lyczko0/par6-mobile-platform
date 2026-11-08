#!/usr/bin/env python3
"""P2 - the PAR6 adapter as bent sheet instead of 10 mm plate + CNC.

    python par6_ref/adapter_stiffness.py

Same method as control/load_paths.py section 5 used to have inline (the
shelf's curvature integrated along its reach) - that section now calls this
file, so there is one model of the adapter. Plus the term it left out: the
vertical plate between the carriage's lower bolt row and the bend. With
gussets that run up past that bolt row it carries nothing; without them the
whole root moment bends it.

Criteria, fixed BEFORE the numbers:
  1. the arm's pitch mode on the adapter >= 35 Hz - the column's own
     threshold (backbone_stiffness.py); the adapter must not be the weak link;
  2. static error at the gripper <= 0.2 mm - below PAR6-class repeatability,
     so the adapter does not dominate it.
The column's first mode is re-run with each variant's mass: the adapter rides
on the carriage, and that mode is BELOW the same 35 Hz already.

A gusset's height here is what stands ABOVE the shelf. load_paths.py counted
the full 63 mm of the old gusset polygon as rib, but 10 of those overlapped
the 10 mm shelf - 53 stood above it, so the old adapter was 0.123 mm, not the
0.092 it reported.

ADAPTER_KG below is the drawn part's mass; backbone_stiffness.py, load_paths.py
and z_drive.py each copy it, and main() asserts every copy.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "z_lift"))
sys.path.insert(0, os.path.join(HERE, "..", "control"))

G = 9.81
RHO = 2.70e-6            # kg/mm3, aluminium
E = 70_000.0             # MPa - 6082 and 5754 alike within 2 %

# --- the load, weighed arm -------------------------------------------------------
ARM_ONLY, PAYLOAD = 6.6, 0.5         # ZWAZONE 2026-08-19
ARM_CG_R, ARM_REACH = 170.0, 424.0   # CG radius is an assumption  [MEASURE]
REACH = 130.0                        # J1 in front of the carriage face (shelf_reach)
M_BASE = (ARM_ONLY * G * ARM_CG_R + PAYLOAD * G * ARM_REACH) / 1000.0   # N*m
F_J1 = (ARM_ONLY + PAYLOAD) * G                                         # N
M_ROOT = M_BASE + F_J1 * REACH / 1000.0
# pitch inertia of the arm about the carriage face (conservative: the spring
# is spread along the shelf, the inertia is taken about its root)
J_ARM = (ARM_ONLY * ((REACH + ARM_CG_R) / 1000) ** 2
         + PAYLOAD * ((REACH + ARM_REACH) / 1000) ** 2)

# --- geometry, par6_adapter.scad ---------------------------------------------
PLATE_H = 165.0                  # vertical plate height
SHELF_L = 225.0                  # shelf_reach + 95
OLD_W, NEW_W = 190.0, 200.0      # shelf (and plate) width, before / after P2
BEND_R = 6.0                     # adapter_bend_r, 1t              [VERIFY] PCBWay
BOLT_ROW_TO_BEND = 35.0          # lower M6 row (z -50) to the shelf (z -75) + bend
SHOULDER_ABOVE_SHELF = 70.5      # base_link height: the shoulder sweeps above it
RIB_CEILING = SHOULDER_ABOVE_SHELF - 7.5
DESIGN = dict(t=6.0, tg=6.0, h=63.0, rib_l=SHELF_L, w=NEW_W, tab=33.0)


def shelf_i(t, tg, h, w):
    """Shelf t thick, w wide, with two gussets tg thick standing h above it."""
    a1, y1 = w * t, t / 2
    if h <= 0 or tg <= 0:
        return w * t ** 3 / 12.0
    a2, y2 = 2 * tg * h, t + h / 2
    ybar = (a1 * y1 + a2 * y2) / (a1 + a2)
    return (w * t ** 3 / 12 + a1 * (y1 - ybar) ** 2
            + 2 * tg * h ** 3 / 12 + a2 * (y2 - ybar) ** 2)


def evaluate(t, tg, h, root_free=False, rib_l=150.0, taper=True, w=OLD_W):
    """(gripper error mm, arm pitch mode Hz, root stress MPa)."""
    n = 2000
    dx = REACH / n
    theta = defl = comp = 0.0
    for i in range(n):
        x = (i + 0.5) * dx
        ei = E * shelf_i(t, tg, h * (max(1 - x / rib_l, 0.0) if taper else 1.0), w)
        mx = (M_BASE + F_J1 * (REACH - x) / 1000.0) * 1000.0      # N*mm
        theta += mx / ei * dx
        defl += mx / ei * (REACH - x) * dx
        comp += dx / ei                                           # rad per N*mm
    if root_free:
        # the plate below the lower bolt row bends as a short cantilever
        ei_v = E * w * t ** 3 / 12.0
        theta_r = M_ROOT * 1000.0 * BOLT_ROW_TO_BEND / ei_v
        theta += theta_r
        defl += theta_r * REACH
        comp += BOLT_ROW_TO_BEND / ei_v
    k_rot = 1.0 / comp / 1000.0                                   # N*m per rad
    f_pitch = math.sqrt(k_rot / J_ARM) / (2 * math.pi)
    sig = M_ROOT * 1000.0 * (t + h) / 2 / shelf_i(t, tg, h, w)
    return theta * ARM_REACH + defl, f_pitch, sig


def rough_mass(t, tg, h, tabs, rib_l=150.0, taper=True, w=OLD_W):
    """Plates and ribs as plain blanks - good enough to rank the variants."""
    m = (PLATE_H * w * t + SHELF_L * w * t) * RHO
    if tg and h:
        rib = rib_l * h / 2 if taper else rib_l * h
        if tabs:                             # bent tab along both bolted edges
            rib += 33.0 * rib_l + 33.0 * h
        m += 2 * rib * tg * RHO
    return m


def design_mass():
    """The drawn part: bent angle with its bend, two ribs with tabs, holes out.
    Reproduces the OpenSCAD model's volume (1.671 kg on 2026-09-25) to 0.5 %."""
    d = DESIGN
    t, r, w, tab, h, L = d["t"], BEND_R, d["w"], d["tab"], d["h"], d["rib_l"]
    plate = (PLATE_H / 2 - (-75.0 + r)) * w * t                  # straight, above the bend
    shelf = (L - (t + r)) * w * t
    bend = math.pi / 4 * ((r + t) ** 2 - r ** 2) * w
    holes = (4 * math.pi * 3.3 ** 2 + 2 * math.pi * 20 ** 2        # M6 raster, 2 bores
             + 4 * (56.2 * math.radians(40) * 5.6 + math.pi * 2.8 ** 2)   # arc slots
             + 10 * math.pi * 2.75 ** 2) * t                        # rib tab bolts
    rel = r + 1
    rib = ((L - t) * h / 2 - rel * rel + (L - t - rel) * tab + (h - rel) * tab
           - 5 * math.pi * 2.75 ** 2) * d["tg"]
    return (plate + shelf + bend - holes + 2 * rib) * RHO


ADAPTER_KG = round(design_mass(), 2)


VARIANTS = [
    # name, t, gusset t, gusset h above shelf, bolted tabs, root free, [rib_l, taper]
    ("V0  przed P2: plyty 10 mm + zebra 8 mm, CNC", 10.0, 8.0, 53.0, False, False),
    ("V1  jedna gieta blacha L 6 mm, bez zeber", 6.0, 0.0, 0.0, False, True),
    ("V2  L 6 + 2 giete zebra 6, h 63, do 150", 6.0, 6.0, 63.0, True, False),
    ("V2x L 6 + 4 giete zebra 6, h 63, do 150", 6.0, 12.0, 63.0, True, False),
    ("V3  rynna: scianki 6 h 63 na calej dl.", 6.0, 6.0, 63.0, True, False, SHELF_L, False),
]


def main():
    import backbone_stiffness as bb
    import load_paths
    import z_drive

    def column_mode(adapter_kg):
        return bb.column_mode(parts=bb.carriage(adapter_kg))

    print("=" * 80)
    print("  P2 - ADAPTER PAR6: blacha gieta zamiast plyt 10 mm i CNC")
    print("=" * 80)
    print(f"  obciazenie: moment ramienia {M_BASE:.1f} N*m + {F_J1:.0f} N na J1,"
          f" u nasady {M_ROOT:.1f} N*m")
    print(f"  bezwladnosc ramienia wzgledem lica wozka  {J_ARM:.3f} kg*m2")
    print("  kryteria: postac ramienia >= 35 Hz  I  blad na chwytaku <= 0.20 mm")
    print(f"  zebro najwyzej {RIB_CEILING:.0f} mm nad polka - wyzej zamiata bark PAR6")
    print()
    print(f"  {'wariant':<44}{'blad':>7}{'postac':>8}{'napr.':>7}{'masa':>7}{'kolumna':>9}")
    print(f"  {'':<44}{'mm':>7}{'Hz':>8}{'MPa':>7}{'kg':>7}{'Hz':>9}")
    rows = []
    for name, t, tg, h, tabs, root_free, *rib in VARIANTS:
        err, f, sig = evaluate(t, tg, h, root_free, *rib)
        rows.append((name, err, f, sig, rough_mass(t, tg, h, tabs, *rib)))
    d = DESIGN
    err, f, sig = evaluate(d["t"], d["tg"], d["h"], False, d["rib_l"], True, d["w"])
    rows.append(("PROJEKT: L 6 + 2 zebra 6 przez cala polke", err, f, sig, ADAPTER_KG))
    verdicts = {}
    for name, err, f, sig, m in rows:
        ok = f >= 35.0 and err <= 0.20
        verdicts[name.split()[0]] = ok
        print(f"  {name:<44}{err:>7.3f}{f:>8.1f}{sig:>7.1f}{m:>7.2f}"
              f"{column_mode(m):>9.1f}   {'OK' if ok else 'ODPADA'}")
    print()
    print("  'kolumna' = pierwsza postac kregoslupa z ta masa adaptera na wozku")
    print("  (backbone_stiffness.py, Ix z karty). Werdykt kolumny jest tam, nie tu.")
    print("  V3 najsztywniejsza, ale to pudelko z 5 giec w 6 mm - PROJEKT to trzy")
    print("  proste czesci z tej samej uslugi, z zapasem 2x na oba kryteria.")
    print("  NIE liczone: podatnosc polaczen srubowych zeber. Zapas ja pokrywa:")
    print("  nawet polowa sztywnosci daje ~48 Hz. Zakladka tylna zebra obejmuje")
    print("  dolny rzad srub wozka (z -50), wiec moment nie idzie przez sama plyte.")

    assert not verdicts["V1"], "gola gieta blacha nie moze przejsc"
    assert verdicts["V0"], "stary adapter nie przechodzi wlasnych kryteriow - kryteria do rewizji"
    assert verdicts["PROJEKT:"], "narysowany adapter nie przechodzi kryteriow"
    assert d["h"] <= RIB_CEILING, "zebro wchodzi pod bark PAR6"
    # every script that copies the adapter's mass must carry THIS mass
    for mod in (bb, load_paths, z_drive):
        assert abs(mod.ADAPTER_KG - ADAPTER_KG) < 0.02, \
            f"{mod.__name__}.ADAPTER_KG = {mod.ADAPTER_KG}, projekt {ADAPTER_KG}"
    # bb reads the carriage from base_masses.scad; these two copy the sum
    for mod in (load_paths, z_drive):
        assert abs(mod.CARRIAGE_KG - bb.CARRIAGE_KG) < 0.02, \
            f"{mod.__name__}.CARRIAGE_KG = {mod.CARRIAGE_KG}, base_masses {bb.CARRIAGE_KG:.3f}"
    # ... and so must the mass model the stability verdict is built on
    import re
    with open(os.path.join(HERE, "..", "mobile_base", "base_masses.scad"), encoding="utf-8") as fh:
        hit = re.search(r'"wspornik PAR6[^"]*",\s*([\d.]+),\s*([\d.]+)', fh.read())
    assert hit and all(abs(float(v) - ADAPTER_KG) < 0.02 for v in hit.groups()), \
        f"base_masses.scad: wspornik PAR6 = {hit.groups() if hit else None}, projekt {ADAPTER_KG}"
    return err, f


if __name__ == "__main__":
    main()
