#!/usr/bin/env python3
"""Uchwyt kola napedowego - wieszaki: co trzyma, a co nie.

    python mobile_base/drive_hanger.py

DLACZEGO
  Gniazdo musi lezec na plasku osi, a plask konczy sie 89 mm od srodka
  opony - wiec kolo stoi ~111 mm poza srodkiem gniazda. Jego nacisk wchodzi
  w uchwyt glownie jako MOMENT przechylajacy wokol X, nie jako sila.
  Pierwszy rysunek (V0) oddawal ten moment belce stopka na JEDNEJ M6 w dolnym
  rowku: dolne lico 40 mm ma jeden rowek na srodku, ramie ~20 mm, nakretka
  wyrywana 4x. Narysowany od 2026-10-07 (V2): noga na wewnetrznym licu belki,
  4 x M6 w jego dolnym rowku; moment trzyma docisk krawedzi + scinanie.

LICZY
  sily na kole w trzech przypadkach, reakcje w gniezdzie, podzial na dwa
  wieszaki, pare M5 gniazdo-wieszak, srube stopki (podwazanie), zginanie
  scianki - dla wersji narysowanej (V0) i z noga na wewnetrznym licu belki
  (V2), gdzie moment trzyma para: docisk przy zewnetrznej krawedzi spodu
  belki i sruby w rowku lica, scinane, na ramieniu ~43 mm.
NIE LICZY
  zmeczenia (prog to tysiace cykli), podatnosci rowka i opony. Caly robot
  stoi na napedzie (omni i caster odciazone na nierownosci) - to gorna
  granica. Mnoznik dynamiczny i nosnosc nakretki to ZALOZENIA, nizej.
Geometria z base_parameters.scad (czytana, nie przepisana), masy i tarcie
z control/dynamics.py.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "control"))
import dynamics as dyn  # noqa: E402  masy i tarcie - jedno zrodlo

with open(os.path.join(HERE, "base_parameters.scad"), encoding="utf-8") as fh:
    _EXPR = {m.group(1): m.group(2) for m in
             re.finditer(r"^(\w+)\s*=\s*([^;]+);", fh.read(), re.M)}


class _Scad(dict):
    """Top-level assignments of base_parameters.scad, evaluated on demand."""
    def __missing__(self, name):
        self[name] = eval(_EXPR[name], {"__builtins__": {}}, self)
        return self[name]


P = _Scad()
G = 9.81

# --- zalozenia - podmien, gdy bedzie pomiar albo karta ------------------------
K_DYN = 2.5           # prog 20 mm / uderzenie: mnoznik nacisku kola    [ZALOZENIE]
TNUT_N = 1000.0       # dopuszczalne wyrwanie nakretki M6 z rowka V-slot   [VERIFY karta]
M5_SHEAR_N = 3400.0   # M5 8.8 na scinanie: 0.6 * 800 * 14.2 mm2 / zapas 2
M6_PRELOAD_N = 5000.0 # naciag M6 8.8 przy ~9 N*m w nakretce mloteczkowej  [VERIFY]
MU_JOINT = 0.2        # tarcie alu-alu w zlaczu, bez przygotowania
SIG_ALLOW = 100.0     # MPa, blacha 5052-H32 / 6061, zapas ~1.6 na plastycznosc

# --- geometria -----------------------------------------------------------------
Y_SEAT = (P["seat_y0"] + P["seat_y1"]) / 2            # srodek gniazda
Z_AXLE = P["wheel_radius"]
R_CONTACT = (0.0, P["wheel_y"] - Y_SEAT, -Z_AXLE)     # styk opony od gniazda
X_HANGER = P["seat_w"] / 2 + P["hanger_t"] / 2        # os scianki wieszaka
Z_BOLT = P["seat_top_z"] - P["seat_h"] / 2            # para M5 w boku gniazda
Z_FLANGE = P["frame_bottom_z"]                        # spod belki
Y_BEAM_IN = P["main_beam_y"] - P["profile_main_w"] / 2
Y_BEAM_OUT = P["main_beam_y"] + P["profile_main_w"] / 2 - 0.5
# V0 - pierwsza wersja, juz nienarysowana: tylko do porownania
V0_Y0, V0_FLANGE = 110.0, 20.0


def wheel_cases():
    m = dyn.ROBOT_KG + dyn.ARM_KG
    cy = dyn.ARM_KG * dyn.ARM_REACH / m                # ramie wyciagniete w bok
    f = m * G * (0.5 + cy / (2 * P["wheel_y"]))        # blizsze kolo
    return f, [("prog / uderzenie", 0.0, 0.0, K_DYN * f),
               ("ruszanie / hamowanie", dyn.MU * f, 0.0, f),
               ("poslizg w bok", 0.0, dyn.MU * f, f)]


def seat_load(fx, fy, fz):
    """Force and moment (N, N*mm) the axle puts into the seat centre."""
    rx, ry, rz = R_CONTACT
    return (fx, fy, fz), (ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx)


def hangers(F, M, y_bolts):
    """Every web / sign combination: (M5 shear, web stress, N, H, V, Mi).
    The couples from My and Mz load one web up and the other down, so each
    quantity takes its own worst combination - not the row of another one."""
    fx, fy, fz = F
    mx, my, mz = M
    s_b = abs(y_bolts[1] - y_bolts[0])
    b_web = Y_BEAM_OUT - min(y_bolts) + 8
    t = P["hanger_t"]
    rows = []
    for sv in (1, -1):
        for sh in (1, -1):
            V = fz / 2 + sv * abs(my) / (2 * X_HANGER)       # pion, w plaszczyznie
            H = fy / 2 + sh * abs(mz) / (2 * X_HANGER)       # wzdluz osi kola
            N = fx / 2                                       # prostopadle do scianki
            Mi = mx / 2 + H * (Z_AXLE - Z_BOLT)              # moment wokol X na srubach
            m5 = max(((V / 2 + k * Mi / s_b) ** 2 + (H / 2) ** 2) ** 0.5 for k in (1, -1))
            lw = Z_FLANGE - Z_BOLT
            sig = (6 * abs(N) * lw / (b_web * t * t)
                   + 6 * (abs(Mi) + abs(H) * lw) / (t * b_web * b_web))
            rows.append((m5, sig, N, H, V, Mi))
    return rows


def v0_flange_bolt(N, H, V, Mi, y_bolts):
    """One M6 in the bottom slot: prying about the flange edges, conservative."""
    yb = sum(y_bolts) / 2
    yf = P["main_beam_y"]
    mbx = Mi + (yb - yf) * V - (Z_BOLT - Z_FLANGE) * H
    mby = (Z_BOLT - Z_FLANGE) * N
    a_y = min(yf - Y_BEAM_IN, Y_BEAM_OUT - yf)
    a_x = V0_FLANGE / 2
    return max(0.0, -V) + abs(mbx) / a_y + abs(mby) / a_x


def v2_beam_bolts(F, M):
    """Leg on the beam's inner face, M6 in its lower slot (as drawn), plate
    under the beam. Roll moment about the outer bottom edge, taken by the leg
    bolts in shear; the My / Mz couples spread elastically, x_max / sum(x^2)."""
    fx, fy, fz = F
    mx, my, mz = M
    xs = P["hanger_leg_bolts_x"]
    y_leg = Y_BEAM_IN - P["hanger_t"] / 2
    q = ((P["wheel_y"] - Y_BEAM_OUT) * fz + Z_FLANGE * fy) / (Y_BEAM_OUT - y_leg)
    k = max(abs(x) for x in xs) / sum(x * x for x in xs)
    shear = abs(q) / len(xs) + abs(my) * k
    pull = abs(fy) / len(xs) + abs(mz) * k       # fx: tarcie plyty i nogi
    return shear, pull, q


def main():
    # the lever arithmetic: a pure vertical load must give Mx = Fz * lever
    assert abs(seat_load(0, 0, 100.0)[1][0] - 100.0 * R_CONTACT[1]) < 1e-9

    f_stat, cases = wheel_cases()
    v0_bolts = [V0_Y0 + 8, P["seat_y1"] - 8]
    v2_bolts = [P["hanger_y0"] + 8, P["seat_y1"] - 8]      # jak narysowane

    print("=" * 78)
    print("  UCHWYT KOLA - WIESZAKI: sruby, scianka, polaczenie z belka")
    print("=" * 78)
    print(f"  kolo {P['wheel_y'] - Y_SEAT:.0f} mm poza srodkiem gniazda, os {Z_AXLE:.0f} nad"
          f" podloga; wieszaki {P['hanger_t']:.0f} mm, X +/-{X_HANGER:.1f}")
    print(f"  nacisk blizszego kola, ramie w bok, caly robot na napedzie: {f_stat:.0f} N")
    print(f"  ZALOZENIA: prog x{K_DYN}, tarcie {dyn.MU}, nakretka w rowku {TNUT_N:.0f} N"
          f" [VERIFY], M5 scinanie {M5_SHEAR_N:.0f} N, scianka {SIG_ALLOW:.0f} MPa")

    print()
    print("  V0 - PIERWSZA WERSJA (do porownania): stopka na 1 x M6 w dolnym rowku, M5 co"
          f" {v0_bolts[1] - v0_bolts[0]:.0f} mm")
    print(f"  {'przypadek':<22}{'Fz':>6}{'Mx':>8}{'M5 scin.':>10}{'M6 wyrw.':>10}{'scianka':>9}")
    print(f"  {'':<22}{'N':>6}{'N*m':>8}{'N':>10}{'N':>10}{'MPa':>9}")
    v0_m5 = v0_t = v0_sig = 0.0
    for name, fx, fy, fz in cases:
        F, M = seat_load(fx, fy, fz)
        rows = hangers(F, M, v0_bolts)
        m5 = max(r[0] for r in rows)
        sig = max(r[1] for r in rows)
        t = max(v0_flange_bolt(*r[2:], v0_bolts) for r in rows)
        v0_m5, v0_t, v0_sig = max(v0_m5, m5), max(v0_t, t), max(v0_sig, sig)
        print(f"  {name:<22}{fz:>6.0f}{M[0] / 1000:>8.1f}{m5:>10.0f}{t:>10.0f}{sig:>9.0f}")

    print()
    print(f"  V2 - JAK NARYSOWANE: noga na wewn. licu belki, {len(P['hanger_leg_bolts_x'])} x M6"
          f" w jego dolnym rowku, plyta pod")
    print(f"  cala belka, scianki od Y {P['hanger_y0']:.0f}, para M5 co"
          f" {v2_bolts[1] - v2_bolts[0]:.0f} mm")
    print(f"  {'przypadek':<22}{'M5 scin.':>10}{'M6 scin.':>10}{'M6 wyrw.':>10}{'scianka':>9}")
    v2_m5 = v2_sh = v2_pull = v2_sig = 0.0
    for name, fx, fy, fz in cases:
        F, M = seat_load(fx, fy, fz)
        rows = hangers(F, M, v2_bolts)
        m5, sig = max(r[0] for r in rows), max(r[1] for r in rows)
        sh, pull, q = v2_beam_bolts(F, M)
        v2_m5, v2_sh = max(v2_m5, m5), max(v2_sh, sh)
        v2_pull, v2_sig = max(v2_pull, pull), max(v2_sig, sig)
        print(f"  {name:<22}{m5:>10.0f}{sh:>10.0f}{pull:>10.0f}{sig:>9.0f}")
    slip = M6_PRELOAD_N * MU_JOINT

    print()
    print("=" * 78)
    print("  WERDYKT")
    print("=" * 78)

    def line(label, val, lim, unit="N"):
        ok = "OK" if val <= lim else f"ZA DUZO x{val / lim:.1f}"
        print(f"    {label:<44}{val:>7.0f} / {lim:<6.0f}{unit:<4}{ok}")

    print("  V0, pierwsza wersja:")
    line("M6 stopki - wyrwanie nakretki z rowka", v0_t, TNUT_N)
    line("para M5 gniazdo-wieszak - scinanie", v0_m5, M5_SHEAR_N)
    line("scianka - zginanie", v0_sig, SIG_ALLOW, "MPa")
    print("  V2, jak narysowane:")
    line("M6 w licu - scinanie (bez poslizgu na tarciu)", v2_sh, slip)
    line("M6 w licu - wyrwanie", v2_pull, TNUT_N)
    line("para M5 gniazdo-wieszak - scinanie", v2_m5, M5_SHEAR_N)
    line("scianka - zginanie", v2_sig, SIG_ALLOW, "MPa")
    print()
    print("  Scianki z blachy 6 mm wytrzymuja z zapasem w obu wersjach - slabe")
    print("  byly polaczenia. W V0 jedna M6 w dolnym rowku trzymala moment kola na")
    print("  ramieniu ~20 mm i wyrywala nakretke. V2 oddaje ten moment parze:")
    print("  docisk zewnetrznej krawedzi plyty + sruby nogi na scinanie, ~43 mm.")
    assert v2_sh <= slip and v2_pull <= TNUT_N and v2_m5 <= M5_SHEAR_N,         "narysowany wieszak nie przechodzi wlasnych kryteriow"
    assert v2_sig <= SIG_ALLOW
    return v0_t, v0_m5, v2_sh, v2_pull, v2_m5


if __name__ == "__main__":
    main()
