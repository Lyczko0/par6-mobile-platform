#!/usr/bin/env python3
"""Which metal parts can become 3D prints - computed, not guessed.

    python mobile_base/print_vs_metal.py

The owner has a Kobra S1 and no easy access to a machine shop, so every part
that can be printed instead of ordered is a part that stops costing money and
lead time. The question is which ones the maths allows.

THREE THINGS DECIDE IT, and only the first is obvious:

1. STRENGTH. Printed PETG reaches maybe 40 MPa in the print plane but only
   about half that across layers, and a printed part is loaded across layers
   more often than you would like. Design allowable here: 7 MPa static.

2. STIFFNESS. PETG is about 1.8 GPa against 70 GPa for aluminium - roughly
   40x softer. A part that only has to hold something in place does not care.
   A part in the stiffness path of the arm cares enormously.

3. CREEP, and this is the one that catches people. Plastic under CONSTANT
   load keeps deforming for months. A bracket that passes a static stress
   check can still sag 2 mm over a year. Anything holding a permanent load
   gets a much lower allowable: 3 MPa.

So a part qualifies for printing when it is (a) below the allowable, (b) not
in a stiffness path that matters, and (c) not a safety device that eats an
impact.
"""
import re
from pathlib import Path

E_PETG = 1800.0          # MPa
SIG_STATIC = 7.0         # MPa, design allowable for occasional load
SIG_CREEP = 3.0          # MPa, design allowable for permanent load
E_AL = 70000.0
G = 9.81

# ROZPIETOSC to odleglosc miedzy PODPORAMI, nie dlugosc czesci. Plyty leza
# na obu belkach glownych, czyli swiatlo 235 mm - nie 300. Obciazenie jest
# ROZLOZONE (M = wL^2/8), nie punktowe posrodku (M = FL/4). Pierwsza wersja
# tego skryptu liczyla punktowo na pelnej dlugosci i odrzucala czesci, ktore
# spokojnie sie drukuje.
BEAM_GAP = 235.0     # swiatlo miedzy licami belek glownych

# (name, span_mm, width_mm, thickness_mm, load_kg, permanent, distributed, note)
CANDIDATES = [
    ("plyta elektroniki", BEAM_GAP, 140, 6, 4.3, True, True,
     "niesie skrzynki, zero roli konstrukcyjnej, lezy na obu belkach"),
    # = end_plate() in base_components.scad: 10 mm, between the beams. It
    # stood here as 250 x 80 x 5 for weeks after the plate was redrawn.
    ("plyta koncowa ramy", BEAM_GAP, 80, 10, 2.0, False, True,
     "zamyka przekroj na skrecanie, obciazenie posrednie"),
    ("taca baterii 4 mm", BEAM_GAP, 110, 4, 3.0, True, True,
     "3 kg wisi na niej caly czas - creep jest tu glownym pytaniem"),
    ("taca baterii 5 mm", BEAM_GAP, 110, 5, 3.0, True, True,
     "to samo o milimetr grubsze"),
    ("wspornik krancowki", 58, 24, 3, 0.2, False, True,
     "trzyma krancowke, zero obciazenia"),
    ("wspornik anti-tip", 80, 60, 6, 25.0, False, False,
     "pochlania UDERZENIE przy przechyle - urzadzenie bezpieczenstwa"),
]

# Parts that stay metal no matter what, with the reason.
STAY_METAL = [
    ("profile ramy i kolumny", "sztywnosc calej konstrukcji"),
    ("plyta spinajaca kolumny", "to ona robi z dwoch profili rame - 40x mniej"
                                " sztywnosci kasuje wynik 36 Hz"),
    ("plyta bazowa kolumny", "caly moment wywracajacy ramienia"),
    ("plyta ruchoma wozka", "nosi ramie, plus gwinty M6 na slepo"),
    ("wspornik nakretki", "115 N na wysiegu 80 mm PRZEZ CALY CZAS - creep"
                          " opuszczalby os Z z miesiaca na miesiac"),
    ("uchwyt kola napedowego", "cwierc masy robota + moment napedowy + udary"),
    ("uchwyt castera", "cwierc masy robota. Sam nacisk na sruby to ~1 MPa,"
                       " wiec plastik by to udzwignal - ale ta czesc ma dopiero"
                       " dostac PODATNOSC PIONOWA (warunek 1 wariantu A),"
                       " ktorej nie ma. Decyzja o materiale razem z ta konstrukcja"),
    ("adapter PAR6", "ramie na wysiegu 130 mm, 15.9 Nm"),
]


# Panel G (gorny, druk 3 mm) pod E-stopem - Lyczko0 2026-10-17: "jesli wydruk
# da rade, to wydruk". E-stop stoi na nawisie panelu ZA zewnetrznym licem belki,
# wiec to wspornik od lica belki, nie plyta na dwoch podporach. Szerokosc
# wspolpracujaca ~60 mm: kolnierz E-stopu ~40 plus po dzwigni z obu stron.
ESTOP_LOADS_N = [("wcisniecie", 30.0), ("uderzenie piescia", 100.0)]
ESTOP_WIDTH = 60.0


def estop_lever():
    """mm from the beam's outer face to the E-stop axis, and the wall, from
    base_parameters.scad - not copied, the E-stop has moved before."""
    src = (Path(__file__).parent / "base_parameters.scad").read_text(encoding="utf-8")
    num = lambda n: float(re.search(rf"(?m)^{n}\s*=\s*([-\d.]+)", src).group(1))
    y = float(re.search(r"estop_pos\s*=\s*\[[^,]*,\s*([-\d.]+)\]", src).group(1))
    return y - (num("main_beam_y") + num("profile_main_w") / 2), num("cover_thk")


def bend(span, width, t, load_n, e_mod, distributed=True):
    """Simply supported plate. Distributed load unless told otherwise."""
    i = width * t ** 3 / 12.0
    z = width * t ** 2 / 6.0
    if distributed:
        m = load_n * span / 8.0
        d = 5.0 * load_n * span ** 3 / (384.0 * e_mod * i)
    else:
        m = load_n * span / 4.0
        d = load_n * span ** 3 / (48.0 * e_mod * i)
    return m / z, d


def main():
    print("=" * 78)
    print("  DRUK ZAMIAST METALU - co pozwala matematyka")
    print("=" * 78)
    print(f"  PETG: E = {E_PETG:.0f} MPa, dopuszczalne {SIG_STATIC:.0f} MPa"
          f" dorywczo / {SIG_CREEP:.0f} MPa na stale")
    print(f"  Aluminium dla porownania: E = {E_AL:.0f} MPa\n")

    print(f"  {'czesc':<22}{'napr.':>8}{'dopusz.':>9}{'ugiecie':>10}"
          f"{'to samo w Al':>13}   werdykt")
    verdicts = []
    for name, span, width, t, kg_load, permanent, dist, note in CANDIDATES:
        f = kg_load * G
        sig, d = bend(span, width, t, f, E_PETG, dist)
        _, d_al = bend(span, width, t, f, E_AL, dist)
        allow = SIG_CREEP if permanent else SIG_STATIC
        ok = sig <= allow
        tag = "DRUK" if ok else "METAL"
        verdicts.append((name, tag, sig, allow, d, note))
        print(f"  {name:<22}{sig:>7.1f}{allow:>9.0f}{d:>9.2f}mm"
              f"{d_al:>12.3f}mm   {tag}")

    print()
    print("=" * 78)
    print("  CO IDZIE NA DRUK")
    print("=" * 78)
    for name, tag, sig, allow, d, note in verdicts:
        if tag == "DRUK":
            print(f"  {name}")
            print(f"    {note}")
            print(f"    {sig:.1f} MPa przy dopuszczalnych {allow:.0f},"
                  f" ugiecie {d:.2f} mm")

    print()
    print("=" * 78)
    print("  CO ZOSTAJE METALEM")
    print("=" * 78)
    for name, tag, sig, allow, d, note in verdicts:
        if tag == "METAL":
            print(f"  {name}  -  {sig:.0f} MPa przy dopuszczalnych {allow:.0f}")
            print(f"    {note}")
    for name, why in STAY_METAL:
        print(f"  {name}")
        print(f"    {why}")

    lever, t = estop_lever()
    i, z = ESTOP_WIDTH * t ** 3 / 12.0, ESTOP_WIDTH * t ** 2 / 6.0
    print()
    print("=" * 78)
    print(f"  PANEL G Z DRUKU POD E-STOPEM - wspornik {lever:.1f} mm od lica belki, {t:.0f} mm")
    print("=" * 78)
    worst = 0.0
    for what, f in ESTOP_LOADS_N:
        sig = f * lever / z
        worst = max(worst, sig)
        print(f"  {what:<20}{f:>5.0f} N   {sig:>5.1f} MPa przy dopuszczalnych"
              f" {SIG_STATIC:.0f}   ugiecie {f * lever ** 3 / (3 * E_PETG * i):.2f} mm")
    print("  -> " + ("panel wystarczy." if worst <= SIG_STATIC else
                     "E-stop na WLASNYM wsporniku przykreconym do belki, panel tylko z"
                     " otworem.\n     Sam druk peknie od uderzenia - a E-stop jest od"
                     " uderzania."))

    print()
    print("=" * 78)
    print("  ZASTRZEZENIA, bez ktorych to nie jest uczciwy wynik")
    print("=" * 78)
    print("   1. Liczone jako PLYTA PELNA, swobodnie podparta na dwoch belkach")
    print("      glownych (swiatlo 235 mm), obciazenie ROZLOZONE. Realna czesc")
    print("      drukowana ma zebra i jest przykrecona w kilku punktach, wiec")
    print("      wypadnie LEPIEJ niz tu. Pierwsza wersja tego skryptu liczyla")
    print("      obciazenie punktowo na pelnej dlugosci czesci i przez to")
    print("      odrzucala plyty, ktore spokojnie sie drukuje.")
    print("   2. Wytrzymalosc PETG zalezy od wydruku bardziej niz od materialu.")
    print("      40 MPa to dobry wydruk; zly potrafi dac 15. Sciany >= 4 linie,")
    print("      wypelnienie >= 40 %, warstwy prostopadle do naprezenia.")
    print("   3. SRUBY W PLASTIKU: zawsze wkladki gwintowane albo podkladki")
    print("      pod lbem. Sruba dokrecona wprost w PETG wgniata sie i luzuje.")
    print("   4. Nie liczone: zmeczenie od drgan jazdy, UV, temperatura.")
    print("      Do wnetrza robota PETG wystarczy; ASA jesli cos ma widziec")
    print("      slonce albo ciepło od sterownikow.")


if __name__ == "__main__":
    main()
