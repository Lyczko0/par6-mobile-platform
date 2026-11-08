#!/usr/bin/env python3
"""Z column backbone - first fore-aft bending mode.

    python z_lift/backbone_stiffness.py

Two V-SLOT 40x80 profiles on edge (80 mm fore-aft), bought 2026-08-19.
Fore-aft is the binding direction: the arm hangs half a metre in front of
the column. Sideways the two profiles 260 mm apart are ~25x stiffer.

WHAT IS COMPUTED
  The first fore-aft mode by finite elements (Euler-Bernoulli beam): profiles,
  rails, screw and the printed shell as mass spread along the column; the
  carriage + adapter + arm as ONE rigid body at the carriage height, with its
  forward lever. When the column top tilts, the arm 0.5 m in front moves up
  and down - that rocking, not the column's own mass, pulls the mode down.
  Until 2026-10-05 this file had all of it as a point mass on the column tip
  and said 31.4 Hz; this model says 27.5.
  Masses are read from mobile_base/base_masses.scad at run time - no copies.

WHAT IS NOT
  The foot and the chassis under it are rigid in the main result; the sweep
  at the end shows what a soft foot costs. No bolted-joint slip. The steel
  rails on T-slot nuts add some stiffness this model throws away.
  The arm is one lump at base x 601 (arm_mount_x + reach, as in dynamics.py)
  without its own rotary inertia - the pose rows bound that.
"""

import math
import os
import re

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MASSES = os.path.join(HERE, "..", "mobile_base", "base_masses.scad")

E_AL = 68_600.0          # MPa, 6063-T5, FROM THE DATASHEET

# --- column, from parameters.scad (z_lift Z; the foot is s = 0 at Z 10) -----
L_COL = 840.0            # backbone_h, profiles Z 10..850
S_TOP = 711.25 - 10      # carriage_z_max: carriage centre at the top of travel
S_BOT = 137.0 - 10       # carriage_z_min
RAIL_SPACING = 260.0

# --- V-SLOT 40x80, 6063-T5, slot 8 - datasheet --------------------------------
DS_KGM = 3.20            # kg/m -> 1185 mm2
DS_IX = 788_000.0        # mm4, strong axis (80 mm in Y)
DS_WX = 17_400.0         # mm3
DS_IY = 216_000.0        # mm4, weak axis
RHO_AL_G_MM3 = 2.70e-3

# --- on the carriage: mm forward of the profiles' neutral axis (base x 85),
#     mm above the carriage centre ------------------------------------------
ARM_KG = 6.6 + 0.5       # PAR6 + tool + object, WEIGHED 2026-08-19
ARM_LEVER = 516.0        # base x 601 (dynamics.py ARM_X) - 85
ARM_UP = 35.0            # shelf 75 below the carriage centre, J2 110.5 above it
ARM_J1 = 222.0           # J1 axis: arm_mount_x 177 + shelf_reach 130 - 85
ARM_TIP = 646.0          # J1 + reach 424
ADAPTER_KG = 1.67        # asserted by par6_ref/adapter_stiffness.py

# --- stiffening fixes ---------------------------------------------------------
# Steel rails on the profile's front face: HGR20 centroid 48.75 mm in front
# of the profile's neutral axis (rail plane Y 80, rail 17.5 tall). Fully
# bonded they almost triple Ix; on T-slot nuts at 60 mm pitch they work
# somewhere between none and that. The model above takes none.
RAIL_D = 48.75
E_STEEL = 210_000.0
# Diagonal brace: two steel tubes 20 x 2 from just under the tie plate back
# to the chassis end plate. Bolted ends counted at half stiffness.
BRACE_S, BRACE_DX, BRACE_EA, BRACE_JOINT = 760.0, 345.0, E_STEEL * 113.0, 0.5
IX_8080, KGM_8080 = 1_650_000.0, 6.5     # 80x80 per profile        [VERIFY]


def scad_masses():
    """The column masses exactly as base_masses.scad computes them, kg."""
    with open(MASSES, encoding="utf-8") as fh:
        src = fh.read()

    def val(name):
        return eval(re.search(rf"^{name}\s*=\s*([^;]+);", src, re.M).group(1), {})

    def item(label, pattern):
        return re.search(rf'"{label}[^"]*",\s*{pattern}', src).group(1)

    def plate(l, w, t):
        return l * w * t * val("rho_al") * val("plate_hole_factor")

    rib = float(item("z_lift plyta ruchoma", r"plate_kg\([^)]*\)\s*\*\s*([\d.]+)"))
    d = val("zl_screw_d")
    return {
        "profiles": 2 * val("zl_profile")[2] / 1000 * val("prof_4080_kgm"),
        "rails": 2 * val("zl_rail_len") / 1000 * val("hgr20_kgm"),
        "screw": math.pi * (d / 2) ** 2 * val("zl_screw_len") * val("rho_fe"),
        "shell": val("col_shell_kg")[1],          # high end: solid print
        "tie": plate(*val("zl_tie")),
        "bf12": plate(*eval(item("wspornik BF12", r"plate_kg\(([^)]*)\)"), {})),
        "bearings": float(item("lozyskowanie", r"([\d.]+)")),
        "plate": plate(*val("zl_movplate")) * rib,
        "nut": float(item("nakretka", r"([\d.]+)")) + plate(*val("zl_nut_bracket")),
        "blocks": 4 * val("hgh20ca_kg"),
    }


M = scad_masses()
# load_paths.py and z_drive.py carry this sum; adapter_stiffness.py asserts it
CARRIAGE_KG = M["plate"] + M["nut"] + M["blocks"] + ADAPTER_KG


def carriage(adapter_kg=ADAPTER_KG, arm=((ARM_KG, ARM_LEVER, ARM_UP),)):
    """Rigid body on the carriage: (kg, mm forward, mm up). Positions from the
    base_masses.scad item list: plate base x 160, blocks 140, nut 105,
    adapter 249 and 48 below the carriage centre."""
    return [(M["plate"], 75, 0), (M["blocks"], 55, 0), (M["nut"], 20, 0),
            (adapter_kg, 164, -48), *arm]


def beam_mode(ei, length, dist, points, s_body, parts, k_foot=None, n=84,
              springs=()):
    """First mode of a cantilever, Hz. SI units: N*m2, m, kg, N*m/rad.

    dist    [(kg, s0, s1)] spread evenly over s0..s1 from the foot
    points  [(kg, s)]      on the neutral axis
    parts   [(kg, y, z)]   rigid body at s_body: y forward, z up from there.
            A forward lump moves up and down when the beam tilts - that is
            the y*y term below.
    k_foot  None = rigid foot, else a rotational spring there
    springs [(s, N/m)]     lateral springs to ground, e.g. a brace
    """
    nodes = np.unique(np.round(np.concatenate(
        [np.linspace(0, length, n + 1), [s_body], [p[1] for p in points],
         [sp[0] for sp in springs],
         [d[1] for d in dist], [d[2] for d in dist]]), 9))
    nd = len(nodes)
    K = np.zeros((2 * nd, 2 * nd))
    Mm = np.zeros_like(K)
    for e in range(nd - 1):
        h = nodes[e + 1] - nodes[e]
        mid = (nodes[e] + nodes[e + 1]) / 2
        mu = sum(kg / (s1 - s0) for kg, s0, s1 in dist if s0 <= mid <= s1)
        ke = ei / h ** 3 * np.array([[12, 6 * h, -12, 6 * h],
                                     [6 * h, 4 * h * h, -6 * h, 2 * h * h],
                                     [-12, -6 * h, 12, -6 * h],
                                     [6 * h, 2 * h * h, -6 * h, 4 * h * h]])
        me = mu * h / 420 * np.array([[156, 22 * h, 54, -13 * h],
                                      [22 * h, 4 * h * h, 13 * h, -3 * h * h],
                                      [54, 13 * h, 156, -22 * h],
                                      [-13 * h, -3 * h * h, -22 * h, 4 * h * h]])
        ix = np.arange(2 * e, 2 * e + 4)
        K[np.ix_(ix, ix)] += ke
        Mm[np.ix_(ix, ix)] += me

    def node(s):
        return int(np.argmin(abs(nodes - s)))

    for kg, s in points:
        Mm[2 * node(s), 2 * node(s)] += kg
    c = node(s_body)
    for kg, y, z in parts:
        Mm[2 * c:2 * c + 2, 2 * c:2 * c + 2] += kg * np.array([[1, z], [z, z * z + y * y]])
    for s, k in springs:
        K[2 * node(s), 2 * node(s)] += k
    if k_foot is not None:
        K[1, 1] += k_foot
    free = np.arange(1 if k_foot is not None else 2, 2 * nd)
    w2 = np.linalg.eigvals(np.linalg.solve(Mm[np.ix_(free, free)],
                                           K[np.ix_(free, free)])).real
    return math.sqrt(w2[w2 > 0].min()) / (2 * math.pi)


def column_mode(ix=DS_IX, parts=None, s_carr=S_TOP, k_foot=None,
                spread=True, shell=M["shell"], profiles=M["profiles"],
                springs=()):
    """First fore-aft mode of THIS column, Hz. ix per profile, mm4;
    springs [(mm from the foot, N/mm)]."""
    parts = carriage() if parts is None else parts
    mm = 1e-3
    if spread:
        dist = [(profiles, 0, L_COL), (M["rails"], 10, 810),
                (M["screw"], 40, 780), (shell, 0, L_COL)]
        # BK12 + BF12 lumped at the top: the split is not known, top is safe
        points = [(M["tie"], 767), (M["bf12"], 780), (M["bearings"], 780)]
    else:
        dist, points = [(1e-6, 0, L_COL)], []
    return beam_mode(E_AL * 2 * ix * 1e-6, L_COL * mm,
                     [(kg, s0 * mm, s1 * mm) for kg, s0, s1 in dist],
                     [(kg, s * mm) for kg, s in points], s_carr * mm,
                     [(kg, y * mm, z * mm) for kg, y, z in parts], k_foot,
                     springs=[(s * mm, k * 1e3) for s, k in springs])


def selfcheck():
    """The FE must reproduce the two textbook cantilevers."""
    ei, ln, tip, mu = 1.0e5, 0.8, 10.0, 5.0
    f_tip = math.sqrt(3 * ei / ln ** 3 / tip) / (2 * math.pi)
    got = beam_mode(ei, ln, [(1e-6, 0, ln)], [], ln, [(tip, 0, 0)])
    assert abs(got / f_tip - 1) < 0.005, (got, f_tip)
    f_uni = 1.8751041 ** 2 / (2 * math.pi) * math.sqrt(ei / (mu * ln ** 4))
    got = beam_mode(ei, ln, [(mu * ln, 0, ln)], [], ln, [])
    assert abs(got / f_uni - 1) < 0.005, (got, f_uni)


def main():
    selfcheck()
    c_kg = sum(p[0] for p in carriage())
    print("=" * 74)
    print("  KREGOSLUP KOLUMNY Z - pierwsza postac przod-tyl, 2 x 40x80 na sztorc")
    print("=" * 74)
    print("  masy z mobile_base/base_masses.scad:")
    print(f"    po calej kolumnie  profile {M['profiles']:.2f}, prowadnice "
          f"{M['rails']:.2f}, sruba {M['screw']:.2f}, skorupa {M['shell']:.2f} kg")
    print(f"    u gory             plyta spinajaca {M['tie']:.2f}, BF12 z "
          f"lozyskami {M['bf12'] + M['bearings']:.2f} kg")
    print(f"    na wozku           plyta {M['plate']:.2f}, wozki {M['blocks']:.2f}, "
          f"nakretka {M['nut']:.2f}, adapter {ADAPTER_KG:.2f},")
    print(f"                       ramie {ARM_KG:.1f} na {ARM_LEVER:.0f} mm przed "
          f"kolumna - razem {c_kg:.1f} kg")
    print(f"  wozek w gorze: srodek {S_TOP:.0f} mm nad stopa, kolumna {L_COL:.0f}")

    # The datasheet contradicts itself: Ix / Wx puts the extreme fibre at
    # 45.3 mm in an 80 mm section. Both readings stay in play.
    area = DS_KGM / RHO_AL_G_MM3
    i_lo, i_hi = area * 80.0 ** 2 / 12.0, area / 2 * 40.0 ** 2 * 2
    ix_wx = DS_WX * 40.0
    assert i_lo < ix_wx < DS_IX < i_hi
    print()
    print(f"  Ix: karta {DS_IX / 1e4:.1f} cm4, ale Ix/Wx daje skrajne wlokno na "
          f"{DS_IX / DS_WX:.1f} mm przy 40 mozliwych.")
    print(f"  Z Wx wychodzi {ix_wx / 1e4:.1f} cm4. Masa dopuszcza "
          f"{i_lo / 1e4:.0f}-{i_hi / 1e4:.0f} cm4 - oba sa wiarygodne.")

    print()
    print(f"  {'Ix':<26}{'wozek w gorze':>15}{'wozek na dole':>15}")
    for label, ix in (("z karty", DS_IX), ("z Wx", ix_wx)):
        print(f"  {label + f' {ix / 1e4:.1f} cm4':<26}"
              f"{column_mode(ix):>12.1f} Hz{column_mode(ix, s_carr=S_BOT):>12.1f} Hz")

    f0 = column_mode()
    f_wx = column_mode(ix_wx)
    lump = [(c_kg, 0, 0)]
    print()
    print("  " + "-" * 70)
    print("  CO ZJADA CZESTOTLIWOSC (Ix z karty, wozek w gorze)")
    print("  " + "-" * 70)
    steps = (
        ("caly wozek z ramieniem na czubku kolumny", column_mode(parts=lump, s_carr=L_COL, spread=False)),
        ("... na prawdziwej wysokosci wozka", column_mode(parts=lump, spread=False)),
        ("+ masa kolumny, prowadnic, sruby, skorupy", column_mode(parts=lump)),
        ("+ dzwignia ramienia - kolysanie przod-tyl", f0),
    )
    for label, f in steps:
        print(f"  {label:<48}{f:>7.1f} Hz")

    print()
    print("  RAMIE - gdzie naprawde siedzi jego masa, nie zmierzone (poz. 21):")
    for label, y in (("cale w osi J1 - gorna granica", ARM_J1),
                     ("cale na 601 - jak dynamics.py", ARM_LEVER),
                     ("cale na koncu zasiegu - dolna granica", ARM_TIP)):
        f = column_mode(parts=carriage(arm=((ARM_KG, y, ARM_UP),)))
        print(f"    {label:<46}{f:>7.1f} Hz")

    print()
    print("  " + "-" * 70)
    print("  STOPA - ile kosztuje podatne polaczenie z rama (Ix z karty)")
    print("  " + "-" * 70)
    k_ref = E_AL * 2 * DS_IX * 1e-6 / 0.020
    for label, k in (("sztywna - SUFIT, wiecej zastrzal nie da", None),
                     ("10 MN*m/rad", 1.0e7),
                     (f"{k_ref / 1e6:.1f} MN*m/rad = 2 cm profilu wiecej", k_ref),
                     ("2.7 MN*m/rad", k_ref / 2),
                     ("1.4 MN*m/rad", k_ref / 4)):
        print(f"    {label:<46}{column_mode(k_foot=k):>7.1f} Hz")

    # rails fully bonded: transformed section, steel -> aluminium by E ratio
    a_r = M["rails"] / 2 / 0.8 / 7.85e-3 * E_STEEL / E_AL      # mm2, one rail
    ybar = a_r * RAIL_D / (area + a_r)
    ix_bond = DS_IX + area * ybar ** 2 + a_r * (RAIL_D - ybar) ** 2
    l_br = math.hypot(BRACE_S, BRACE_DX)
    k_br = 2 * BRACE_JOINT * BRACE_EA / l_br * (BRACE_DX / l_br) ** 2   # N/mm
    print()
    print("  " + "-" * 70)
    print("  CO MOZNA ZROBIC (Ix z karty, wozek w gorze)")
    print("  " + "-" * 70)
    rows = (
        ("nic - model bez szyn", f0),
        ("nic - szyny w pelni zespolone (gora)", column_mode(ix_bond)),
        ("zastrzal u stopy (2 czesci PCBWay)", f0),
        ("ukosnik: 2 rury 20x2 do ramy", column_mode(springs=((BRACE_S, k_br),))),
        ("2 x 80x80 zamiast 40x80", column_mode(IX_8080, profiles=2 * 0.84 * KGM_8080)),
    )
    for label, f in rows:
        print(f"    {label:<40}{f:>6.1f} Hz")
    print(f"  Szyny i tak ida na 13 srub kazda (BOM 5.7) i usztywniaja profil:")
    print(f"  w pelni zespolone daja Ix {ix_bond / 1e4:.0f} cm4 zamiast {DS_IX / 1e4:.1f}."
          f" Realnie gdzies pomiedzy -")
    print("  dlatego najpierw test stukniecia, potem pieniadze.")

    i_side = 2 * (DS_IY + area * (RAIL_SPACING / 2) ** 2)
    print()
    print(f"  W bok: dwa profile {RAIL_SPACING:.0f} mm od siebie, "
          f"{i_side / (2 * DS_IX):.0f}x sztywniej - nie ogranicza.")

    print()
    print("=" * 74)
    print("  WERDYKT")
    print("=" * 74)
    print(f"  Sufit, stopa idealnie sztywna: {f0:.1f} Hz (Ix z karty), "
          f"{f_wx:.1f} Hz (Ix z Wx).")
    print("  Ponizej bufora 35 Hz i progu 30 Hz na zastrzal u stopy. ZASTRZAL")
    print("  NIE POMOZE: usztywnia stope, a sufit juz liczy ja idealnie sztywna.")
    print("  Do 30 Hz brakuje sztywnosci samej kolumny albo krotszej dzwigni")
    print("  ramienia - ukosnik z gory kolumny w tyl do ramy albo 80x80.")
    print()
    print("  Bufor 35 Hz pokrywal rame z dwoch profili zwiazanych u gory i u")
    print("  dolu. Ta dziala tylko w bok - w przod-tyl kazdy profil gnie sie")
    print("  sam i przekroj jest dokladny. Zjadly go za to dzwignia ramienia i")
    print("  masa kolumny, ktorych stary model nie mial.")
    print("  Najwyzsza postac samego ramienia: 5.2 Hz (zmierzone, shaper 5 Hz).")
    print(f"  Kolumna na {f_wx:.0f}-{f0:.0f} Hz jest 5x wyzej - ramie jej nie rozbuja.")
    print()
    print("  DO DECYZJI: przyjac i zmierzyc po zlozeniu (telefon na gorze")
    print("  kolumny, stuknac, pik w widmie). Ponizej ~23 Hz - miekka stopa,")
    print("  wtedy zastrzal; ponizej 20 Hz - ukosnik. Zadna z tych czesci nie")
    print("  musi isc w zamowieniu PCBWay: ukosnik to profil albo rura.")


if __name__ == "__main__":
    main()
