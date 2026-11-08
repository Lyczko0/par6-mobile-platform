#!/usr/bin/env python3
"""Dzwignia pomiarowa NEMA23 57BYG250B - czy wytrzyma i czy nie slizga sie na walku.

    python test_rig/lever_check.py

DLACZEGO
  Dzwignia do testu momentu ma dwa niezalezne tryby awarii i tylko jeden z nich
  jest oczywisty. Pekniecie ramienia liczy kazdy. Przekrecenie sie zacisku na
  gladkim walku 8 mm jest tym, co realnie psuje pomiar - i to ono decyduje
  o srednicy piasty, nie wytrzymalosc belki.

CZEGO NIE LICZY
  Pelzania PLA pod dlugotrwalym naciagiem sruby. Dzwignia jest przyrzadem na
  godziny, nie na miesiace - ale jak ma wisiec obciazona przez dobe, docisk
  trzeba sprawdzic ponownie.
  Anizotropii wydruku miedzy warstwami. Orientacja druku jest tak dobrana,
  ze naprezenie idzie W warstwie, nie w poprzek - patrz PRINT_SETTINGS.md.
"""

import math

G = 9.81

# --- silnik -----------------------------------------------------------------
T_MOTOR   = 1.2          # N*m, moment postojowy 57BYG250B (karta)   [VERIFY]
SHAFT_D   = 8.0          # mm, srednica walka (opis oferty)          [VERIFY]
OVERLOAD  = 3.0          # na tyle projektuje - test moze przestrzelic

# --- geometria dzwigni (musi zgadzac sie z Test_Lever_NEMA23.py) -------------
ARM_R      = 100.0       # mm, otwor pomiarowy - promien roboczy
ARM_R_MID  = 50.0        # mm, drugi otwor
HUB_D      = 26.0
HUB_H      = 22.0
BORE_D     = 8.2
WEB_T      = 10.0        # grubosc = wysokosc druku
WEB_H_ROOT = 28.0
WEB_H_TIP  = 14.0
EAR_X      = 22.0        # ucho zacisku siega do x = -EAR_X
EAR_W      = 20.0
SLIT_W     = 2.0
# Odciazenia sa PODLUZNE: (srodek, szerokosc, dlugosc czesci prostej).
# Okragly otwor w srodniku znaczy "punkt pomiarowy" i nic innego - piec
# okraglych dziur w rzedzie pozwalalo pomylic promien i caly pomiar o 2x.
LIGHT      = [(32.0, 12.0, 6.0), (66.0, 10.0, 6.0), (88.0, 8.0, 3.0)]
LOAD_HOLE  = 6.0

# Objetosc bryly ZMIERZONA w Fusion po zbudowaniu modelu (nie szacunek).
# Szacunek analityczny nizej sluzy juz tylko do wychwycenia, czy zmiana
# parametru nie rozjechala sie z modelem.
VOL_FUSION = 29_350.0    # mm3

# --- material ---------------------------------------------------------------
E_PLA     = 2_200.0      # MPa, wydruk wzdluz warstwy                [VERIFY]
SIG_PLA   = 25.0         # MPa, dopuszczalne krotkotrwale
RHO_PLA   = 1.24e-3      # g/mm3
MU        = 0.30         # PLA - stal, na sucho                      [VERIFY]
BEAR_PLA  = 20.0         # MPa, docisk pod podkladka
DERATE    = 3.0          # model pierscienia jest optymistyczny


def web_h(x):
    """Wysokosc srodnika w plaszczyznie stolu, x liczone od osi walka."""
    x0, x1 = HUB_D / 2.0, ARM_R
    if x <= x0:
        return WEB_H_ROOT
    f = min((x - x0) / (x1 - x0), 1.0)
    return WEB_H_ROOT + (WEB_H_TIP - WEB_H_ROOT) * f


def slot_gap(x):
    """Wysokosc materialu wyjeta przez szczeline na wspolrzednej x."""
    for cx, d, ln in LIGHT:
        off = abs(x - cx)
        r = d / 2.0
        if off <= ln / 2.0:
            return d
        if off <= ln / 2.0 + r:
            return 2.0 * math.sqrt(max(r ** 2 - (off - ln / 2.0) ** 2, 0.0))
    return 0.0


def section_i(x):
    """Moment bezwladnosci przekroju, z odjeciem szczeliny odciazajacej."""
    h = web_h(x)
    i_sec = WEB_T * h ** 3 / 12.0
    g = slot_gap(x)
    if g > 0.0:
        i_sec -= WEB_T * g ** 3 / 12.0
    return i_sec


def section_z(x):
    """Wskaznik wytrzymalosci przekroju."""
    return section_i(x) / (web_h(x) / 2.0)


def main():
    print("=" * 72)
    print("  DZWIGNIA POMIAROWA NEMA23 - CZY WYTRZYMA")
    print("=" * 72)
    f_tip = T_MOTOR / (ARM_R / 1000.0)
    f_mid = T_MOTOR / (ARM_R_MID / 1000.0)
    print(f"  moment silnika {T_MOTOR:.2f} N*m")
    print(f"  na promieniu {ARM_R:.0f} mm  ->  {f_tip:5.1f} N  = {f_tip/G:5.2f} kg")
    print(f"  na promieniu {ARM_R_MID:.0f} mm  ->  {f_mid:5.1f} N  = {f_mid/G:5.2f} kg")
    print(f"  projektuje na {OVERLOAD:.0f}x zapas, czyli {f_tip*OVERLOAD:.0f} N na koncu")

    # --- zginanie ------------------------------------------------------------
    print()
    print("  " + "-" * 68)
    print("  ZGINANIE SRODNIKA")
    print("  " + "-" * 68)
    print(f"  {'x [mm]':>8}{'h [mm]':>9}{'Z [mm3]':>10}"
          f"{'sig 1x':>9}{'sig 3x':>9}   uwaga")
    worst = (0.0, None)
    for x in (HUB_D / 2.0, 32.0, 50.0, 66.0, 88.0, ARM_R):
        m1 = f_tip * (ARM_R - x)
        z = section_z(x)
        s1, s3 = m1 / z, m1 * OVERLOAD / z
        note = "szczelina odciazajaca" if slot_gap(x) > 0 else ""
        if x == ARM_R:
            note = "otwor pomiarowy"
        if x <= HUB_D / 2.0:
            note = "u nasady piasty"
        print(f"  {x:>8.0f}{web_h(x):>9.1f}{z:>10.0f}{s1:>9.2f}{s3:>9.2f}   {note}")
        if s3 > worst[0]:
            worst = (s3, x)
    print()
    print(f"  najgorszy przekroj: x = {worst[1]:.0f} mm,"
          f"  {worst[0]:.2f} MPa przy {OVERLOAD:.0f}x")
    print(f"  dopuszczalne dla PLA {SIG_PLA:.0f} MPa  ->  zapas"
          f" {SIG_PLA/worst[0]:.1f}x")

    # --- ugiecie -------------------------------------------------------------
    n = 400
    d1 = 0.0
    x0 = HUB_D / 2.0
    dx = (ARM_R - x0) / n
    for i in range(n):
        x = x0 + (i + 0.5) * dx
        m = f_tip * (ARM_R - x)
        d1 += m * (ARM_R - x) / (E_PLA * section_i(x)) * dx
    d3 = d1 * OVERLOAD
    print()
    print(f"  ugiecie konca:  {d1:.2f} mm przy {T_MOTOR:.1f} N*m,"
          f"  {d3:.2f} mm przy {OVERLOAD:.0f}x")
    print("  Ugiecie nie psuje pomiaru sily, ale zmienia ramie -"
          f" o {d1/ARM_R*100:.2f} % przy nominale.")

    # --- zacisk --------------------------------------------------------------
    print()
    print("  " + "=" * 68)
    print("  ZACISK NA WALKU - TO JEST WLASCIWE OGRANICZENIE")
    print("  " + "=" * 68)
    f_shaft = T_MOTOR / (SHAFT_D / 2000.0)
    print(f"  Sila obwodowa na powierzchni walka:  {f_shaft:.0f} N")
    print(f"  Zeby jej nie puscic tarciem przy mu = {MU:.2f},"
          f" potrzeba {f_shaft/MU:.0f} N docisku.")
    print()
    wash_od, wash_id = 9.0, 4.3
    a_bear = math.pi / 4.0 * (wash_od ** 2 - wash_id ** 2)
    f_bolt = BEAR_PLA * a_bear
    t_ideal = MU * 2 * math.pi * f_bolt * (SHAFT_D / 2000.0)
    t_real = t_ideal / DERATE
    print("  Naciag sruby M4 ogranicza docisk pod lbem, nie sama sruba:")
    print(f"    powierzchnia pod podkladka {a_bear:.0f} mm2"
          f"  x  {BEAR_PLA:.0f} MPa  =  {f_bolt:.0f} N")
    print(f"  Model cienkiego pierscienia daje    {t_ideal:5.2f} N*m")
    print(f"  Po derate {DERATE:.0f}x (nierownomierny docisk, ugiecie piasty)"
          f"   {t_real:5.2f} N*m")
    print(f"  Wymagane {T_MOTOR:.2f} N*m  ->  zapas {t_real/T_MOTOR:.1f}x")
    if t_real / T_MOTOR < 2.0:
        print("  UWAGA: zapas ponizej 2x. Jesli zacisk puszcza, kolejnosc")
        print("  ratunku: (1) podkladka pod lbem, (2) druga sruba, (3) stalowy")
        print("  pierscien zaciskowy 8 mm zatopiony w piascie.")
    a_nowash = math.pi / 4.0 * (7.0 ** 2 - 4.5 ** 2)
    t_nowash = MU * 2 * math.pi * (BEAR_PLA * a_nowash) * (SHAFT_D / 2000.0) / DERATE
    print()
    print(f"  BEZ PODKLADKI lb M4 opiera sie na {a_nowash:.0f} mm2 zamiast"
          f" {a_bear:.0f} - zapas spada do {t_nowash/T_MOTOR:.1f}x.")
    print("  Podkladka nie jest ozdoba.")

    # --- masa i tara ---------------------------------------------------------
    hub = math.pi / 4.0 * (HUB_D ** 2 - BORE_D ** 2) * HUB_H
    ear = (EAR_X - HUB_D / 2.0 + 3) * EAR_W * HUB_H * 0.7
    web_a = (ARM_R - HUB_D / 2.0) * (WEB_H_ROOT + WEB_H_TIP) / 2.0
    web_a += math.pi / 8.0 * WEB_H_TIP ** 2
    web_a -= sum(math.pi / 4.0 * d ** 2 + ln * d for _, d, ln in LIGHT)
    web_a -= 2 * math.pi / 4.0 * LOAD_HOLE ** 2
    web = web_a * WEB_T
    vol_est = hub + ear + web - SLIT_W * (EAR_X + 1) * HUB_H
    vol = VOL_FUSION
    print()
    print("  " + "-" * 68)
    print("  MASA I TARA")
    print("  " + "-" * 68)
    print(f"  objetosc z Fusion    {vol/1000.0:6.2f} cm3")
    print(f"  szacunek analityczny {vol_est/1000.0:6.2f} cm3"
          f"   (rozjazd {abs(vol_est-vol)/vol*100:.0f} %)")
    if abs(vol_est - vol) / vol > 0.15:
        print("  ROZJAZD > 15 % - albo zmienil sie model, albo ten skrypt.")
    for fill, lab in ((1.00, "lita"), (0.70, "5 scianek + 30 % gyroid")):
        print(f"    {lab:<26} {vol*RHO_PLA*fill:5.1f} g")
    m_real = vol * RHO_PLA * 0.70
    x_com = (ear * -14.0 + web * (HUB_D / 2 + ARM_R) / 2.0) / (hub + ear + web)
    t_self = m_real / 1000.0 * G * x_com / 1000.0
    print(f"  srodek ciezkosci     x = {x_com:.0f} mm od osi walka")
    print(f"  wlasny moment        {t_self:.4f} N*m"
          f"  = {t_self/T_MOTOR*100:.1f} % nominalu")
    print("  To trzeba wyzerowac PRZED pomiarem - albo odjac od wyniku.")


if __name__ == "__main__":
    main()
