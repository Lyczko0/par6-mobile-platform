#!/usr/bin/env python3
"""Uchwyt kola napedowego - czy siodlo zacisku przeniesie moment.

    python mobile_base/wheel_mount.py

DLACZEGO
  Lyczko0 zdecydowal 2026-09-12, ze przejmujemy oryginalne rozwiazanie
  hoverboarda: os lezy w pol-okraglym gniezdzie, a dociska ja stalowy
  strzemien na 4 sruby. Nasza czesc to gniazdo + 4 gwinty + interfejs
  do ramy. To zdejmuje z nas najtrudniejszy element, ale przenosi
  pytanie w jedno miejsce: CZYM ten styk reaguje moment napedowy.

  Os jest okragla. Okragly walek w zacisku ciernym to dokladnie ten sam
  problem, ktory wyszedl przy dzwigni pomiarowej - tylko tutaj moment
  jest o rzad wielkosci wiekszy. Jesli os ma splaszczenie, gniazdo MUSI
  je lapac i problem znika. Jesli nie ma, wszystko wisi na naciagu srub.

CZEGO NIE LICZY
  Momentu postojowego silnika - to jest liczba niezmierzona i wlasnie
  ona, a nie trakcja, jest przypadkiem projektowym przy zablokowanym kole.
  Zginania samego strzemienia - bez grubosci i szerokosci blachy nie ma
  z czego liczyc.
  Zmeczenia. Robot startuje i hamuje tysiace razy; zacisk cierny, ktory
  raz przeslizgnie, przesliznie sie znowu.
"""

import math

# --- co wiemy -----------------------------------------------------------------
WHEEL_R      = 100.0     # mm, ZMIERZONE - opona 200 mm w poprzek
TRACTION_TOT = 237.0     # N, granica przyczepnosci obu kol, control/dynamics.py
MU_FLOOR     = 0.70      # przy tym policzone TRACTION_TOT              [VERIFY]

# --- os: z CAD, do potwierdzenia dwoma pomiarami suwmiarka -------------------
# mobile_base/ref/hoverboard_8in/*.stp - GrabCAD "Hoverboard Wheel, 8in, BLDC
# Motor" (John Frank, 2018, Inventor, mm), czytane 2026-10-07 wprost z encji
# STEP. Os: walec 16.00, JEDEN plask 5.00 od srodka na 42 mm, otwor 7.5 na
# przewody, faza 1 mm na koncu. 13.3 z suwmiarki (2026-09) to wymiar przez
# plask, rowek 14.6-15.8 to gniazdo pod 16.
# ALE: w tym kole opona ma ~47 mm, u Lyczko0 82.2, a przed plaskiem jest
# 4 mm walca, u niego na zdjeciach ~30. Inny wariant - przekroj osi pewnie
# ten sam, DLUGOSCI NIE.
# Suwmiarka 2026-10-07: 15.8 i 13.3 wobec 16.0 i 13.0 - zgodne w granicach
# tego pomiaru. Rozjazd 0.2-0.3 nie gra roli, bo kopiujemy GLEBOKOSC rowka
# oryginalu i bierzemy oryginalne strzemie: zacisk wyznaczaja oryginalne
# czesci, nie te liczby. Rowek pod wieksza z nich (16), wtedy pasuje kazda.
AXLE_D       = 16.0      # mm, CAD; suwmiarka 15.8
AXLE_FLAT    = 13.0      # od plaska do przeciwnej strony, CAD; suwmiarka 13.3
FLAT_LEN     = 42.0      # mm, CAD - gniazdo 38.8-40 miesci sie na nim
AXLE_BORE    = 7.5       # mm, CAD, przewody
FLAT_W = 2 * math.sqrt((AXLE_D / 2) ** 2 - (AXLE_FLAT - AXLE_D / 2) ** 2)   # 12.5
# Zdjecia 2026-10-07: os ma JEDEN plask, na gorze, frezowany na calej dlugosci
# gniazda; przed gniazdem stopien (wiekszy walek), przewody wychodza z czola.
# Rowek w odlewie POLOKRAGLY. Strzemie to gieta omega z plaskim dnem, ktore
# dociska plask osi - moment trzyma KSZTALT, wariant B ponizej.
# CAD: GrabCAD "Hoverboard Wheel, 8in, BLDC Motor" (John Frank, 2018, STEP),
# tylko obrys zewnetrzny. Sprawdzic dwoma pomiarami (os i plask), zanim
# zastapi suwmiarke - inne silniki 8" maja inne osie. Odlewu ani strzemienia
# tam nie ma.

# --- gniazdo w odlewie ramy (XY-13), zdjecia Lyczko0 2026-10-05 --------------
# Koncowki szczek luzno w otworach: rozstawy +/-1 mm, sruby strzemienia chca
# +/-0.3 - powtorzyc metoda krawedzi (scisnac do blizszych + srednica).
HOLE_PITCH_ALONG  = 22.9   # wzdluz osi; 23.4 z 2026-09 to ta sama para
HOLE_PITCH_ACROSS = 29.5   # w poprzek osi, miedzy podkladkami
SEAT_GROOVE_W     = 15.8   # rowek na gorze podkladek; 14.6 w innym miejscu (10-07)
SEAT_BLOCK        = (38.8, 47.7)   # blok gniazda: wzdluz x w poprzek; wzdluz 40.0 (10-07)
# Przewody silnika wychodza przez wydrazona os - przepust za koncem osi.

# --- czego nie wiemy ----------------------------------------------------------
STALL_MULT   = 3.0       # ile razy moment postojowy > trakcyjny      [MEASURE]
PLATE_T      = 10.0      # mm, grubosc naszej plyty (BOM 4.1)
MU_CLAMP     = 0.15      # stal - aluminium, lekko zaolejone          [VERIFY]
SIG_AL_BEAR  = 80.0      # MPa, dopuszczalny docisk na 6082/6061      [VERIFY]

# --- kwalifikacja przez eksploatacje (argument Lyczko0, 2026-09-16) ---------
# Ten sam zacisk nosil w hoverboardzie czlowieka. Jesli jego codzienna praca
# jest ciezsza niz nasza, to zlacze jest juz sprawdzone - pod warunkiem, ze
# kopiujemy je wiernie. Te liczby sa z opisu produktu, nie z pomiaru.
HB_RIDER_KG  = 120.0     # dopuszczalny jezdziec                         [VERIFY]
HB_BOARD_KG  = 12.0      # sam hoverboard                         [MEASURE waga]
HB_SLOPES    = (10.0, 15.0)   # typowy deklarowany podjazd, stopnie      [VERIFY]
OUR_WHEELS_KG = 35.5     # na obu kolach napedowych, control/dynamics.py

# sruba: (nazwa, d, pole rdzenia mm2, granica plastycznosci MPa)
BOLTS = [
    ("M5 8.8",  5.0, 14.2, 640.0),
    ("M5 12.9", 5.0, 14.2, 1100.0),
    ("M6 8.8",  6.0, 20.1, 640.0),
    ("M6 12.9", 6.0, 20.1, 1100.0),
]
PRELOAD_FRAC = 0.65      # typowy naciag montazowy jako czesc granicy


def main():
    print("=" * 74)
    print("  UCHWYT KOLA NAPEDOWEGO - SIODLO NA OSI PIASTY")
    print("=" * 74)

    t_trac = TRACTION_TOT / 2.0 * WHEEL_R / 1000.0
    t_stall = t_trac * STALL_MULT
    print(f"  Sila napedowa obu kol (granica przyczepnosci, mu={MU_FLOOR:.2f})"
          f"   {TRACTION_TOT:.0f} N")
    print(f"  Na jedno kolo                                          "
          f"      {TRACTION_TOT/2:.0f} N")
    print(f"  MOMENT NA JEDNEJ OSI, przypadek trakcyjny              "
          f"     {t_trac:5.2f} N*m")
    print(f"  Przypadek zablokowanego kola (x{STALL_MULT:.0f} - ZGADYWANE)"
          f"        {t_stall:5.2f} N*m   [MEASURE]")
    print()
    print("  Trakcja to przypadek, w ktorym kolo moze sie obracac. Przy kole")
    print("  zablokowanym o prog lub sciane ograniczeniem jest moment")
    print("  postojowy silnika, a ten jest NIEZMIERZONY. Dlatego ponizej")
    print("  licze oba i patrze, ktory jeszcze przechodzi.")

    # --- wariant A: gniazdo pol-okragle, tylko tarcie -------------------------
    r = AXLE_D / 2000.0                      # m
    print()
    print("  " + "=" * 70)
    print("  A. GNIAZDO POL-OKRAGLE - moment trzyma TYLKO tarcie")
    print("  " + "=" * 70)
    print(f"  Os zacisnieta miedzy strzemieniem i gniazdem. Dwie powierzchnie")
    print(f"  cierne, promien {AXLE_D/2:.2f} mm, mu = {MU_CLAMP:.2f}.")
    print()
    print(f"  {'przypadek':<26}{'potrzebny docisk':>18}{'na 1 z 4 srub':>16}")
    for lab, t in (("trakcyjny", t_trac), ("zablokowane kolo", t_stall)):
        f_tot = t / (2.0 * MU_CLAMP * r)
        print(f"  {lab:<26}{f_tot:>15.0f} N{f_tot/4.0:>13.0f} N")
    print()
    print(f"  {'sruba':<12}{'naciag/szt':>12}{'lacznie 4x':>13}"
          f"{'trakcja':>10}{'blokada':>10}")
    for name, d, area, sy in BOLTS:
        f_b = PRELOAD_FRAC * sy * area
        f_tot = 4.0 * f_b
        cap = 2.0 * MU_CLAMP * f_tot * r
        print(f"  {name:<12}{f_b:>10.0f} N{f_tot:>11.0f} N"
              f"{cap/t_trac:>9.1f}x{cap/t_stall:>9.1f}x")
    print()
    print("  UWAGA NA TE LICZBY. Zakladaja, ze strzemien wytrzyma pelny")
    print("  naciag czterech srub bez rozgiecia - a to jest GIETA BLACHA,")
    print("  nie frezowana obejma. Bez jej grubosci i szerokosci nie da sie")
    print("  tego sprawdzic, a to ona, nie sruba, bedzie ograniczeniem.")

    # --- wariant B: gniazdo lapie splaszczenie -------------------------------
    print()
    print("  " + "=" * 70)
    print("  B. GNIAZDO LAPIE SPLASZCZENIE - moment trzyma KSZTALT")
    print("  " + "=" * 70)
    print("  Wtedy tarcie nie ma znaczenia, a pyta sie tylko o docisk")
    print(f"  na plaszczyznie. Dopuszczalne {SIG_AL_BEAR:.0f} MPa na aluminium.")
    print()
    print(f"  {'przypadek':<26}{'sila na plasku':>16}"
          f"{'potrzebna dlugosc styku':>26}")
    for lab, t in (("trakcyjny", t_trac), ("zablokowane kolo", t_stall)):
        # moment reagowany para sil na ramieniu ~ srednica osi
        f_flat = t / (AXLE_D / 1000.0)
        w_flat = FLAT_W                              # z CAD, nie zalozona
        l_need = f_flat / (SIG_AL_BEAR * w_flat)
        print(f"  {lab:<26}{f_flat:>13.0f} N{l_need:>23.1f} mm")
    print()
    print(f"  Szerokosc plaska {FLAT_W:.1f} mm z CAD (os {AXLE_D:.0f}, przez plask"
          f" {AXLE_FLAT:.0f}) [VERIFY suwmiarka].")
    print("  Kilka milimetrow styku wystarcza. To dlatego oryginal dziala")
    print("  na czterech malych srubach: one nie przenosza momentu, tylko")
    print("  TRZYMAJA OS W GNIEZDZIE. Moment bierze ksztalt.")

    # --- gwinty w naszej plycie ---------------------------------------------
    print()
    print("  " + "-" * 70)
    print(f"  GWINTY W NASZEJ PLYCIE {PLATE_T:.0f} mm (otwor nieprzelotowy)")
    print("  " + "-" * 70)
    print("  W aluminium chce sie minimum 1.5 x d zaczepu gwintu.")
    for name, d, _a, _s in BOLTS:
        if "8.8" not in name:
            continue
        eng = PLATE_T - 2.0            # 2 mm na dno i niepelny pierwszy zwoj
        need = 1.5 * d
        ok = "OK" if eng >= need else "ZA MALO - trzeba pogrubic albo przelot"
        print(f"    {name[:2]}   zaczep {eng:.0f} mm,"
              f" potrzeba {need:.1f} mm   {ok}")

    # --- kwalifikacja przez eksploatacje -----------------------------------
    print()
    print("  " + "=" * 70)
    print("  C. CZY ORYGINALNE ZLACZE JUZ TO WYTRZYMALO - hoverboard vs robot")
    print("  " + "=" * 70)
    m_hb = HB_RIDER_KG + HB_BOARD_KG
    f_hb = m_hb * 9.81 / 2.0
    f_us = OUR_WHEELS_KG * 9.81 / 2.0
    print(f"  {'':<34}{'hoverboard':>14}{'robot':>10}{'stosunek':>10}")
    print(f"  {'nacisk pionowy na jedna os':<34}{f_hb:>12.0f} N"
          f"{f_us:>8.0f} N{f_hb/f_us:>9.1f}x")
    for deg in HB_SLOPES:
        t_hb = m_hb * 9.81 * math.sin(math.radians(deg)) / 2.0 * WHEEL_R / 1000.0
        lab = f"moment na osi, podjazd {deg:.0f} st."
        print(f"  {lab:<34}{t_hb:>10.1f} N*m{t_trac:>6.1f} N*m"
              f"{t_hb/t_trac:>9.1f}x")
    print()
    print("  Hoverboard w zwyklej jezdzie pod gore obciaza ta os momentem")
    print("  rownym albo wiekszym od naszego przypadku trakcyjnego, a pionowo")
    print(f"  prawie {f_hb/f_us:.0f}x mocniej. Przypadek zablokowanego kola tez jest")
    print("  pokryty: to TEN SAM silnik, wiec najwiekszy moment, jaki moze")
    print("  wytworzyc, zlacze juz widzialo - o ile nie podniesiemy limitu")
    print("  pradu w firmware Gen2.x ponad fabryczny.")
    print()
    print("  WNIOSEK: zlacze jest skwalifikowane eksploatacja. Wytrzymalosci")
    print("  nie trzeba liczyc - trzeba je WIERNIE SKOPIOWAC. Kwalifikacja")
    print("  nalezy do oryginalnego gniazda + strzemienia + srub + naciagu,")
    print("  a nie do 'jakiegos pol-okraglego gniazda na 4 sruby'.")
    print("  Dlatego pomiary geometrii zostaja blokujace, a pomiary")
    print("  wytrzymalosciowe (grubosc strzemienia, moment postojowy) spadaja")
    print("  do informacyjnych.")

    # --- co zmierzyc --------------------------------------------------------
    print()
    print("  " + "=" * 70)
    print("  CO ZMIERZYC I CO KAZDA LICZBA ROZSTRZYGA")
    print("  " + "=" * 70)
    B, I = "BLOKUJE", "info"
    rows = [
        (I, "KONTROLA CAD - ZAMKNIETE 2026-10-07: 15.8 / 13.3",
         "zgodne z CAD w granicach suwmiarki, przekroj osi z CAD"),
        (B, f"dlugosc plaska u Lyczko0 (CAD {FLAT_LEN:.0f})",
         "gniazdo musi lezec na plasku na calej dlugosci"),
        (I, "ORIENTACJA plaska - ZAMKNIETE 2026-10-07",
         "plask do gory, pod plaskim dnem strzemienia"),
        (B, "rozstaw otworow WZDLUZ osi - metoda krawedzi",
         f"raster gwintow w plycie; jest {HOLE_PITCH_ALONG} +/-1, trzeba +/-0.3"),
        (B, "rozstaw otworow W POPRZEK osi - metoda krawedzi",
         f"to samo; jest {HOLE_PITCH_ACROSS} +/-1"),
        (B, "gwint i dlugosc oryginalnych srub, otwory w strzemieniu",
         "rozmiar sruby - M5 wchodzi w plyte 10 mm, M6 na styk"),
        (B, "SZCZELINA stopka strzemienia - podkladka: os w gniezdzie, bez srub",
         "docisk oryginalnego zacisku - nasze gniazdo ma dac te sama"),
        (B, "GLEBOKOSC rowka w oryginalnym odlewie",
         "druga polowa. Obie MUSZA sie zlozyc na srednice osi - glebsze "
         "gniazdo = strzemien nie dociska, plytsze = nie dokrecisz do lica"),
        (B, "dlugosc osi od lica silnika do konca",
         "ile mamy do uchwycenia i gdzie moze stac gniazdo"),
        (B, "czy os ma stopien - srednica przy piascie",
         "gniazdo moze potrzebowac podtoczenia"),
        (B, "szerokosc obudowy silnika wzdluz osi",
         "srodek opony wzgledem lica - rozstaw kol i szerokosc oslon"),
        (B, "ile przewody wystaja z konca osi, wtyczka, promien giecia",
         "przepust za koncem osi (wychodza przez os - 2026-10-05)"),
        (I, "MASA jednej piasty",
         "ostatni przedzial w budzecie mas [2.4 - 3.6] kg"),
        (I, "GRUBOSC i szerokosc blachy strzemienia",
         "po sekcji C juz nie limit - tylko do dokumentacji"),
        (I, "moment postojowy / prad przy zablokowanym kole",
         "po sekcji C pokryty eksploatacja - byle nie podnosic limitu pradu"),
    ]
    for i, (lvl, what, why) in enumerate(rows, 1):
        print(f"  {i:>2}. [{lvl:<7}] {what}")
        print(f"               -> {why}")


if __name__ == "__main__":
    main()
