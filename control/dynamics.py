#!/usr/bin/env python3
"""Dynamika: hamowanie, skret, szybkie ruchy ramienia.

    python control/dynamics.py

DLACZEGO
  Wszystkie dotychczasowe liczby w tym projekcie byly STATYCZNE. Marginesy
  rzedu 100-800x w sciezkach nosnych sugerowaly, ze dynamika nie bedzie
  problemem - i to zalozenie okazuje sie prawdziwe dla WYTRZYMALOSCI, ale
  nie dla STATECZNOSCI. Tam decyduje wysokosc srodka ciezkosci, a nie
  wytrzymalosc czegokolwiek.

JAK TO JEST LICZONE
  Model quasi-statyczny: przyspieszenie zamieniam na pozorne przesuniecie
  srodka ciezkosci o com_z * a/g i sprawdzam, czy nie wychodzi poza wielobok
  podparcia. To standardowe podejscie dla wozkow i wozkow widlowych.

CZEGO NIE OBEJMUJE
  Podatnosci opon i castorow - realny robot przechyla sie na ogumieniu
  ZANIM zacznie sie wywracac, wiec faktyczny prog jest NIZSZY niz tu wychodzi.
  Drgan i odbicia od progu - to udar, nie przyspieszenie.
  Sprzezenia: ramie machajace w trakcie skretu liczone jest jako suma,
  a nie jako pelna dynamika wielobryly.
  Wszystkie te trzy rzeczy dzialaja NA NIEKORZYSC. Wyniki traktuj jako
  gorna granice tego, co robot zniesie, nie jako gwarancje.
"""

import math

G = 9.81

# --- masy i geometria, z modelu -------------------------------------------
# PRZEPISANE Z `bash mobile_base/mass_report.sh` 2026-10-07, dolny kraniec (pakiet nad osiami, nowy uchwyt kola)
# (kolo omni z przodu, wsporniki oslon, oslony i skorupa kolumny z objetosci
# siatek, dolny kraniec z wypelnienia ze slicera 55 % - 2026-10-04).
# Balast jest juz W SRODKU tych liczb - siedzi w base_masses.scad jako dwa
# plaskowniki stalowe na licach belek. Nie dokladaj go tu drugi raz.
ROBOT_KG    = 52.490         # baza z balastem, bez ramienia
COM_X_ROBOT = 21.557         # CoM samej bazy, z balastem, pakiet na X -40
ROBOT_COM_Z = 336.6
MODEL_COM_X_FRONT = 90.6     # to samo co mass_report: CoM z ramieniem, poza front
ARM_KG     = 6.6 + 0.5       # ZWAZONE ramie + obiekt
ARM_X      = 601.0           # punkt przylozenia ciezaru ramienia, poza front
ARM_Z_HIGH = 881.0           # lico montazu ramienia, gora
ARM_Z_LOW  = 307.0

WHEEL_Y    = 230.0           # +/- Y osi kol napedowych
# Kolo castera stoi ZA osia skretu w kierunku jazdy. Do 2026-10-03 ten plik
# bral X 240 - pozycje kola przy jezdzie DO TYLU - i liczyl hamowanie i prog
# tak, jakby przedni caster podpieral robota 70 mm dalej, niz robi to w jezdzie.
# Od 2026-10-03 przod niesie kolo omni (sekcja 7): nie skreca, kontakt stoi.
OMNI_X     = 260.0           # omni_x
OMNI_R_MM  = 63.5            # omni_d / 2                             [MEASURE]
CASTER_PIVOT = 205.0         # -caster_rear_pivot; tylny caster, oś skretu -205
CASTER_TRAIL = 35.0          # caster_swivel_off                      [MEASURE]
CASTER_F   = OMNI_X                        # przednia krawedz, w kazdej jezdzie
CASTER_R   = -(CASTER_PIVOT - CASTER_TRAIL)  # tylny w jezdzie do tylu: -170
MODEL_MARGIN_FRONT = 112.2   # mass_report, poza front - pilnowane nizej
ANTITIP_X  = -262.0
ANTITIP_GAP = 8.0

MU         = 0.7             # guma po gladkiej podlodze                [VERIFY]

# Balast: 2 x plaskownik 150x80x12 na zewnetrznych licach belek, z tylu.
# Wczesniej ten plik trzymal wlasny balast 1.76 kg na X -250, Y 0, Z 60 -
# czyli dokladnie tam, gdzie stoi tylny caster, i o ktorym mass_report.sh nie
# wiedzial. Dwa modele mowily przez to dwie rozne rzeczy: tu PASS 101.8 mm,
# tam RISK 94 mm. Teraz jest jedno zrodlo prawdy: base_parameters.scad 4b.
BALLAST_KG = 2.261           # ballast_kg z modelu
BALLAST_X  = -215.0          # ballast_cx
BALLAST_Z  = 200.0           # ballast_cz - na wysokosci belek, nie na dnie

ARM_REACH  = 424.0
ARM_J_EST  = None            # liczone nizej


def com_with_arm(z_arm, ballast=True):
    """Zwraca (masa, com_x, com_z) calego robota z ramieniem.

    ballast=False ODEJMUJE balast od modelu - sluzy tylko do porownania,
    bo w modelu balast juz jest.
    """
    m = ROBOT_KG + ARM_KG
    mx = ROBOT_KG * COM_X_ROBOT + ARM_KG * ARM_X
    mz = ROBOT_KG * ROBOT_COM_Z + ARM_KG * z_arm
    if not ballast:
        m -= BALLAST_KG
        mx -= BALLAST_KG * BALLAST_X
        mz -= BALLAST_KG * BALLAST_Z
    return m, mx / m, mz / m


# Straznik przed kolejnym rozjazdem kopii: liczby wyzej musza odtwarzac CoM,
# ktory drukuje mass_report.sh. Jak ktos zmieni model i nie przepisze tych
# wartosci, skrypt ma sie wywrocic, a nie liczyc dynamike dla innego robota.
_m, _cx, _cz = com_with_arm(ARM_Z_HIGH)
assert abs(_cx - MODEL_COM_X_FRONT) < 1.0, (
    f"dynamics.py rozjechal sie z mass_report.sh: CoM x {_cx:.1f} "
    f"zamiast {MODEL_COM_X_FRONT} - przepisz stale z raportu")


def margin_plan(cx, cy, front=(OMNI_X, 0.0)):
    """Najmniejsza odleglosc rzutu CoM od krawedzi wieloboku podparcia przy
    KAZDYM ustawieniu casterow - support_poly() w base_variants.scad. Kontakt
    to kolo (x, y, r); krawedz jest styczna do obu swoich kol od wnetrza.
    front = (X osi skretu, wyprzedzenie) przedniego podparcia; 0 = bez skretu."""
    disks = [(front[0], 0.0, front[1]), (0.0, WHEEL_Y, 0.0),
             (-CASTER_PIVOT, 0.0, CASTER_TRAIL), (0.0, -WHEEL_Y, 0.0)]
    m = math.inf
    for i in range(4):
        (ax, ay, ar), (bx, by, br) = disks[i], disks[(i + 1) % 4]
        ln = math.hypot(bx - ax, by - ay)
        ux, uy = (bx - ax) / ln, (by - ay) / ln
        s = (ar - br) / ln
        c = math.sqrt(1 - s * s)
        nx, ny = -c * uy + s * ux, c * ux + s * uy
        m = min(m, nx * (cx - ax) + ny * (cy - ay) - ar)
    return m


def threshold(m, cx, x_front, r_wheel, h=20.0):
    """Wjazd na prog h: przednie kolo (promien r_wheel, kontakt na x_front)
    niesie m*cx/x_front i trzeba je wepchnac na krawedz. (potrzeba, naped da)
    w N, przy MU."""
    fc = m * cx / x_front
    ratio = math.tan(math.acos((r_wheel - h) / r_wheel))
    return ratio * fc * G, MU * (m - fc) * G


def brake_limits(cx, cz):
    """Hamowanie z jazdy do przodu: (wywrotka, poslizg) w g. Krawedz
    wywrotki to przednie kolo, ktore w tej jezdzie stoi na CASTER_F.
    Przy hamowaniu ciezar PRZENOSI SIE na przednie kolo, wiec kola traca
    docisk dokladnie wtedy, gdy najbardziej go potrzebuja. Pierwsza wersja
    tego nie miala i wychodzilo, ze robot wywraca sie przed poslizgiem.
    Rozwiazanie ukladu:  mu*(Xc - cx - cz*k)/Xc = k"""
    return ((CASTER_F - cx) / cz,
            MU * (CASTER_F - cx) / (CASTER_F + MU * cz))


# Ten sam straznik dla polygonu: margines z mass_report.sh, poza front.
assert abs(margin_plan(_cx, 0.0) - MODEL_MARGIN_FRONT) < 1.0, (
    f"dynamics.py rozjechal sie z mass_report.sh: margines "
    f"{margin_plan(_cx, 0.0):.1f} zamiast {MODEL_MARGIN_FRONT}")


def line(t):
    print()
    print("  " + "-" * 68)
    print("  " + t)
    print("  " + "-" * 68)


def main():
    print("=" * 72)
    print("  DYNAMIKA - hamowanie, skret, ruchy ramienia")
    print("=" * 72)

    for lab, ball in (("bez balastu", False),
                      (f"z balastem {BALLAST_KG} kg", True)):
        m, cx, cz = com_with_arm(ARM_Z_HIGH, ball)
        print(f"  {lab:<20} masa {m:5.1f} kg   CoM x {cx:6.1f}   z {cz:6.1f}"
              f"   margines w planie {margin_plan(cx, 0):5.1f} mm")
    m, cx, cz = com_with_arm(ARM_Z_HIGH, True)
    m_lo, cx_lo, cz_lo = com_with_arm(ARM_Z_LOW, True)
    print()
    print("  Dalej licze z balastem i z ramieniem NA GORZE - to najgorszy uklad.")

    # --- 1. hamowanie -----------------------------------------------------
    a_tip, a_trac = brake_limits(cx, cz)
    drive_frac = (CASTER_F - cx) / CASTER_F      # ile ciezaru na kolach, na postoju
    a_trac_naive = MU * drive_frac
    line("1. HAMOWANIE")
    print(f"  wywrotka do przodu przy       {a_tip:6.2f} g"
          f"   (CoM przesuwa sie o {cz*a_tip:.0f} mm)")
    print(f"  ciezar na kolach, na postoju  {drive_frac*100:6.0f} %"
          f"   (CoM {cx:.0f} mm przed osia, przednie kolo na {CASTER_F:.0f})")
    print(f"  gdyby ciezar sie nie przenosil {a_trac_naive:5.2f} g")
    print(f"  granica przyczepnosci REALNA  {a_trac:6.2f} g"
          f"   (mu = {MU}, z przeniesieniem ciezaru)")
    if a_trac < a_tip:
        print(f"  -> kola BUKSUJA zanim robot sie wywroci."
              f"  Zapas {a_tip/a_trac:.2f}x  DOBRZE")
        print("     To wlasciwy tryb awarii: robot slizga sie, nie przewraca.")
    else:
        print(f"  -> ROBOT WYWRACA SIE ZANIM KOLA STRACA PRZYCZEPNOSC."
              f"  {a_trac/a_tip:.2f}x za duzo")
        print("     Zly tryb awarii. Trzeba ograniczyc hamowanie w software.")
    for v_kmh in (2, 4, 6):
        v = v_kmh / 3.6
        d_tip = v ** 2 / (2 * a_tip * G)
        d_tra = v ** 2 / (2 * a_trac * G)
        print(f"  z {v_kmh} km/h ({v*100:.0f} cm/s): droga hamowania min"
              f" {max(d_tip, d_tra)*1000:5.0f} mm"
              f"   (ponizej tego {'wywrotka' if a_tip < a_trac else 'poslizg'})")

    # --- 2. przyspieszanie do tylu ----------------------------------------
    a_tip_r = (cx - CASTER_R) / cz
    line("2. RUSZANIE I HAMOWANIE DO TYLU")
    print(f"  wywrotka do tylu przy         {a_tip_r:6.2f} g"
          f"   ({a_tip_r/a_tip:.1f}x bezpieczniej niz do przodu)")
    print(f"  Anti-tip stoi na X {ANTITIP_X:.0f} z luzem {ANTITIP_GAP:.0f} mm -"
          f" lapie przechyl {math.degrees(math.atan(ANTITIP_GAP/abs(ANTITIP_X-cx))):.1f} st.")

    # --- 3. skret ---------------------------------------------------------
    marg_lat = margin_plan(cx, 0)
    a_lat_tip = marg_lat / cz
    line("3. SKRET")
    print(f"  margines boczny w planie      {marg_lat:6.1f} mm")
    print(f"  wywrotka bokiem przy          {a_lat_tip:6.2f} g")
    print(f"  granica przyczepnosci bokiem  {MU:6.2f} g  (caly ciezar na oponach)")
    print(f"  -> {'slizga sie pierwszy, DOBRZE' if MU < a_lat_tip else 'WYWRACA SIE PIERWSZY'}")
    print()
    print(f"  {'promien skretu':>16}{'v max [m/s]':>14}{'v max [km/h]':>14}")
    for r in (0.5, 1.0, 2.0):
        v = math.sqrt(a_lat_tip * G * r)
        print(f"  {r:>14.1f} m{v:>14.2f}{v*3.6:>14.1f}")
    print("  Robot rozniocowy skreca w miejscu - promien 0 to obrot wokol osi,")
    print("  bez sily odsrodkowej. Powyzsze dotyczy jazdy po luku.")

    # --- 4. ruch ramienia -------------------------------------------------
    # Ramie jako punkt masy na promieniu: J = m r^2. To zawyza, bo masa jest
    # rozlozona, ale w te strone ma byc bezpiecznie.
    j_arm = ARM_KG * (ARM_REACH / 1000.0) ** 2
    line("4. SZYBKIE RUCHY RAMIENIA")
    print(f"  bezwladnosc ramienia (punkt na {ARM_REACH:.0f} mm)"
          f"   {j_arm:.2f} kg*m2")
    print(f"  {'obrot 90 st. w':>16}{'przysp. kata':>14}{'moment reakcji':>16}"
          f"{'pozorne a bazy':>16}")
    for t in (2.0, 1.0, 0.5):
        # profil trojkatny: polowa czasu rozpedza, polowa hamuje
        alpha = 4 * (math.pi / 2) / t ** 2
        torque = j_arm * alpha
        # reakcja pozioma na baze: F = m * alpha * r
        f_react = ARM_KG * alpha * (ARM_REACH / 1000.0)
        a_equiv = f_react / (m * G)
        print(f"  {t:>14.1f} s{alpha:>12.1f} rad/s2{torque:>13.1f} N*m"
              f"{a_equiv:>14.3f} g")
    print(f"  Wywrotka nastepuje przy {a_tip:.2f} g, wiec nawet obrot 90 st.")
    print("  w pol sekundy jest daleko ponizej progu - ramie jest lekkie")
    print("  wzgledem bazy. Ale to sila POZIOMA; moment reakcji obciaza")
    print("  wozki i adapter, nie stabilnosc.")

    # --- 5. przypadek zlozony ---------------------------------------------
    line("5. HAMOWANIE W SKRECIE - przypadek zlozony")
    print("  Przyspieszenia sumuja sie wektorowo. Elipsa bezpieczenstwa:")
    print(f"  {'a wzdluz [g]':>14}{'a bok [g]':>14}{'suma':>10}   werdykt")
    for ax in (0.0, 0.10, 0.15, 0.20, a_tip):
        rem = 1.0 - (ax / a_tip) ** 2
        ay = a_lat_tip * math.sqrt(rem) if rem > 0 else 0.0
        tot = math.hypot(ax, ay)
        print(f"  {ax:>14.2f}{ay:>14.2f}{tot:>10.2f}   "
              f"{'granica wywrotki' if ax >= a_tip - 1e-6 else 'na krawedzi elipsy'}")
    print()
    bind = min(a_tip, a_lat_tip)
    print(f"  Wiazaca jest os {'BOCZNA' if a_lat_tip < a_tip else 'WZDLUZNA'}"
          f" - prog {bind:.2f} g.")
    print(f"  Praktyczny wniosek: trzymac sie ponizej {bind*0.5:.2f} g")
    print("  w kazdej osi, czyli polowy progu wywrotki. To zwykla praktyka")
    print("  dla wozkow i daje zapas na podatnosc opon, ktorej tu nie liczylem.")
    for v_kmh in (2, 4):
        v = v_kmh / 3.6
        print(f"    z {v_kmh} km/h zatrzymanie na"
              f" {v**2/(2*bind*0.5*G)*1000:.0f} mm")

    # --- 6. wjazd na prog, quasi-statycznie -------------------------------
    # Kolo o promieniu R wchodzi na prog h dopiero, gdy sila pozioma na jego
    # osi przekroczy N * tan(acos((R-h)/R)). Przednie kolo ma ok. polowe
    # promienia kola napedowego, wiec to ONO jest sciana - model mowil to od
    # dawna, ale nikt nie sprawdzil, czy naped w ogole ma czym pchnac.
    FRONT_R = OMNI_R_MM          # od 2026-10-03 omni; wczesniej caster R62.5
    WHEEL_R_MM  = 100.0          # ZMIERZONE 2026-08-19, bylo 108
    line("6. WJAZD NA PROG - czy naped ma czym pchnac przednie kolo")
    f_caster_load = m * (cx / CASTER_F)                 # kg na przednim kole
    f_drive_load  = m - f_caster_load
    print(f"  na przednim kole {f_caster_load:5.1f} kg,"
          f" na kolach {f_drive_load:5.1f} kg")
    print(f"  {'prog':>7}{'kolo R' + format(FRONT_R, '.1f'):>16}{'potrzeba':>12}"
          f"{'naped da':>12}   werdykt")
    for h in (10, 15, 20, 35):
        ratio = math.tan(math.acos((FRONT_R - h) / FRONT_R))
        need, have = threshold(m, cx, CASTER_F, FRONT_R, h)
        print(f"  {h:>5} mm{ratio:>14.2f}{need:>10.0f} N{have:>10.0f} N   "
              f"{'OK, zapas ' + format(have/need, '.2f') + 'x' if have > need else 'ZA MALO - ' + format(need/have, '.2f') + 'x brakuje'}")
    print()
    print("  Pierwsza wersja tego akapitu mowila 'tylem jest latwiej, bo prog")
    print("  bierze kolo napedowe'. To bylo zle z dwoch powodow: liczby wyszly")
    print("  gorsze (246 N wobec 236), a przede wszystkim NAPEDZANE kolo przy")
    print("  progu to inna fizyka - opiera sie momentem o krawedz, a nie tarciem")
    print("  o podloge. Tego nie modeluje.")
    print()
    print("  CO REALNIE POMAGA - dwie drogi, obie policzone:")
    print()
    # 1. wieksze kolo przednie
    need_ratio = MU * (m - f_caster_load) / f_caster_load
    r_min = 20.0 / (1.0 - 1.0 / math.sqrt(1.0 + need_ratio ** 2))
    print(f"  a) WIEKSZE KOLO PRZEDNIE. Zeby prog 20 mm przeszedl, potrzeba")
    print(f"     wspolczynnika <= {need_ratio:.2f}, czyli promienia >="
          f" {r_min:.0f} mm, D >= {2*r_min:.0f} mm.")
    # Ten napis zawsze mowil "za maly", takze wtedy, gdy D125 miescil sie
    # w wymaganiu (125 > 121 mm) - liczba byla dobra, zdanie klamalo.
    k = FRONT_R / r_min
    print(f"     Wybrane omni D{2 * FRONT_R:.0f} (R{FRONT_R}) - "
          + (f"ma {k:.2f}x zapasu." if k >= 1.0 else f"jest {1/k:.2f}x za maly."))
    for d in (150, 200):
        rr = d / 2
        ratio = math.tan(math.acos((rr - 20) / rr))
        print(f"     D{d}: wspolczynnik {ratio:.2f}"
              f"  -> zapas {need_ratio/ratio:.2f}x")
    print()
    # 2. wiecej balastu - przesuwa ciezar z przedniego kola na naped
    print("  b) WIECEJ BALASTU. Cofniecie CoM zdejmuje ciezar z przedniego kola")
    print("     I DOKLADA go kolom - dziala z dwoch stron naraz.")
    print(f"  {'balast [kg]':>13}{'CoM x':>9}{'przod':>9}{'naped':>8}"
          f"{'potrzeba':>11}{'naped da':>11}")
    ratio20 = math.tan(math.acos((FRONT_R - 20) / FRONT_R))
    # 2.26 to druga para plaskownikow na tych samych srubach
    for extra in (0.0, 1.0, 2.26):
        mm_ = m + extra
        cxx = (m * cx + extra * BALLAST_X) / mm_
        fc = mm_ * cxx / CASTER_F
        fd = mm_ - fc
        if extra == 0.0:
            fc_nom, fd_nom = fc, fd
        need = ratio20 * fc * G
        have = MU * fd * G
        print(f"  {BALLAST_KG + extra:>13.2f}{cxx:>9.1f}{fc:>8.1f}kg{fd:>7.1f}kg"
              f"{need:>9.0f} N{have:>9.0f} N   "
              f"{'OK' if have > need else 'za malo'}")

    print()
    print("  TO STOI NA WSPOLCZYNNIKU TARCIA, KTOREGO NIKT NIE ZMIERZYL.")
    _z = (MU * fd_nom * G) / (ratio20 * fc_nom * G)
    print(f"  Przy mu={MU} naped daje {_z * 100:.0f} % potrzebnej sily:")
    ratio20 = math.tan(math.acos((FRONT_R - 20) / FRONT_R))
    mm2 = m + 0.0
    fc2 = mm2 * cx / CASTER_F
    fd2 = mm2 - fc2
    need2 = ratio20 * fc2 * G
    for mu_t in (0.5, 0.6, 0.7, 0.8, 0.9):
        have2 = mu_t * fd2 * G
        print(f"    mu = {mu_t}: naped da {have2:3.0f} N wobec {need2:.0f} N   "
              f"{'OK, zapas ' + format(have2/need2, '.2f') + 'x' if have2 > need2 else 'ZA MALO'}")
    print(f"  Prog 20 mm przechodzi dopiero od mu = {need2 / (fd2 * G):.2f}."
          " Twarda plytka albo")
    print("  panele moga dac mniej. To jest pomiar do zrobienia na podlodze,")
    print("  po ktorej robot ma jezdzic, a nie liczba z tablicy.")
    print()
    print("  Prog 35 mm nie przechodzi w zadnym wariancie - do tego potrzebny")
    print("  jest wieksze kolo przednie, nie wiecej balastu.")

    line("6b. UDERZENIE W PROG - tego nie licze")
    print("  Nie licze tego. Uderzenie przedniego kola w prog 20 mm przy 4 km/h to")
    print("  impuls o czasie rzedu milisekund i szczytowym przyspieszeniu")
    print("  o rzad wielkosci wyzszym niz cokolwiek powyzej. Rozstrzyga o tym")
    print("  PODATNOSC uchwytu przedniego kola - czesc, ktora jeszcze nie istnieje.")
    print("  To jest realny powod, dla ktorego podatny uchwyt jest")
    print("  na liscie braków, a nie kosmetyczny detal.")

    # --- 7. przednie podparcie, ramie ROZLOZONE -----------------------------
    # Lyczko0 2026-10-03: robot ma jezdzic takze z rozlozonym ramieniem, wiec
    # sama zasada "jazda tylko ze zlozonym" nie wystarcza. Tyl bez zmian.
    # Caster zamiata kolo wyprzedzenie + R + luz 6 i oslona musi je objac;
    # kolo omni nie skreca - kontakt stoi w miejscu, obrys to samo kolo.
    line("7. PRZEDNIE PODPARCIE - jazda z rozlozonym ramieniem (poza przod, gora)")
    sx = (ROBOT_KG * COM_X_ROBOT + ARM_KG * (ARM_X - ARM_REACH)) / m
    sy = ARM_KG * ARM_REACH / m
    front_now = 205.0 + 35.0 + 62.5 + 6.0    # caster na 205 - stan do 2026-10-03
    print(f"  {'wariant':<26}{'margines':>9}{'bok':>6}{'prog 20':>9}"
          f"{'mu min':>8}{'hamow.':>8}{'bokiem':>8}{'przod':>7}")
    print(f"  {'':<26}{'[mm]':>9}{'[mm]':>6}{'[x]':>9}{'':>8}"
          f"{'[g]':>8}{'[g]':>8}{'[mm]':>7}")
    # (nazwa, X osi lub kola, wyprzedzenie, promien kola)    omni D127 [VERIFY]
    for name, x, r, rw in (("caster D125, os 205 (bylo)", 205.0, CASTER_TRAIL, 62.5),
                           ("caster D125, os 290", 290.0, CASTER_TRAIL, 62.5),
                           ("caster D125, os 310", 310.0, CASTER_TRAIL, 62.5),
                           ("omni D127 na 240", 240.0, 0.0, 63.5),
                           ("omni D127 na 260 WYBRANE", OMNI_X, 0.0, OMNI_R_MM),
                           ("omni D127 na 290", 290.0, 0.0, 63.5)):
        x_fwd = x - r                       # kontakt w jezdzie do przodu
        need, have = threshold(m, cx, x_fwd, rw)
        mu_min = MU * need / have
        print(f"  {name:<26}{margin_plan(cx, 0.0, (x, r)):>9.0f}"
              f"{margin_plan(sx, sy, (x, r)):>6.0f}{have / need:>9.2f}{mu_min:>8.2f}"
              f"{(x_fwd - cx) / cz:>8.2f}{margin_plan(cx, 0.0, (x, r)) / cz:>8.2f}"
              f"{x + r + rw + 6.0 - front_now:>+7.0f}")
    print("  margines: przy KAZDYM ustawieniu kolek, wymagane 100. prog 20:")
    print(f"  ile razy naped przewyzsza potrzebe przy mu = {MU}. przod: o ile")
    print("  przesuwa sie lico przedniej oslony (obrys podparcia + luz 6).")


if __name__ == "__main__":
    main()
