#!/usr/bin/env python3
"""Os Z: predkosc, czas przejazdu, moment silnika, hamulec.

    python control/z_drive.py

DLACZEGO
  Predkosc krytyczna sruby wyszla 3529 obr/min i to brzmi jak duzo, ale
  obroty niczego nie mowia. Skok to 5 mm, wiec dopiero czas przejazdu calego
  zakresu pokazuje, o czym mowimy. Punkt odniesienia: kolumna teleskopowa,
  ktora Lyczko0 mial wczesniej, jechala z gory na dol w 60 s.

CZEGO NIE LICZY
  Charakterystyki moment-obroty konkretnego NEMA23 - ta spada z predkoscia
  i to ona, a nie moment postojowy, decyduje na gorze zakresu. Bez karty
  silnika i napiecia zasilania nie da sie tego policzyc.
  Tarcia w prowadnicach i w nakretce poza katalogowa sprawnoscia.
"""

import math

G = 9.81

STROKE      = 574.25     # mm, z_travel
LEAD        = 5.0        # mm/obr, SFU1605
ADAPTER_KG  = 1.67        # P2, asserted by par6_ref/adapter_stiffness.py
CARRIAGE_KG = 2.777 + 0.639 + 1.400 + ADAPTER_KG  # plyta, nakretka gieta, wozki
MOVING_KG   = 6.6 + 0.5 + CARRIAGE_KG  # ZWAZONE ramie + obiekt + wozek
SCREW_KG    = 1.26       # sruba 16 mm x 800
SCREW_D     = 16.0
N_CRIT      = 3529.0     # obr/min, z load_paths.py
ETA_FWD     = 0.90       # sprawnosc sruby kulowej, katalogowa      [VERIFY]
ETA_BACK    = 0.80       # sprawnosc wsteczna                        [VERIFY]
REF_TIME    = 60.0       # s, kolumna teleskopowa - punkt odniesienia


def main():
    print("=" * 70)
    print("  OS Z - ILE TO JEST NAPRAWDE")
    print("=" * 70)
    print(f"  skok {STROKE:.0f} mm,  sruba {LEAD:.0f} mm/obr,"
          f"  masa w ruchu {MOVING_KG:.1f} kg")

    print()
    print(f"  {'obr/min':>9}{'mm/s':>9}{'cm w 5 s':>11}{'caly skok':>12}   uwaga")
    rows = [
        (115,  "tempo kolumny teleskopowej"),
        (300,  ""),
        (600,  "spokojne, prawie bezglosne"),
        (1000, "rozsadny cel"),
        (1400, ""),
        (2000, ""),
        (N_CRIT, "PREDKOSC KRYTYCZNA SRUBY - nie zblizac sie"),
    ]
    for rpm, note in rows:
        v = rpm * LEAD / 60.0
        cm5 = min(v * 5.0, STROKE) / 10.0
        t = STROKE / v
        cap = "  (caly skok krotszy)" if v * 5.0 > STROKE else ""
        print(f"  {rpm:>9.0f}{v:>9.0f}{cm5:>10.1f}{cap}{t:>12.1f} s   {note}")

    print()
    print(f"  Kolumna teleskopowa robila ten skok w {REF_TIME:.0f} s, czyli"
          f" {STROKE/REF_TIME:.1f} mm/s = {STROKE/REF_TIME*60/LEAD:.0f} obr/min.")
    print(f"  Zeby ja pobic dziesieciokrotnie wystarczy"
          f" {STROKE/(REF_TIME/10)*60/LEAD:.0f} obr/min -"
          f" {N_CRIT/(STROKE/(REF_TIME/10)*60/LEAD):.0f}x ponizej krytycznej.")
    print("  Predkosc krytyczna nie jest tu zadnym ograniczeniem i nie ma sensu")
    print("  o nia walczyc. Ograniczeniem bedzie moment silnika przy obrotach.")

    # --- moment -----------------------------------------------------------
    f_ax = MOVING_KG * G
    t_lift = f_ax * (LEAD / 1000.0) / (2 * math.pi * ETA_FWD)
    t_hold = f_ax * (LEAD / 1000.0) * ETA_BACK / (2 * math.pi)

    j_screw = 0.5 * SCREW_KG * (SCREW_D / 2000.0) ** 2
    j_load  = MOVING_KG * (LEAD / 1000.0 / (2 * math.pi)) ** 2
    j_tot   = j_screw + j_load

    print()
    print("  " + "-" * 66)
    print("  MOMENT NA WALE")
    print("  " + "-" * 66)
    print(f"  obciazenie osiowe                {f_ax:7.0f} N")
    print(f"  moment na podnoszenie            {t_lift:7.3f} N*m"
          f"   (sprawnosc {ETA_FWD:.2f})")
    print(f"  moment, ktory os oddaje w dol    {t_hold:7.3f} N*m"
          f"   <- tyle musi utrzymac HAMULEC")
    print(f"  bezwladnosc sruby + odbita masy  {j_tot*1e6:7.1f} g*cm2"
          f"   (sruba {j_screw/j_tot*100:.0f} %)")
    for rpm, t_acc in ((1000, 0.3), (1000, 0.1)):
        alpha = rpm * 2 * math.pi / 60.0 / t_acc
        print(f"  rozpedzenie do {rpm} obr/min w {t_acc:.1f} s"
              f"    {j_tot*alpha:7.3f} N*m")
    t_need = t_lift + j_tot * (1000 * 2 * math.pi / 60.0 / 0.3)
    print()
    print(f"  RAZEM potrzeba okolo             {t_need:7.3f} N*m")
    for nm in (0.6, 1.2, 1.9):
        print(f"    NEMA23 {nm} N*m postojowo   -> zapas {nm/t_need:5.1f}x"
              f"  {'OK' if nm/t_need >= 3 else 'granica'}")
    print()
    print("  Silnik jest przewymiarowany na moment o rzad wielkosci. Wiazaca")
    print("  bedzie charakterystyka moment-obroty: NEMA23 traci moment powyzej")
    print("  okolo 1000 obr/min i tego TU NIE LICZE - potrzebna karta silnika")
    print("  i napiecie zasilania sterownika.")
    # --- czy hamulec jest potrzebny ---------------------------------------
    # Pytanie zadane wprost 2026-08-19. Odpowiedz jest liczbowa, nie uznaniowa.
    print()
    print("  " + "=" * 66)
    print("  CZY HAMULEC JEST POTRZEBNY")
    print("  " + "=" * 66)
    print("  Sruba kulowa nie jest samohamowna - sprawnosc wsteczna"
          f" {ETA_BACK:.2f}.")
    print(f"  Ciezar osi napiera na wal momentem  {t_hold:.3f} N*m.")
    print()
    print("  Co go trzyma, gdy nie ma pradu? Silnik bez zasilania ma tylko")
    print("  moment zaczepowy - katalogowo 4-7 % momentu postojowego.")
    for nm in (0.6, 1.2, 1.9):
        for frac, lab in ((0.04, "4 %"), (0.07, "7 %")):
            det = nm * frac
            ok = det > t_hold
            print(f"    NEMA23 {nm} N*m, zaczepowy {lab}"
                  f" = {det:.3f} N*m  ->  "
                  f"{'utrzyma, ale bez zapasu' if ok else 'NIE UTRZYMA - os zjezdza'}")
    print()
    # jak szybko spada, gdy zaczepowy nie wystarcza
    det = 1.2 * 0.05
    t_net = t_hold - det
    if t_net > 0:
        alpha = t_net / j_tot
        t_fall = math.sqrt(2 * (STROKE / 1000.0) / (LEAD / 1000.0)
                           * 2 * math.pi / alpha)
        # alpha*t to rad/s; /2pi daje obr/s; x LEAD daje mm/s. Bez zadnego
        # x1000 - pierwsza wersja to miala i wyplula 502809 mm/s.
        v_end = alpha * t_fall / (2 * math.pi) * LEAD
        print(f"  Przy zaczepowym 5 % ({det:.3f} N*m) zostaje"
              f" {t_net:.3f} N*m na rozpedzanie osi.")
        print(f"  Caly skok {STROKE:.0f} mm zjezdza w {t_fall:.1f} s,"
              f" konczac przy {v_end:.0f} mm/s.")
        print(f"  Dla porownania predkosc krytyczna sruby to"
              f" {N_CRIT * LEAD / 60.0:.0f} mm/s - opadajaca os"
              f" {'PRZEKRACZA JA' if v_end > N_CRIT * LEAD / 60.0 else 'jej nie osiaga'}")
        print("  i zaczyna bic. To nie jest opadanie, to spadanie"
              " z ramieniem 4.5 kg.")
    print()
    print("  WNIOSEK: hamulec NIE jest zbedny. Zaczepowy silnika jest tego")
    print("  samego rzedu co obciazenie, wiec o utrzymaniu osi decydowalby")
    print("  przypadek. Dodatkowo E-STOP odcina prad do silnika - bez hamulca")
    print("  wcisniecie grzybka ZRZUCALOBY ramie, czyli robiloby dokladnie to,")
    print("  przed czym ma chronic.")
    print()
    print("  Zapas samego hamulca jest natomiast duzy: typowy zintegrowany")
    print(f"  trzyma 0.5-1 N*m wobec potrzebnych {t_hold:.3f} -"
          f" {0.5/t_hold:.0f}x.  [VERIFY na karcie]")
    print("  Duzy zapas hamulca to nie to samo co brak potrzeby hamulca.")

    bench_limits()


# ---------------------------------------------------------------------------
#  JAKIE V I A USTAWIC - i czego z tego NIE DA SIE policzyc
# ---------------------------------------------------------------------------
J_ROTOR   = 3.0e-5       # kg*m2, wirnik NEMA23 57x56              [VERIFY karta]
L_PHASE   = 3.6e-3       # H, indukcyjnosc fazy - SZACUNEK          [VERIFY karta]
V_SUPPLY  = 23.6         # V, ZMIERZONE na szynie 2026-09-06
I_PEAK    = 1.7          # A szczytowo (1200 mA rms * sqrt(2))
TARGET_RPM = 1000.0      # cel projektowy z tabeli wyzej: 6.9 s na caly skok


def corner_rpm(v_supply, l_phase, i_peak, full_steps=200.0):
    """Obroty, przy ktorych zasilacz przestaje nadazac z przewracaniem pradu.

    Prad w fazie musi przejsc z +I na -I co dwa pelne kroki. Przy n obr/min
    jest na to 0.6/n sekundy, a zmiana wynosi 2I. Napiecie potrzebne to
    L*di/dt, wiec n_corner = V * 0.6 / (2 * L * I). Powyzej tego moment
    zaczyna opadac i silnik zaczyna gubic kroki.
    """
    return v_supply * (120.0 / full_steps) / (2.0 * l_phase * i_peak)


def bench_limits():
    print()
    print("=" * 70)
    print("  JAKIE V I A USTAWIC NA STANOWISKU")
    print("=" * 70)

    j_screw = 0.5 * SCREW_KG * (SCREW_D / 2000.0) ** 2
    j_load  = MOVING_KG * (LEAD / 1000.0 / (2 * math.pi)) ** 2
    j_tot   = J_ROTOR + j_screw + j_load

    print(f"  Cel projektowy: {TARGET_RPM:.0f} obr/min ="
          f" {TARGET_RPM * LEAD / 60:.0f} mm/s ="
          f" {STROKE / (TARGET_RPM * LEAD / 60):.1f} s na caly skok.")
    print(f"  W jednostkach aplikacji (stopnie na WALE):"
          f"  V = {TARGET_RPM * 6:.0f} deg/s")

    # --- 1. przyspieszenie: sprawdzamy, czy w ogole jest ograniczeniem -----
    print()
    print("  1. PRZYSPIESZENIE - nie jest ograniczone momentem")
    print("  " + "-" * 66)
    print(f"     bezwladnosc calkowita {j_tot*1e6:.1f} g*cm2"
          f"  (wirnik {J_ROTOR/j_tot*100:.0f} %, sruba {j_screw/j_tot*100:.0f} %,"
          f" masa {j_load/j_tot*100:.0f} %)")
    print()
    print(f"  {'rampa do celu':>16}{'obr/min/s':>11}{'deg/s2':>10}"
          f"{'moment':>10}{'droga rampy':>13}")
    for t_ramp in (1.0, 0.5, 0.3, 0.15):
        rpm_s = TARGET_RPM / t_ramp
        alpha = rpm_s * 2 * math.pi / 60.0
        t_acc = j_tot * alpha
        dist  = 0.5 * (TARGET_RPM * LEAD / 60.0) * t_ramp
        print(f"  {t_ramp:>14.2f} s{rpm_s:>11.0f}{rpm_s*6:>10.0f}"
              f"{t_acc:>9.3f} N*m{dist:>11.1f} mm")

    t_lift = MOVING_KG * G * (LEAD / 1000.0) / (2 * math.pi * ETA_FWD)
    print()
    print(f"     Do tego stale {t_lift:.3f} N*m na samo podnoszenie.")
    print(f"     Nawet najostrzejsza rampa daje razem"
          f" {t_lift + j_tot * (TARGET_RPM/0.15) * 2*math.pi/60:.3f} N*m"
          f" wobec 1.2 N*m postojowo.")
    print("     WNIOSEK: przyspieszenia nie ogranicza moment. Ogranicza je to,")
    print("     czy silnik w otwartej petli nadazy - a to jest inna sprawa.")

    # --- 2. predkosc: TU jest prawdziwe ograniczenie ------------------------
    print()
    print("  2. PREDKOSC - tu jest prawdziwe ograniczenie i NIE ZNAMY GO")
    print("  " + "-" * 66)
    print(f"     Zasilanie {V_SUPPLY:.1f} V (zmierzone), prad szczytowy"
          f" {I_PEAK:.1f} A.")
    print("     Obroty graniczne zaleza od INDUKCYJNOSCI FAZY, ktorej nie mamy:")
    print()
    print(f"  {'L fazy':>10}{'obr/min gr.':>14}{'mm/s':>9}{'deg/s':>9}   werdykt")
    for l in (1.5e-3, 2.5e-3, 3.6e-3, 5.0e-3, 8.0e-3):
        n = corner_rpm(V_SUPPLY, l, I_PEAK)
        ok = "cel OK" if n > TARGET_RPM * 1.3 else (
             "ciasno" if n > TARGET_RPM else "CEL NIEOSIAGALNY")
        print(f"  {l*1000:>8.1f} mH{n:>14.0f}{n*LEAD/60:>9.0f}{n*6:>9.0f}   {ok}")
    n_est = corner_rpm(V_SUPPLY, L_PHASE, I_PEAK)
    print()
    print(f"     Przy zalozonych {L_PHASE*1000:.1f} mH wychodzi {n_est:.0f}"
          f" obr/min - czyli cel {TARGET_RPM:.0f} lezy DOKLADNIE na granicy.")
    print("     Dlatego tego nie da sie zalatwic obliczeniem. Trzeba zmierzyc.")

    # --- 3. drabinka testowa -----------------------------------------------
    print()
    print("  3. DRABINKA TESTOWA - od czego zaczac i jak sprawdzac")
    print("  " + "-" * 66)
    print("     Metoda: zamaluj kreske na wale, ustaw ZERO, pusc CYC 90 500 20.")
    print("     Po 20 cyklach kreska MUSI wrocic w to samo miejsce. Kazdy")
    print("     zgubiony krok kumuluje sie, wiec 20 cykli powieksza blad")
    print("     dwudziestokrotnie - 1 krok na cykl to juz 2 stopnie odchylki.")
    print()
    print(f"  {'krok':>6}{'V deg/s':>10}{'obr/min':>10}{'A deg/s2':>11}"
          f"{'rampa':>9}   uwaga")
    ladder = [
        (300,   2000,  "start, ma dzialac zawsze"),
        (900,   5000,  ""),
        (1800,  10000, "polowa celu"),
        (3600,  20000, ""),
        (4800,  20000, "tu zwykle zaczyna gubic"),
        (6000,  20000, "CEL - 1000 obr/min"),
        (7200,  20000, "zapas, jak przejdzie - swietnie"),
    ]
    for v, a, note in ladder:
        print(f"  {'':>6}{v:>10}{v/6:>10.0f}{a:>11}{v/a:>8.2f} s   {note}")
    print()
    print("     Po znalezieniu granicy: ZEJDZ O JEDEN SZCZEBEL i tam zostan.")
    print("     Otwarta petla nie ma zapasu - albo nadaza, albo gubi, a gubi")
    print("     najchetniej pod obciazeniem, ktorego na stanowisku nie ma.")
    print()
    print("     Prad zmieniaj OSOBNO. Wiecej pradu = wiecej momentu przy")
    print("     obrotach, wiec drabinke trzeba przejsc jeszcze raz po kazdej")
    print("     zmianie CUR. Nie mieszaj dwoch zmiennych naraz.")

    # --- 4. sprzezenie z baza ----------------------------------------------
    a_lin = (TARGET_RPM / 0.3) * 2 * math.pi / 60.0 * (LEAD / 1000.0) / (2*math.pi)
    f_react = MOVING_KG * a_lin
    print()
    print("  4. CO TO ROBI BAZIE")
    print("  " + "-" * 66)
    print(f"     Rampa 0.3 s to {a_lin*1000:.0f} mm/s2 na {MOVING_KG:.1f} kg,")
    print(f"     czyli sila reakcji {f_react:.0f} N = {f_react/G:.2f} kg"
          f" ({f_react/(MOVING_KG*G)*100:.0f} % ciezaru osi).")
    print("     Pionowo, wiec nie wywraca - ale odejmuje sie od nacisku na kola")
    print("     przy ruszaniu w gore i dodaje przy hamowaniu w dole.")
    # The threshold margin is not copied here - it read "1.05x" for weeks
    # after it stopped being true (2026-10-03: the caster trail).
    print("     Prog 20 mm nie ma zapasu, ktory moglby to zjesc (dynamics.py,")
    print("     sekcja 6). Te 4 N to ulamek ciezaru robota, ale nie podnos osi Z")
    print("     rownoczesnie z wjazdem na prog; nic to nie kosztuje.")


# ---------------------------------------------------------------------------
#  E-STOP: twarde odciecie 24 V kontra sekwencja hamulca w firmware
# ---------------------------------------------------------------------------
# Firmware Teensy przy E-STOP najpierw zaciska hamulec, czeka 120 ms i dopiero
# wtedy odcina cewki - bo zrzucenie obu naraz zostawia wal wolny na czas
# dociskania szczek. CONTROL_ARCHITECTURE.md sekcja 6 planowala jednak styk NC
# tnacy 24 V do drivera I hamulca JEDNOCZESNIE. To jest dokladnie ten przypadek,
# przed ktorym firmware sie broni. Ile to realnie kosztuje?
T_BRAKE_ENGAGE = 0.120   # s, czas dociskania szczek, z README stanowiska [VERIFY]
T_BRAKE_HOLD   = 0.5     # N*m, typowy hamulec zintegrowany NEMA23      [VERIFY]
DETENT_FRAC    = (0.04, 0.07)   # moment zaczepowy jako czesc postojowego
T_HOLDING      = 1.2     # N*m


def estop_window():
    print()
    print("=" * 70)
    print("  E-STOP: CO SIE DZIEJE Z OSIA Z, GDY GRZYBEK TNIE 24 V")
    print("=" * 70)
    j_screw = 0.5 * SCREW_KG * (SCREW_D / 2000.0) ** 2
    j_load  = MOVING_KG * (LEAD / 1000.0 / (2 * math.pi)) ** 2
    j_tot   = J_ROTOR + j_screw + j_load
    t_back  = MOVING_KG * G * (LEAD / 1000.0) * ETA_BACK / (2 * math.pi)
    mm_per_rad = LEAD / (2 * math.pi)

    print(f"  Przez {T_BRAKE_ENGAGE*1000:.0f} ms szczeki jeszcze nie trzymaja,")
    print("  a cewki juz nie maja pradu. Os trzyma tylko moment zaczepowy.")
    print()
    print(f"  {'zaczepowy':>10}{'start z postoju':>18}{'jazda w dol 1000 obr/min':>27}")
    for frac in DETENT_FRAC:
        t_net = max(t_back - frac * T_HOLDING, 0.0)
        alpha = t_net / j_tot
        rows = []
        for w0 in (0.0, TARGET_RPM * 2 * math.pi / 60.0):
            t = T_BRAKE_ENGAGE
            theta = w0 * t + 0.5 * alpha * t * t
            w_end = w0 + alpha * t
            # potem hamulec zatrzymuje wal: opoznienie z nadwyzki momentu
            a_dec = (T_BRAKE_HOLD - t_back) / j_tot
            theta += w_end ** 2 / (2 * a_dec)
            rows.append(theta * mm_per_rad)
        print(f"  {frac*100:>8.0f} %{rows[0]:>15.1f} mm{rows[1]:>22.1f} mm")
    print()
    print("  Z postoju to milimetry - zaczepowy i bezwladnosc wirnika odbitej")
    print("  przez skok 5 mm robia z tej osi bardzo leniwe wahadlo. Ale jadac")
    print("  w dol pelna predkoscia os PRZEJEZDZA DALEJ o ponad centymetr, bo")
    print("  twarde odciecie nie hamuje - tylko przestaje napedzac.")
    print()
    print("  WNIOSEK - zatrzymanie KATEGORII 1, nie 0:")
    print("    styk NC grzybka -> wejscie ESTOP Teensy: firmware zatrzymuje")
    print("       os i zaciska hamulec w ulamku milisekundy, cewki trzymaja;")
    print("    drugi styk NC -> 24 V przez PRZEKAZNIK Z OPOZNIENIEM WYLACZENIA")
    print("       ~250 ms: moc znika zawsze, ale dopiero po sekwencji.")
    print("  Twarde odciecie zostaje gwarancja - przekaznik czasowy nie")
    print("  potrzebuje dzialajacego softu. Koszt: jeden modul czasowy.")
    print("  [VERIFY] czas dociskania i moment hamulca z karty - to one")
    print("  ustawiaja opoznienie, 250 ms to 2x zalozone 120.")


if __name__ == "__main__":
    main()
    estop_window()
