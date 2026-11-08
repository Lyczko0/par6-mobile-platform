#!/usr/bin/env python3
"""Sciezki obciazenia - czy elementy nosne w ogole sie zgadzaja.

    python control/load_paths.py

DLACZEGO TEN PLIK ISTNIEJE
  Do 2026-08-19 policzone byly trzy rzeczy: sztywnosc kregoslupa, stabilnosc
  i pelzanie wydrukow. Reszta lancucha nosnego - wozki prowadnic, belki ramy,
  plyta ruchoma, sruba - nie miala ZADNEJ liczby. Nie dlatego, ze sa slabe;
  dlatego, ze nikt nie sprawdzil.

CO JEST LICZONE
  1. HGH20CA - moment od ramienia rozlozony na cztery wozki
  2. belki glowne 40x80 - ugiecie i naprezenie pod cala masa robota
  3. plyta ruchoma 440x220x10 - zginanie od momentu ramienia
  4. sruba SFU1605 - wyboczenie i predkosc krytyczna
  5. adapter PAR6 - polka z zebrami, przekroj zmienny, calkowana
  6. plyta ruchoma z ramieniem wysunietym w bok
  7. katowniki na stykach ramy
  8. castery D125 - obciazenie i spec na podatny uchwyt

CZEGO NIE LICZY  (i to jest wazniejsze niz to, co liczy)
  Dynamiki - to jest w dynamics.py, od 2026-08-19.
  Nic o poslizgu w polaczeniach srubowych ani o luzowaniu sie pod drganiami.
  Ukladu DWURAMIENNEGO - przy jednym ramieniu w osi plyty skrecania nie ma,
  przy dwoch nierowno obciazonych pojawia sie i trzeba to zrobic od nowa.
  Charakterystyki moment-obroty silnika - patrz z_drive.py.
  Zadnej z tych rzeczy nie da sie policzyc bez danych, ktorych nie mamy.
"""

import math
import os
import sys

G = 9.81

# --- geometria, z modelu --------------------------------------------------
# 2026-08-19: ZWAZONE. Bylo 3.4 + 1.052 (ramie + chwytak + obiekt),
# jest 6.6 kg samo ramie z chwytakiem plus 0.5 obiektu. +67 % na koncu
# najdluzszej dzwigni w maszynie.
ARM_KG        = 6.6 + 0.5        # ZWAZONE ramie + obiekt
ADAPTER_KG    = 1.67             # P2, asserted by par6_ref/adapter_stiffness.py
CARRIAGE_KG   = 2.777 + 0.639 + 1.400 + ADAPTER_KG  # nakretka gieta, nie blok 1.14
ROBOT_KG      = 47.4             # dolny kraniec przedzialu, bez ramienia

Y_RAIL        = 80.0             # lico montazu prowadnic
Y_ARM_LOAD    = 601.0            # punkt przylozenia ciezaru ramienia
Y_CARR_CG     = 110.0            # srodek ciezkosci wozka
BLK_PITCH     = 120.0            # rozstaw wozkow wzdluz prowadnicy
N_RAIL        = 2

PLATE         = (440.0, 220.0, 10.0)
BEAM_SPAN     = 240.0            # najwiekszy odstep podpor belki glownej
BEAM_LEN      = 600.0
N_BEAM        = 2

SCREW_FREE_L  = 760.0            # BK12 .. BF12
SCREW_ROOT_D  = 13.5             # SFU1605 srednica rdzenia          [VERIFY]
SCREW_LEAD    = 5.0

E_AL          = 68_600.0         # 6063-T5, z karty profilu
E_STEEL       = 210_000.0
SIG_AL        = 127.0            # granica plastycznosci 6063-T5
E_AL_6082     = 70_000.0         # plyty i adapter

# Katalogowe, do podstawienia realnymi                              [VERIFY]
HGH20_C0      = 30_000.0         # nosnosc statyczna wozka, N
PROF_I_STRONG = 788_000.0        # Ix profilu 40x80
PROF_W_STRONG = 17_400.0         # Wx


def line(t):
    print()
    print("  " + "-" * 68)
    print("  " + t)
    print("  " + "-" * 68)


def verdict(margin, warn=3.0):
    return "OK" if margin >= warn else ("GRANICA" if margin >= 1.5 else "ZA SLABE")


def main():
    print("=" * 72)
    print("  SCIEZKI OBCIAZENIA - Mobile Manipulator V1")
    print("=" * 72)

    # --- 1. wozki prowadnic ----------------------------------------------
    m_arm  = ARM_KG * G * (Y_ARM_LOAD - Y_RAIL) / 1000.0
    m_carr = CARRIAGE_KG * G * (Y_CARR_CG - Y_RAIL) / 1000.0
    m_tot  = m_arm + m_carr
    # Moment rozklada sie na dwie prowadnice, a na kazdej para wozkow tworzy
    # pare sil na ramieniu BLK_PITCH. Wozek gorny ciagnie, dolny pcha.
    f_blk  = (m_tot / N_RAIL) * 1000.0 / BLK_PITCH
    f_vert = (ARM_KG + CARRIAGE_KG) * G / (N_RAIL * 2)
    line("1. WOZKI HGH20CA - moment od wysunietego ramienia")
    print(f"  moment od ramienia         {m_arm:8.1f} N*m  (ramie "
          f"{(Y_ARM_LOAD - Y_RAIL):.0f} mm od lica prowadnic)")
    print(f"  moment od wozka            {m_carr:8.1f} N*m")
    print(f"  RAZEM                      {m_tot:8.1f} N*m")
    print(f"  sila na wozek, od momentu  {f_blk:8.0f} N")
    print(f"  sila na wozek, pionowa     {f_vert:8.0f} N")
    res = math.hypot(f_blk, f_vert)
    print(f"  wypadkowa                  {res:8.0f} N   wobec C0 = "
          f"{HGH20_C0:.0f} N  ->  zapas {HGH20_C0/res:.0f}x  {verdict(HGH20_C0/res)}")
    print("  Uwaga: to zapas STATYCZNY. Katalogowy moment dopuszczalny")
    print("  pojedynczego wozka nie jest tu sprawdzony - para wozkow na")
    print("  prowadnicy przenosi moment jako pare sil, wiec nie powinien byc")
    print("  wiazacy, ale to zalozenie, nie wynik.")

    # --- 2. belki glowne --------------------------------------------------
    w = ROBOT_KG * G / N_BEAM / BEAM_LEN           # N/mm na belke
    m_beam = w * BEAM_SPAN ** 2 / 8.0
    sig_beam = m_beam / PROF_W_STRONG
    d_beam = 5 * w * BEAM_SPAN ** 4 / (384 * E_AL * PROF_I_STRONG)
    line("2. BELKI GLOWNE 40x80 - cala masa robota")
    print(f"  obciazenie ciagle          {w:8.3f} N/mm na belke")
    print(f"  moment, przeslo {BEAM_SPAN:.0f} mm     {m_beam/1000:8.2f} N*m")
    print(f"  naprezenie                 {sig_beam:8.2f} MPa  wobec {SIG_AL:.0f} "
          f"->  zapas {SIG_AL/sig_beam:.0f}x  {verdict(SIG_AL/sig_beam)}")
    print(f"  ugiecie                    {d_beam:8.4f} mm")

    # --- 3. plyta ruchoma -------------------------------------------------
    pw, ph, pt = PLATE
    w_plate = pw * pt ** 2 / 6.0
    sig_plate = m_tot * 1000.0 / w_plate
    line("3. PLYTA RUCHOMA 440 x 220 x 10 - moment ramienia do wozkow")
    print(f"  wskaznik zginania          {w_plate:8.0f} mm3")
    print(f"  naprezenie                 {sig_plate:8.2f} MPa  wobec 250 (6082-T6)"
          f"  ->  zapas {250/sig_plate:.0f}x  {verdict(250/sig_plate)}")
    for t in (8.0, 6.0):
        wt = pw * t ** 2 / 6.0
        print(f"    gdyby {t:.0f} mm:            {m_tot*1000/wt:8.2f} MPa"
              f"   zapas {250/(m_tot*1000/wt):.0f}x")
    print("  To jest sam moment do przodu. Przypadek boczny w punkcie 6.")

    # --- 4. sruba ---------------------------------------------------------
    f_ax = (ARM_KG + CARRIAGE_KG) * G
    i_screw = math.pi * SCREW_ROOT_D ** 4 / 64.0
    p_cr = 2.046 * math.pi ** 2 * E_STEEL * i_screw / SCREW_FREE_L ** 2
    n_cr = 15.1 * SCREW_ROOT_D / SCREW_FREE_L ** 2 * 1e7
    v_cr = n_cr * SCREW_LEAD / 60.0
    line("4. SRUBA SFU1605 - wyboczenie i predkosc krytyczna")
    print(f"  obciazenie osiowe          {f_ax:8.0f} N")
    print(f"  sila krytyczna Eulera      {p_cr:8.0f} N  (utwierdzona-podparta, "
          f"{SCREW_FREE_L:.0f} mm)")
    print(f"                             ->  zapas {p_cr/f_ax:.0f}x  "
          f"{verdict(p_cr/f_ax)}")
    print(f"  predkosc krytyczna         {n_cr:8.0f} obr/min  = {v_cr:.0f} mm/s")

    # --- 5. adapter PAR6 --------------------------------------------------
    # One model of the adapter: par6_ref/adapter_stiffness.py (P2, bent sheet
    # since 2026-09-25). The inline copy that lived here counted the old
    # gusset's full 63 mm as rib - 10 of them overlapped the 10 mm shelf - and
    # so reported 0.092 mm for an adapter that gave 0.123.
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    "..", "par6_ref"))
    import adapter_stiffness as ad
    d = ad.DESIGN
    tip, f_pitch, sig_root = ad.evaluate(d["t"], d["tg"], d["h"], False,
                                         d["rib_l"], True, d["w"])
    line("5. ADAPTER PAR6 - katownik giety 6 mm + 2 zebra przez cala polke")
    print(f"  moment wlasny ramienia     {ad.M_BASE:8.1f} N*m  (CG {ad.ARM_CG_R:.0f} mm,"
          f" chwyt na {ad.ARM_REACH:.0f})")
    print(f"  moment u nasady polki      {ad.M_ROOT:8.1f} N*m")
    print(f"  BLAD NA CHWYTAKU           {tip:8.3f} mm   (kat x zasieg + ugiecie)")
    print(f"  postac ramienia na adapterze {f_pitch:6.1f} Hz  (prog 35, jak kolumna)")
    print(f"  naprezenie u nasady        {sig_root:8.2f} MPa  wobec 130 (5754)"
          f"  ->  zapas {130/sig_root:.0f}x  {verdict(130/sig_root)}")
    print("  Warianty, i czemu nie jedna blacha: python par6_ref/adapter_stiffness.py")

    # --- 6. plyta ruchoma, przypadek boczny -------------------------------
    m_side = (ad.ARM_ONLY + ad.PAYLOAD) * G * ad.ARM_REACH / 1000.0
    f_rail = m_side * 1000.0 / 260.0
    line("6. PLYTA RUCHOMA - ramie wysuniete W BOK")
    print(f"  moment boczny              {m_side:8.1f} N*m  (ramie na pelnym"
          f" zasiegu {ad.ARM_REACH:.0f} mm)")
    print(f"  roznica sil na prowadnice  {f_rail:8.0f} N  (rozstaw 260 mm)")
    print(f"                             ->  zapas wobec C0 "
          f"{HGH20_C0/f_rail:.0f}x  {verdict(HGH20_C0/f_rail)}")
    print("  SKRECANIA plyty nie ma: ramie stoi w osi plyty, wiec moment od")
    print("  wysunietego ramienia jest symetryczny i idzie na czyste zginanie.")
    print("  Skrecanie pojawi sie dopiero w ukladzie DWURAMIENNYM przy")
    print("  nierownym obciazeniu - wtedy trzeba to policzyc od nowa.")

    # --- 8. castery -------------------------------------------------------
    # Tyl: caster D125 gumowo-zelazny, skretny, z hamulcem postojowym, 1.1 kg
    # (wybrany 2026-08-19). Przod: kolo omni D127 na X 260 (2026-10-03) -
    # bez skretu, kontakt stoi w miejscu. Oba w osi robota.
    # Masa, CoM i pozycja castera z dynamics.py - jedna kopia modelu, nie
    # trzy. Wlasne stale stad mowily 55.7 kg i caster na X 240; w jezdzie do
    # przodu kolo stoi za osia skretu, na 170, i niesie o polowe wiecej.
    import dynamics as dyn
    W_TOT, COM_X_D, COM_Z_D = dyn.com_with_arm(dyn.ARM_Z_HIGH)
    CAST_X  = dyn.CASTER_F
    A_BRAKE = dyn.brake_limits(COM_X_D, COM_Z_D)[1]   # granica przyczepnosci
    CAST_TRAVEL = 12.0      # caster_travel z modelu
    f_static = W_TOT * COM_X_D / CAST_X
    f_brake  = W_TOT * COM_Z_D * A_BRAKE / CAST_X
    line("8. KOLA PODPOROWE - obciazenie i czego wymaga podatny uchwyt")
    print(f"  kolo przednie, na postoju  {f_static:8.1f} kg")
    print(f"  dodatkowo przy hamowaniu   {f_brake:8.1f} kg"
          f"   (przeniesienie ciezaru przy {A_BRAKE:.2f} g)")
    print(f"  SZCZYT na przednim kole     {f_static + f_brake:8.1f} kg")
    print("  Nosnosc kola omni musi to przeniesc z zapasem.  [VERIFY na karcie]")
    print()
    print("  DWA KOLA PODPOROWE W OSI TO KOLYSKA. Robot ma cztery punkty podparcia,")
    print("  a plaszczyzne wyznaczaja trzy - na nierownej podlodze jeden caster")
    print("  zawsze wisi i robot buja sie wzdluznie wokol osi kol.")
    print("  Ani caster (gumowo-zelazny), ani omni nie ma wlasnej podatnosci -")
    print("  cala musi dac uchwyt, najlepiej przedniego kola, ktore niesie wiecej.")
    print()
    k_half = f_static * G / (CAST_TRAVEL / 2)
    print(f"  Wymagana sztywnosc uchwytu, jesli ciezar wlasny ma scisnac")
    print(f"  polowe skoku {CAST_TRAVEL:.0f} mm:   {k_half:8.1f} N/mm")
    print(f"  Przy tej sztywnosci uchwyt dobiera nierownosc podlogi do"
          f" +/-{CAST_TRAVEL/2:.0f} mm")
    print(f"  zanim caster oderwie sie albo dobije do konca skoku.")
    print("  To jest SPEC na brakujaca czesc, nie jej projekt.")

    # --- 7. katowniki na stykach ramy -------------------------------------
    DECK_KG = 5.0
    f_bracket = DECK_KG * G / 4.0
    line("7. KATOWNIKI NA STYKACH RAMY")
    print(f"  poprzeczka niesie okolo    {DECK_KG:8.1f} kg (poklad + elektronika)")
    print(f"  na jeden katownik          {f_bracket:8.0f} N")
    print("  Katalogowy katownik do rowka 8 z M6 trzyma setki N.  [VERIFY]")
    print("  WNIOSEK: o liczbie katownikow NIE decyduje wytrzymalosc, tylko")
    print("  sztywnosc montazowa. Moment wywracajacy kolumny idzie belkami")
    print("  wprost w kola - poprzeczki nie sa w tej sciezce w ogole.")
    print("  Dwa katowniki na styk, 5 poprzeczek x 2 konce x 2 = 20 sztuk.")

    # --- podsumowanie -----------------------------------------------------
    print()
    print("=" * 72)
    print("  CO MA LICZBE, A CO NIE")
    print("=" * 72)
    done = [
        # numbers that belong to other scripts are not copied here - three of
        # these four had gone stale (34 Hz, 111 mm, 0.25 g) by 2026-10-03
        ("kregoslup kolumny", "backbone_stiffness.py", "pierwsza postac vs prog"),
        ("wsporniki lozysk", "recznie, w komentarzu", "19.7 MPa / 127, 6.5x"),
        ("styk podstawy kolumny", "recznie, w komentarzu", "320 N*m / 11.3, 28x"),
        ("wydruki - pelzanie", "print_vs_metal.py", "kazda czesc osobno"),
        ("stabilnosc i masa", "mass_report.sh", "margines vs 100 mm projektowe"),
        ("wozki, belki, plyta, sruba", "TEN PLIK", "patrz wyzej"),
        ("adapter PAR6", "adapter_stiffness.py", "blad na chwytaku i postac"),
        ("katowniki ramy", "TEN PLIK", "nie wytrzymalosc, tylko sztywnosc"),
        ("os Z - predkosc i moment", "z_drive.py", "silnik przewymiarowany 10x"),
        ("kola podporowe", "TEN PLIK", f"szczyt {f_static + f_brake:.0f} kg,"
                                     f" spec uchwytu {k_half:.0f} N/mm"),
        ("hamowanie, skret, ramie", "dynamics.py", "progi wywrotki i poslizgu w g"),
    ]
    missing = [
        ("uchwyt kola napedowego", "geometria osi piasty nieznana [MEASURE]"),
        ("podatny uchwyt kola przedniego", "CZESC NIE ISTNIEJE"),
        ("detal anti-tipa", "CZESC NIE ISTNIEJE"),
        ("skrecanie plyty przy 2 ramionach", "uklad dwuramienny nie policzony"),
        ("charakterystyka moment-obroty", "potrzebna karta NEMA23 i napiecie"),
        ("poslizg i luzowanie srub", "brak danych o drganiach"),
        ("udar na progu", "to impuls, nie przyspieszenie - potrzebny uchwyt"),
        ("podatnosc opon i casterow", "obniza realny prog wywrotki, nie liczone"),
        ("srodek ciezkosci ramienia", "masa zwazona, CoG NIE            [MEASURE]"),
    ]
    print("\n  POLICZONE")
    for a, b, c in done:
        print(f"    {a:<28}{b:<26}{c}")
    print("\n  BEZ ZADNEJ LICZBY")
    for a, b in missing:
        print(f"    {a:<34}{b}")
    print()
    print("  Pierwsze trzy z listy braku to te same czesci, ktore czekaja")
    print("  na zakupione elementy. Reszta czeka tylko na decyzje.")


if __name__ == "__main__":
    main()
