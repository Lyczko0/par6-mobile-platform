// ############################################################################
//  base_parameters.scad  -  MOBILE BASE V1 (KONCEPT)
//
//  Baza mobilna pod istniejacy modul osi Z (../z_lift), docelowo pod jedno
//  lub dwa ramiona PAR6/PAROL6.
//
//  JEDNOSTKI: MILIMETRY.
//
//  UKLAD WSPOLRZEDNYCH (zgodny z Mobile_Manipulator_V1_Chassis.py):
//    origin = PODLOGA (Z=0), srodek obrysu podwozia
//    +X = PRZOD robota,  +Y = LEWA strona,  +Z = GORA
//
//  STATUS: KONCEPT. Zadnego wymiaru nie traktowac jako finalnego.
//  Wszystko oznaczone [MEASURE] wymaga realnego pomiaru przed CNC -
//  pelna lista w MEASURE_BEFORE_CNC.md.
//
//  Komentarze w kodzie po angielsku dla spojnosci z ../z_lift/*.scad,
//  dokumentacja (.md) po polsku.
// ############################################################################

$fa = 5;
$fs = 1.2;

// ---------------------------------------------------------------------------
// 0.  DISPLAY (nadpisywane w main_base.scad)
// ---------------------------------------------------------------------------
variant            = "C";     // "A" | "B" | "C"  - wariant podparcia
show_frame         = true;
show_drive         = true;
show_casters       = true;
show_battery       = true;
show_cnc           = true;
show_column        = true;    // interfejs kolumny Z + strefa keep-out
show_electronics   = true;
show_skirts        = false;   // estetyczne oslony boczne
show_stability     = false;   // polygon podparcia + rzut CoM
show_dimensions    = false;
show_zlift_ghost   = false;   // obrys kolumny Z dla kontekstu
arm_pose           = "front"; // "front" | "side" | "max"
view               = "iso";   // "iso"|"top"|"bottom"|"side"|"front"
explode            = 0;

// ---------------------------------------------------------------------------
// 1.  OBRYS I WYSOKOSCI
// ---------------------------------------------------------------------------
base_length        = 600;   // X, calkowita dlugosc ramy
base_width         = 560;   // Y, calkowita szerokosc korpusu (bez skirtow)
base_deck_height   = 240;   // Z gornego pokladu = GORA BELEK GLOWNYCH.
                            // BYLO 250, bo lezala tu jeszcze plyta montazowa
                            // kolumny 300x420x10. Usunieta 2026-08-18: wszystkie
                            // cztery sruby rastru 250 ladują na licu belek
                            // glownych (Y +/-125 wobec belki 117.5..157.5),
                            // wiec plyta nie miala czego przenosic - byla
                            // przekladka duplikujaca plyte bazowa z_lift,
                            // ktora ma identyczny obrys 300x420x10.
                            // MUSI byc rowne base_deck_from_floor w
                            // ../z_lift/parameters.scad - to jest interfejs.
ground_clearance   = 45;    // najnizszy punkt konstrukcji (taca baterii)

doorway_clear_min  = 700;   // najwezsze drzwi jakie ma pokonac    [MEASURE]
doorway_margin_req = 40;    // wymagany zapas na strone

// ---------------------------------------------------------------------------
// 2.  NAPED - 2 x KOLO 8.5 CALA (HUB MOTOR)
// ---------------------------------------------------------------------------
// ZMIERZONE 2026-08-19 linijka w poprzek opony: 200 mm, zgodnie z
// oznaczeniem. Model zakladal 216 (8.5 cala) i mylil sie o 16 mm.
// To NIE zmienia proporcji robota - wszystko jest mierzone od podlogi -
// ale zmienia dwie rzeczy: geometrie uchwytu kola (os siada 8 mm nizej
// wzgledem ramy) i zdolnosc wchodzenia na prog, bo mniejsze kolo ma gorzej.
wheel_diameter     = 200;   // ZMIERZONE, zgadza sie z oznaczeniem 200x90
// 2026-08-19: hoverboard w reku. Na oponie stoi 200x90 - opona off-road,
// wyrazniej szersza niz zakladane 65. Biore 90 (nominal z oznaczenia), bo do
// przeswitow bezpieczniejsza jest wieksza. Pomiar suwmiarka dal ~82, co jest
// normalne - oznaczenia opon sa nominalne.
// SREDNICA NADAL OTWARTA: oznaczenie mowi 200, model zakladal 216, a pomiar
// 822 mm nie pasuje do zadnego z nich. Patrz nizej.
wheel_width        = 90;    // z oznaczenia 200x90                     [MEASURE]
wheel_hub_d        = 110;   // srednica obudowy silnika            [MEASURE]
// Os piasty - JEDNOSTRONNA, wystaje do srodka robota. Przekroj z CAD
// (mobile_base/ref/hoverboard_8in, GrabCAD 8"), suwmiarka 15.8 / 13.3 zgodna.
// Dlugosci: Lyczko0 2026-10-07, kolo plasko na stole: calosc 185, plask od
// 130, os wystaje 75 za lico silnika (lico na 110). Opona 82, wiec od
// SRODKA OPONY: lico silnika 69, plask 89, czolo 144. Do 2026-10-07 model
// mial os 14 mm konczaca sie 75 mm od srodka opony - te same "75", ale
// liczone od innego miejsca. [MEASURE] czy kolo lezalo na oponie, czy na
// kolpaku silnika - na kolpaku wszystko jest o ~14 mm blizej srodka opony.
axle_d             = 16;
axle_flat          = 13;    // od plaska (gora, pod strzemieniem) do dolu
axle_end           = 185 - 82 / 2;   // 144, srodek opony -> czolo  [MEASURE]
axle_flat_from     = 130 - 82 / 2;   // 89, srodek opony -> plask    [MEASURE]
axle_cable_l       = 40;    // przewody prosto za czolem, przed gieciem [MEASURE]
// Silnik jest szerszy od opony (110 wobec 82): od srodka wystaje 28 mm poza
// bok opony, od zewnatrz kolpak chowa sie lekko w oponie (Lyczko0 2026-10-07).
hub_face_in        = 110 - 82 / 2;   // 69, srodek opony -> lico silnika od srodka
wheel_track        = 460;   // rozstaw kol napedowych (osie)
drive_axle_x       = 0;     // pozycja wspolnej osi poprzecznej.
                            // 0 = srodek obrysu. To jest glowny parametr
                            // kompromisu trakcja / promien obrotu -
                            // patrz BASE_CONCEPT.md.
wheel_radius       = wheel_diameter / 2;   // = wysokosc osi nad podloga

// ---------------------------------------------------------------------------
// 3.  KOLA PODPOROWE
// ---------------------------------------------------------------------------
caster_diameter    = 125;   // duze kolo = latwiejszy prog         [MEASURE]
caster_width       = 20;   // szerokosc bieznika, z karty (bylo 40)
caster_swivel_off  = 35;    // wyprzedzenie skretnego (trail)      [MEASURE]
caster_plate_thk   = 6;
caster_front_x     = 240;   // warianty B i C; w A przod niesie kolo omni
caster_rear_x      = -240;
// Wariant A, PRZOD: kolo omni, nie caster (Lyczko0 2026-10-03, X 260).
// Caster skretny stawal po jezdzie do przodu 35 mm za osia skretu i zjadal
// 45 mm marginesu. Omni nie skreca - kontakt stoi w miejscu, a oslona
// obejmuje samo kolo zamiast zamiatania 360 stopni. control/dynamics.py,
// sekcja 7: margines 112 mm, prog 20 mm 1.21x, przod +21 mm.
omni_x             = 260;
omni_d             = 127;   // podwojny rzad rolek                 [MEASURE]
omni_w             = 50;    // szerokosc                           [MEASURE]
caster_track       = 380;   // warianty B i C: rozstaw narozny
antitip_d          = 80;    // kolko anti-tip (wariant C)
antitip_gap        = 8;     // luz nad podloga w normalnej jezdzie
antitip_x          = -262;

// ---------------------------------------------------------------------------
// 4.  RAMA - PROFILE ALUMINIOWE
// ---------------------------------------------------------------------------
// Wariant bazowy: belki glowne 40x80 (80 mm w pionie), poprzeczki 40x40.
// Alternatywa 2080/2060 omowiona w BASE_CONCEPT.md.
profile_main_w     = 40;    // szerokosc belki glownej
profile_main_h     = 80;    // wysokosc belki glownej (w pionie)
profile_cross      = 40;    // poprzeczka 40x40
profile_slot       = 8;     // rowek T-slot
// Rozstaw belek podyktowany PAKIETEM: swiatlo miedzy licami musi pomiescic
// 210 mm obudowy + luz. 137.5 daje swiatlo 235, czyli 12.5 mm na strone.
// Przy 125 (poprzednio) swiatlo bylo 210 - pakiet wchodzil z zerowym luzem.
main_beam_y        = 137.5; // +/- Y osi belek glownych
// Poprzeczki 40x40. Dwa twarde warunki, oba wykryte 2026-08-18:
//   1. zadna nie moze wejsc w keepout napedu kolumny (X 70.5..139.5) -
//      dlatego 170, nie 120. Sprawdza to cross_in_motor nizej.
//   2. zadne dwie nie moga na siebie nachodzic - poprzednio -260 i dodatkowa
//      wariantu A na -240 nachodzily na 20 mm. Teraz jest jedna na -240,
//      wysrodkowana pod tylnym casterem, a dodatkowa znika.
// Rozstawy: 120, 120, 170, 70. Najwiekszy 170.
// X=170 zamiast 45 dlatego, ze kolumna wchodzi w rame czterema M6 rastru 250,
// ktore ladują na LICU BELEK GLOWNYCH (Y +/-125 wobec belki 117.5..157.5),
// a nie na poprzeczkach. Kryterium jest wiec sztywnosc ramy, nie podparcie
// plyty - a 170 daje mniejszy najwiekszy rozstaw i usztywnia przod tam,
// gdzie wchodzi obciazenie z castera.
cross_x            = [-240, -120, 0, 170, 240];

frame_top_z        = base_deck_height;                    // 240
frame_bottom_z     = frame_top_z - profile_main_h;        // 160

// ---------------------------------------------------------------------------
// 4b. BALAST - plaskowniki stalowe na zewnetrznych licach belek glownych, tyl
// ---------------------------------------------------------------------------
// Po zwazeniu ramienia (6.6 kg zamiast 3.95) margines statecznosci spadl
// ponizej 100 mm i prog 20 mm przestal przechodzic. control/dynamics.py
// zamknal oba balastem 1.76 kg na X -250, Y 0 - ale tam stoi TYLNY CASTER.
// Balast zyl wiec w jednym skrypcie, w miejscu, ktorego fizycznie nie ma,
// a mass_report.sh o nim nie wiedzial i dalej mowil RISK.
//
// Tu dostaje realne miejsce. W wariancie A boki belek z tylu sa wolne -
// tylne anti-tipy istnieja tylko w wariancie C. Dwa plaskowniki na licach,
// po 2 x M8 w rowki. ZERO czesci do wycinania: plaskownik z hurtowni stali,
// ciety na dlugosc. Wiecej balastu = drugi plaskownik na tych samych srubach
// (ballast_bars_side = 2), bez zmiany niczego innego.
ballast_bar_l      = 150;    // X
ballast_bar_h      = 80;     // Z - rowna belce, nic nie wystaje nad poklad
ballast_bar_t      = 12;     // Y - plaskownik 80x12, standard hutniczy
ballast_bars_side  = 1;      // na strone
ballast_x1         = -290;   // 5 mm luzu do plyty koncowej (X -305..-295)
ballast_cx         = ballast_x1 + ballast_bar_l / 2;           // -215
ballast_cz         = frame_bottom_z + ballast_bar_h / 2;       // 200
ballast_y_in       = main_beam_y + profile_main_w / 2;         // 157.5 - lico
ballast_y_out      = ballast_y_in + ballast_bars_side * ballast_bar_t;
ballast_head_clr   = 7;      // leb M8 5.5 + podkladka 1.5 - wystaje na zewnatrz
rho_steel          = 7.85e-6;   // kg/mm3, S235
ballast_kg         = 2 * ballast_bars_side * ballast_bar_l * ballast_bar_h
                     * ballast_bar_t * rho_steel;              // 2.26

// ---------------------------------------------------------------------------
// 5.  BATERIA
// ---------------------------------------------------------------------------
// PAKIET 36 V 12.8 Ah, 10S4P 18650, 460 Wh, ~3.0 kg, BMS 30 A. NIE KUPIONY
// (Lyczko0 2026-10-07) - wymiary ponizej to WYMAGANIE przy zakupie, nie
// pomiar: max 190 x 90 x 70 z obudowa. Bylo 210 z ogloszenia - przy 210
// pakiet wchodzil w gniazda osi kol (Y +/-99), od 2026-10-07 lezacych tuz
// obok niego. Typowy 10S4P to ~185-200 x 75-80 x 65-70.
// ULOZONY W POPRZEK ROBOTA. Wzdluz (210 w X) nie miescil sie w korytarzu
// miedzy obrysami zamiatania casterow (167 mm) - to byl bloker nr 1.
// W poprzek zajmuje w X tylko 90 mm i problem znika.
battery_l          = 90;    // X  (krotszy bok obudowy)            [VERIFY]
battery_w          = 190;   // Y  MAX przy zakupie (w poprzek robota)
battery_h          = 70;    // Z                                   [VERIFY]
battery_mass       = 3.0;   // kg, z deklaracji sprzedawcy
// Pozycja srodka pakietu.
//
// 2026-09-16: -55 -> -40 i przewody z "rear" na "front". Poprzednia granica
// tylna ("obrys zamiatania tylnego castera -142.5") byla liczona SAMYM
// promieniem kola. Realne zamiatanie to wyprzedzenie 35 + promien 62.5 +
// luz 6 = 103.5 mm, wiec krawedz stoi na -101.5. Test caster_vs_tray, ktory
// by to zlapal, byl zdefiniowany, ale nikt go nie uruchamial - dopiero
// podpiecie go do check_covers.sh pokazalo wanne 8 mm w zamiataniu. W tym
// samym miejscu lezala strefa przewodow: kolo uderzaloby w nie przy skrecie.
//
// Okna, w ktorych miesci sie wszystko (tyl -101.5, przod: naped kolumny
// 70.5 minus wymagane 20 mm):
//   przewody z tylu   -> battery_x w [-16.5, -4.5],  CoM +2.3 mm
//   przewody z przodu -> battery_x w [-46.5, -34.5], CoM +0.8 mm
// Wybrane drugie: mniejszy ruch, wiecej zapasu statecznosci. Pakiet jest
// symetryczny w X, wiec "front" to obrot o 180 st. w wannie, nic wiecej.
battery_x          = -40;
battery_y          = 0;
// Z KTOREJ SCIANY PAKIETU WYCHODZA PRZEWODY. To nie jest kosmetyka.
// Przy battery_x = -20 (stan z 2026-08-18) "front" wchodzil pod naped
// kolumny Z. Przy -40 strefa przewodow konczy sie na +45, a keep-out napedu
// zaczyna sie na 70.5 - 25.5 mm wobec wymaganych 20. Pilnuja tego
// cable_vs_column i caster_vs_cable w check_covers.sh.
battery_cable_side = "front";  // "rear" | "front"
// 2026-10-07: pakiet NAD osiami napedu, pod pokladem (Lyczko0: "bateria moze
// isc troche wyzej, zrobic na nia uchwyty w srodku"). Czolo osi piasty
// z przewodami siega Y +/-86 i lezy POD pakietem. Trzymaja go dwie kolyski
// z blachy na wewnetrznych licach belek (rowki Z 180 i 220) i pasy z gory.
// Wanna 5 mm z dna odpadla - stala tam, gdzie teraz jest os. Wysokosc
// pakietu (battery_z) liczy sie od strzemienia - nizej, po uchwycie kola.
cradle_t           = 3;              // blacha kolyski
cradle_w           = 20;             // pas kolyski w X
cradle_x           = [-75, -45];     // srodki - za wieszakami uchwytu kola
// Wysokosc liczona od strzemienia uchwytu kola: pakiet nad nim i nad czolami
// osi. Musi stac TU, przed column_battery_gap_z - odwolanie w przod to undef.
strap_t            = 3;      // strzemie, blacha                         [MEASURE]
axle_flat_z        = wheel_radius + axle_flat - axle_d / 2;    // 105, plask osi
drive_seat_top_z   = axle_flat_z + strap_t;                    // 108, wierzch strzemienia
battery_z          = drive_seat_top_z + 7;    // 115, spod ogniw
battery_top_z      = battery_z + battery_h;   // 185
tray_top_z         = battery_z;   // wierzch kolyski; nazwa zostaje dla check_interface
battery_cable_zone = 40;    // strefa na przewody i zlacza z przodu pakietu

// ---------------------------------------------------------------------------
// 6.  KOLUMNA Z + STREFA BEZPIECZENSTWA NAPEDU
//     Liczby przeniesione z ../z_lift/parameters.scad. Jesli tam sie zmienia,
//     tu tez trzeba zmienic - to jest twardy interfejs miedzy modulami.
// ---------------------------------------------------------------------------
// Plyta montazowa kolumny USUNIETA - patrz base_deck_height wyzej.
// Plyta bazowa z_lift (420 x 300 x 10) siada wprost na belki glowne.
column_bolt_pitch  = 275;   // = 2 x main_beam_y - sruby ida w rowek belki
column_bolt_d      = 8;
column_x           = 0;     // srodek rastru srub kolumny
column_y           = 0;

// Naped kolumny NIE lezy na osi rastru srub: os sruby pociagowej jest
// column_motor_dx do przodu, bo plyta bazowa z_lift wystaje do tylu.
column_motor_dx    = 105;   // = screw_axis_y - base_plate_cy w z_lift
                            // = 60 - (-45). BYLO 120, gdy sruba stala na
                            // zlift Y=45 przy plytowym kregoslupie. Profil
                            // 40x80 przesunal lancuch, a sruba cofnela sie
                            // o 20 mm, zeby otwor silnika nie wychodzil poza
                            // krawedz plyty. Interfejs - sprawdzaj razem.
column_motor_x     = column_x + column_motor_dx;

// Obwiednia instalacyjna silnika z hamulcem zintegrowanym (z_lift):
//   90 mm silnik+hamulec + 8 mm wyjscie kabla bokiem + 12 mm oslona = 110
column_motor_env   = 95;    // silnik+hamulec: 56 korpus + 39 hamulec
                            // (z rodziny 57AI, trzy zgodne punkty danych)
column_motor_inst  = 115;   // z kablem i oslona
column_motor_frame = 57;    // przekroj silnika
column_motor_cover = 6;     // oslona na promien
column_clear_req   = 20;    // WYMAGANY luz od baterii i jej przewodow

// keep-out: nic nie moze wejsc w te bryle
keepout_w          = column_motor_frame + 2 * column_motor_cover;   // 69
keepout_top_z      = base_deck_height;
keepout_bot_z      = base_deck_height - column_motor_inst;          // 140
keepout_safe_z     = keepout_bot_z - column_clear_req;              // 120

// ---------------------------------------------------------------------------
// 7.  ELEKTRONIKA
// ---------------------------------------------------------------------------
// Plyta elektroniki. BYLO 260 dlugosci na X=-60, co NACHODZILO na plyte
// bazowa kolumny (X -150..150) na 220 mm - obie lezą na frame_top_z.
// Nikt tego nie sprawdzal. Teraz siedzi CALA za kolumna, w pasie
// X -300..-150, i to samo przesuniecie oddaje margines stabilnosci.
elec_plate_l       = 140;
elec_plate_w       = 300;
elec_plate_thk     = 6;
elec_plate_x       = -228;

// Plyta bazowa kolumny z_lift: 420 (Y) x 300 (X) x 10, lezy wprost na belkach
// glownych. To JEDYNA plyta pod kolumna - podwoziowa zostala usunieta.
col_baseplate_w    = 420;   // Y
col_baseplate_d    = 300;   // X
col_baseplate_x0   = -col_baseplate_d / 2;   // -150, przod pasa kolumny
// Nic innego na frame_top_z nie moze wejsc w pas X -150..150.
elec_plate_front   = elec_plate_x + elec_plate_l / 2;
assert(elec_plate_x + elec_box_d / 2 <= elec_plate_x + elec_plate_l / 2,
       "obudowa elektroniki glebsza niz jej wlasna plyta");
assert(elec_plate_x - elec_box_d / 2 >= -half_l,
       "obudowa elektroniki wystaje poza tyl ramy");

assert(elec_plate_front <= col_baseplate_x0,
       str("plyta elektroniki (przod X=", elec_plate_front,
           ") wchodzi pod plyte bazowa kolumny (X=", col_baseplate_x0, ")"));
bms_box            = [140, 90, 60];
driver_box         = [120, 80, 50];

// ---------------------------------------------------------------------------
// 8.  MASY I SRODEK MASY  -  NIEZNANE. NIE ZGADYWAC.
// ---------------------------------------------------------------------------
// Dopoki mass_data_known = false, base_stability.scad NIE podaje marginesow
// liczbowych - zwraca TO VERIFY i zamiast tego liczy DOPUSZCZALNA strefe
// srodka masy. To jest czysta geometria polygonu podparcia i nie wymaga
// zadnych mas, wiec jest uczciwym wynikiem juz teraz.
// UWAGA - te siedem wartosci NIE jest juz definiowanych tutaj:
//   mass_data_known, total_robot_mass, arm_mass, arm_payload, arm_reach,
//   com_x, com_y, com_z
// Definiuje je WYLACZNIE base_masses.scad, ktory liczy je z pozycjowanego
// budzetu mas. Nie przywracaj tu placeholderow undef: OpenSCAD wylicza
// zmienna przypisana dwa razy w MIEJSCU PIERWSZEGO przypisania, wiec
// placeholder tutaj kasowal wynik z base_masses.scad i base_stability.scad
// wracalo do TO VERIFY bez zadnego bledu.

// Punkt montazu ramienia wzgledem bazy - wynika z geometrii z_lift.
// KAZDA z wartosci ponizej jest KOPIA tego, co liczy ../z_lift/parameters.scad.
// Nie zmieniaj ich na oko - uruchom:  python control/check_interface.py
// Skrypt pyta z_lift o kazda z nich i konczy bledem przy rozjezdzie.
arm_mount_x        = 177;   // = y_arm_face - base_plate_cy
arm_mount_z_low    = 307;   // najnizsza pozycja plyty ramienia
arm_mount_z_high   = 881;   // najwyzsza
dual_arm_dy        = 145;   // rozstaw dwoch ramion w Y

stability_margin_req = 100; // mm, wymagany zapas rzutu CoM do krawedzi
                            // polygonu. Wartosc projektowa, nie norma.

// ---------------------------------------------------------------------------
// 9.  PROG I NIEROWNOSCI
// ---------------------------------------------------------------------------
threshold_h        = 20;    // typowy prog domowy                  [MEASURE]
threshold_h_max    = 35;    // przypadek trudny

// ---------------------------------------------------------------------------
// 10. KOLORY
// ---------------------------------------------------------------------------
col_profile = [0.55, 0.56, 0.60];
col_cnc     = [0.75, 0.77, 0.79];
// Czesci DRUKOWANE zamiast metalowych - lekko cieplejszy odcien niz oslony,
// zeby na renderze bylo widac, co wychodzi z drukarki, a co z zamowienia.
// Ktore i dlaczego: print_vs_metal.py
col_print   = [0.93, 0.91, 0.86];
col_wheel   = [0.16, 0.16, 0.18];
col_caster  = [0.30, 0.31, 0.34];
col_batt    = [0.20, 0.42, 0.62];
col_elec    = [0.15, 0.45, 0.35];
col_keepout = [0.90, 0.30, 0.10];
col_skirt   = [0.95, 0.95, 0.94];
col_poly    = [0.10, 0.55, 0.85];
col_warn    = [0.90, 0.35, 0.10];

// OpenSCAD 2021 drops colours on export, so viz/export.py exports a two-colour
// part once per colour. "" draws everything - what every other caller wants.
viz_only = "";
function viz(tag) = viz_only == "" || viz_only == tag;

// ###########################################################################
// ###  GEOMETRIA POCHODNA                                                 ###
// ###########################################################################
half_l = base_length / 2;
half_w = base_width / 2;

battery_x0 = battery_x - battery_l / 2;
battery_x1 = battery_x + battery_l / 2;
// Zajeta przestrzen pakietu Z PRZEWODAMI - to ona, a nie sama bryla ogniw,
// musi omijac strefe napedu kolumny.
battery_zone_x1 = battery_cable_side == "front"
                  ? battery_x1 + battery_cable_zone : battery_x1;
battery_zone_x0 = battery_cable_side == "rear"
                  ? battery_x0 - battery_cable_zone : battery_x0;

keepout_x0 = column_motor_x - keepout_w / 2;
keepout_x1 = column_motor_x + keepout_w / 2;

// luz miedzy strefa napedu kolumny a bateria (z przewodami)
column_battery_gap_x = keepout_x0 - battery_zone_x1;
column_battery_gap_z = keepout_safe_z - battery_top_z;

// Poprzeczki 4040 przecinaja plaszczyzne, przez ktora schodzi naped kolumny.
// Zadna nie moze wejsc w keepout silnika. Az do 2026-08-18 nikt tego nie
// sprawdzal i poprzeczka na X=120 siedziala w nim na 39.5 x 40 mm.
function cross_hits_motor(cx) =
    let (x0 = cx - profile_cross/2, x1 = cx + profile_cross/2,
         k0 = column_motor_x - keepout_w/2, k1 = column_motor_x + keepout_w/2)
    (min(k1, x1) - max(k0, x0) > 0)
    && (min(base_deck_height, frame_top_z) - max(keepout_bot_z,
         frame_top_z - profile_cross) > 0);

cross_in_motor = [for (cx = cross_x) if (cross_hits_motor(cx)) cx];

// Zadne dwie poprzeczki nie moga na siebie nachodzic.
cross_overlaps = [for (i = [0 : len(cross_x) - 2])
                  if (cross_x[i + 1] - cross_x[i] < profile_cross)
                  [cross_x[i], cross_x[i + 1]]];
assert(len(cross_overlaps) == 0,
       str("poprzeczki nachodza na siebie: ", cross_overlaps));

// kola napedowe
wheel_y     = wheel_track / 2;
wheel_out_y = wheel_y + wheel_width / 2;

// Uchwyt kola (2026-10-07, zamiast plyty-zastepnika): gniazdo jak w ramie
// hoverboardu, ORYGINALNE strzemie i dwa giete wieszaki do dolnego rowka
// belki. Gniazdo lezy na plasku osi, na jego zewnetrznym koncu - blizej
// silnika, krotsza dzwignia. Wieszaki stoja tylko poza obrysem pakietu
// i przed licem silnika - z boku belki nic nie zejdzie, tam jest silnik.
seat_len      = 40;     // wzdluz osi (38.8 / 40.0)                      [MEASURE]
seat_w        = 47.7;   // w poprzek osi                                 [MEASURE]
seat_h        = 16;     // pod osia: rowek R 8.1 + 7.9 materialu
seat_pitch    = [29.5, 22.9];   // gwinty strzemienia: w poprzek, wzdluz [MEASURE +/-1]
seat_top_z    = wheel_radius;   // podkladki na wysokosci osi   [MEASURE glebokosc rowka]
seat_y1       = wheel_y - axle_flat_from - 2;   // 139, 2 mm przed koncem plaska
seat_y0       = seat_y1 - seat_len;             // 99
strap_in_w    = 18.5;   // wnetrze kanalu strzemienia (Lyczko0 2026-10-07)
// Wieszak po drive_hanger.py (2026-10-07): JEDNA gieta czesc na kolo -
// scianki po bokach gniazda, plyta pod cala belka, noga w gore po
// wewnetrznym licu belki. Pierwsza wersja (stopki na 1 x M6 w dolnym rowku)
// wyrywala nakretke 4x: dolne lico 40 mm ma jeden rowek, ramie ~20 mm.
hanger_t      = 6;      // blacha PCBWay
hanger_y0     = 100;    // scianki od Y 100: pakiet +/-95, para M5 co 23 mm
hanger_leg_top = frame_top_z - profile_cross - 4;   // 196, pod katownikami poprzeczki X 0
hanger_leg_bolts_x  = [-25, -10, 10, 25];   // 4 x M6, dolny rowek lica belki (Z 180)
hanger_base_bolts_x = [-15, 15];            // 2 x M6, rowek spodu belki


// przejscie przez drzwi
door_margin = (doorway_clear_min - max(base_width, 2 * wheel_out_y)) / 2;

// Sila pozioma potrzebna do wjazdu na prog, jako krotnosc obciazenia kola.
// F/W = tan(acos((R-h)/R)). Klasyczna zaleznosc dla sztywnego kola i
// ostrej krawedzi - gorna oszacowanie, realne progi sa zaokraglone.
function threshold_angle(R, h) = acos((R - h) / R);
function threshold_force_ratio(R, h) = (h >= R) ? 1e9 : tan(threshold_angle(R, h));

// ###########################################################################
// ###  ASERCJE - konfiguracje fizycznie niemozliwe zatrzymuja render      ###
// ###########################################################################
assert(wheel_out_y <= half_w,
       "kola napedowe wystaja poza obrys bazy - zmniejsz wheel_track");
assert(battery_top_z + 5 <= frame_top_z - profile_cross,
       "pakiet wchodzi w poprzeczki - obniz go albo zmniejsz battery_h");
assert(battery_w / 2 + cradle_t + 5 <= main_beam_y - profile_main_w / 2,
       "pakiet z kolyska nie miesci sie miedzy belkami");
assert(battery_w / 2 + 3 <= seat_y0,
       "pakiet wchodzi nad gniazda osi - wezszy pakiet albo gniazdo dalej");

assert(frame_bottom_z > 0, "rama ponizej podlogi");
assert(battery_zone_x0 >= -half_l - 0.001,
       "pakiet z przewodami wystaje poza tyl ramy - wydluz base_length albo przesun battery_x");

module base_report() {
    echo("======================================================");
    echo("  MOBILE BASE V1 - KONCEPT - geometria pochodna (mm)");
    echo("======================================================");
    echo(str("  obrys                     : ", base_length, " x ", base_width));
    echo(str("  wysokosc pokladu          : ", base_deck_height,
             "   przeswit ", ground_clearance));
    echo(str("  kola napedowe             : D", wheel_diameter,
             "  rozstaw ", wheel_track, "  os X=", drive_axle_x));
    echo(str("  szerokosc z kolami        : ", 2 * wheel_out_y));
    echo(str("  zapas na strone, drzwi ", doorway_clear_min, " : ", door_margin));
    echo("------------------------------------------------------");
    echo("  STREFA BEZPIECZENSTWA NAPEDU KOLUMNY Z");
    echo(str("  os silnika kolumny        : X=", column_motor_x, " Y=", column_y));
    echo(str("  keep-out                  : X ", keepout_x0, "..", keepout_x1,
             "   Z ", keepout_bot_z, "..", keepout_top_z));
    echo(str("  dolna granica z zapasem   : Z ", keepout_safe_z,
             "  (wymagany luz ", column_clear_req, ")"));
    echo(str("  bateria                   : X ", battery_x0, "..", battery_x1,
             "   Z ", battery_z, "..", battery_top_z));
    echo(str("  strefa przewodow          : X ", battery_zone_x0, "..",
             battery_zone_x1, "  (wyjscie: ", battery_cable_side, ")"));
    echo(str("  LUZ w X (bateria->naped)  : ", column_battery_gap_x));
    echo(str("  LUZ w Z (bateria->naped)  : ", column_battery_gap_z));
    if (len(cross_in_motor) > 0)
        echo(str("WARNING: poprzeczka 4040 na X=", cross_in_motor,
                 " wchodzi w keepout napedu kolumny (X ",
                 column_motor_x - keepout_w/2, "..",
                 column_motor_x + keepout_w/2,
                 "). Przesun ja poza ten zakres albo usun."));
    else
        echo("  OK: zadna poprzeczka nie wchodzi w keepout napedu kolumny");
    if (column_battery_gap_x >= column_clear_req)
        echo(str("  OK: pakiet omija strefe napedu w plaszczyznie XY o ",
                 column_battery_gap_x, " mm"));
    else if (column_battery_gap_z >= column_clear_req)
        echo(str("  OK: pakiet jest nizej niz strefa napedu o ",
                 column_battery_gap_z, " mm"));
    else
        echo(str("  BLAD: naped kolumny koliduje z bateria. Brakuje ",
                 column_clear_req - max(column_battery_gap_x, column_battery_gap_z),
                 " mm. Przesun battery_x albo obniz pakiet."));
    echo("------------------------------------------------------");
    echo("  PROG (sila pozioma / obciazenie kola)");
    echo(str("  prog ", threshold_h, " mm, kolo napedowe D", wheel_diameter,
             " : ", threshold_force_ratio(wheel_radius, threshold_h)));
    echo(str("  prog ", threshold_h, " mm, caster D", caster_diameter,
             "        : ", threshold_force_ratio(caster_diameter / 2, threshold_h)));
    echo(str("  prog ", threshold_h_max, " mm, caster D", caster_diameter,
             "        : ", threshold_force_ratio(caster_diameter / 2, threshold_h_max)));
    echo("  -> caster zawsze jest ograniczeniem, nie kolo napedowe");
    if (door_margin < doorway_margin_req)
        echo(str("  UWAGA: zapas w drzwiach ", door_margin,
                 " mm < wymagane ", doorway_margin_req));
    echo("  KONCEPT. Zaden wymiar nie jest finalny. MEASURE_BEFORE_CNC.md");
    echo("======================================================");
}

// ###########################################################################
// ###  BASE_FINAL_APPEARANCE_CONCEPT_V1                                   ###
// ###  Wariant A zatwierdzony. Ponizej tylko to, co dochodzi na etapie    ###
// ###  wygladu i oslon. Nic tu nie zmienia zatwierdzonej architektury.    ###
// ###########################################################################

// --- podatnosc casterow glownych (warunek 1 rekomendacji) ------------------
// Caster musi miec pionowa podatnosc, inaczej 4 sztywne punkty zawsze
// odciazaja jeden z nich. Skok wchodzi do keepout: oslona musi miec zapas
// nad casterem podniesionym do gory, nie tylko nad stojacym.
caster_travel      = 12;    // pionowy skok podatnosci             [MEASURE]
caster_spring_d    = 30;    // srednica wkladu sprezystego
caster_top_z       = caster_diameter / 2 + caster_diameter * 0.63
                     + caster_plate_thk;               // ~147

// --- anti-tip BOCZNE (warunek 2 rekomendacji) -----------------------------
// Nie z tylu jak w wariancie C, tylko z boku - slaboscia wariantu A jest
// stabilnosc boczna. X przesuniete do przodu, bo tam idzie obciazenie od
// ramienia, i zeby wyjsc poza obrys kola napedowego.
antitip_side_x     = 170;
antitip_side_y     = 250;

// --- oslony ---------------------------------------------------------------
cover_thk          = 3;     // scianka PETG/ASA                   ESTIMATE
// Zebra pionowe - KOPIE z z_lift, pilnowane przez check_interface.py.
// 6 x 3 co 24 mm to +14 % filamentu; 9 x 4.5 co 21 kosztowalo +36 %.
col_flute_w        = 6;
col_flute_d        = 3;
col_flute_pitch    = 24;
col_flute_band     = 0.42;  // ulamek lica zajety przez pasmo zeber
cover_gap          = 6;     // luz od KAZDEJ obwiedni ruchomej
cover_bottom_z     = 70;    // dol oslon bocznych - NIE obniza przeswitu
cover_top_z        = base_deck_height;
vent_slot_w        = 4;
vent_slot_len      = 45;
vent_pitch         = 9;
boss_d             = 7;     // boss pod insert heat-set M3
boss_insert_d      = 4.2;
boss_h             = 8;

// --- obwiednie ruchome (keepout) ------------------------------------------
// Kolo napedowe: pelny walec, bo oslona ma byc poza CALYM obrysem kola.
wheel_keep_r       = wheel_radius + cover_gap;
wheel_keep_w       = wheel_width + 2 * cover_gap;
// Caster: pelny obrot 360 stopni wokol osi skretu + skok podatnosci.
caster_pivot_dx    = caster_swivel_off;
caster_sweep_r     = caster_swivel_off + caster_diameter / 2 + cover_gap;
caster_front_pivot = caster_front_x - caster_pivot_dx;   // 205, warianty B i C
caster_rear_pivot  = caster_rear_x  + caster_pivot_dx;   // -205
// Kolo omni: walec kola + luz, i skok podatnosci w gore.
omni_keep_r        = omni_d / 2 + cover_gap;
omni_keep_w        = omni_w + 2 * cover_gap;
// Najdalszy punkt podparcia w X, z przodu i z tylu. Bumpery musza byc ZA nim.
front_keep_max_x   = omni_x + omni_keep_r;
caster_sweep_min_x = caster_rear_pivot - caster_sweep_r;

// --- panele: pozycje wynikaja z obwiedni, nie z gustu ---------------------
// Przod i tyl osobno: do 2026-10-03 tyl byl lustrem przodu, co przy omni z
// przodu wydluzyloby robota z obu stron.
cover_front_x      = front_keep_max_x + 2;        // LICO WEWNETRZNE bumpera
cover_rear_x       = caster_sweep_min_x - 2;
cover_side_y       = wheel_out_y + cover_gap;     // LICO WEWNETRZNE boku
cover_corner_r     = 26;                          // promien naroza bumpera
// Sciecie gornej krawedzi korpusu. Zero materialu wiecej, a to ono robi
// z pudla korpus maszyny - sama faktura na plaskim boku tego nie zalatwia.
// Panel gorny G musi sie o tyle skurczyc, inaczej wystaje nad sciecie.
cover_chamfer_h    = 32;    // wysokosc sciecia
cover_chamfer_in   = 14;    // o tyle lico wchodzi do srodka na gorze
                            // 32/14 zamiast 30/22 - lagodniej, 24 stopnie
                            // od pionu zamiast 36. Zaakceptowane 2026-08-19.
// Lico ZEWNETRZNE skorupy - stad zaczynaja sie strefy dostepu serwisowego.
shell_front_x      = cover_front_x + 2 * cover_corner_r;
shell_rear_x       = cover_rear_x - 2 * cover_corner_r;
shell_side_y       = cover_side_y + cover_thk;
// Miekki zderzak przodu: walce na narozach, o tyle przed skorupa.
bumper_off         = 4;
bumper_r           = 12;

// --- mocowanie oslon: M4 od zewnatrz (Lyczko0 2026-10-03) ----------------
// Przod i tyl: rura przez cala skorupe do wkladki w drukowanej plycie
// koncowej ramy. Boki: drukowany wspornik pod belka, w jej dolnym rowku,
// wkladka w jego czole. Miejsca omijaja port ladowania, bezpiecznik, napis,
// pas LED, balast, kolo, anti-tip i kratki - pilnuja testy check_covers.
end_plate_thk      = 10;
// Y 130: 6.4 mm scianki do M6 belek w plycie koncowej, 36 mm od strefy
// portu ladowania (Y 95). Z 200 to najwyzej: sciecie gornej krawedzi
// zaczyna sie na 208, a rura ma promien 5.
cover_screw_y      = 130;
cover_screw_z      = [170, 200];   // w plycie koncowej, Z 160..240
cover_tube_d       = 10;
cover_screw_hole   = 4.5;          // M4 przelotowo
insert_m4_d        = 5.6;          // otwor pod wkladke heat-set M4    [VERIFY]
insert_m4_l        = 8;
// Z przodu jeden: kratki boku zajmuja X 208..252, a wspornik na 290 mial
// srube 2 mm od konca belki i zachodzil na sasiada na 262 (licznik bryl
// w viz/export.py, 2026-10-03). Srodek odpada przez kolo i jego wyjmowanie.
side_bracket_x     = [-275, -150, 270];
side_bracket_w     = 30;           // X
side_bracket_h     = 20;           // Z, pod belka
side_bracket_dx    = 8;            // 2 x M5 w dolny rowek belki, +/- od srodka
side_screw_z       = frame_bottom_z - side_bracket_h / 2;
robot_len_total    = shell_front_x - shell_rear_x + 2 * 16;  // + zderzak
// Boki koncza sie przed bumperami, inaczej panele wchodza w siebie.
cover_side_x_end   = cover_front_x - 4;
cover_side_x_rear  = cover_rear_x + 4;
// Przepusty kablowe w panelu gornym - poza sciana obudowy elektroniki.
cable_pass_y       = 200;
// Obudowa elektroniki - wspolne dla panelu I i otworu w panelu G.
elec_box_w         = 300;
// Obudowa NIE MOZE byc glebsza niz plyta, na ktorej stoi. Bylo 200 przy
// plycie 140 - pudlo zwisalo po 30 mm z kazdej strony i wchodzilo 22 mm
// w pas plyty bazowej kolumny (X od -150). Zaden test tego nie lapal, bo
// keepout "column" to obwiednia NAPEDU, nie plyta. Wyszlo dopiero, gdy
// cokol J stanal na krawedzi plyty i zderzyl sie z pudlem.
elec_box_d         = elec_plate_l;
elec_box_h         = 90;

// --- sterowanie i zlacza --------------------------------------------------
estop_d            = 22.5;
estop_access_d     = 95;                // strefa reki nad grzybkiem
                                        // MUSI byc przed estop_pos - OpenSCAD
                                        // czyta plik po kolei
// X WYPROWADZONY, nie wpisany. Strefa reki ma 95 mm srednicy i przy X=195
// siegala 147.5, czyli 5.5 mm w scianke cokolu J - zlapane jako J vs estop.
// E-stop jest elementem bezpieczenstwa, wiec to on dyktuje, a nie kosmetyka:
// os musi stac o promien strefy plus zapas za licem cokolu.
estop_pos          = [col_baseplate_d / 2 + cover_thk + estop_access_d / 2 + 3,
                      175];                 // na panelu gornym, przod-lewo
mainsw_d           = 19;
mainsw_pos         = [-205, 0];         // prawy bok, blizej tylu (Y=-)
charger_d          = 25;
charger_pos        = [0, 95];           // panel tylny
fuse_d             = 30;
fuse_pos           = [-150, 0];         // panel tylny serwisowy
usb_panel          = [70, 26];          // lewy bok
usb_pos            = [-90, 0];
led_strip          = [220, 10];         // front
access_depth       = 130;               // glebokosc strefy dostepu serwisowego

// --- kolumna Z jako PROXY WIZUALNY ----------------------------------------
// To NIE jest model z ../z_lift, tylko uproszczony obrys o tych samych
// wymiarach zewnetrznych, przeliczonych do ukladu bazy:
//   chassis_X = lift_Y + 75,  chassis_Y = -lift_X,  chassis_Z = lift_Z + 250
// Wnetrze kolumny bylo juz zweryfikowane w ../z_lift - tu chodzi o wyglad.
// Kregoslup kolumny: DWA PROFILE 40x80 na sztorc, nie plyta z podkladkami.
// Zmienione 2026-08-18 razem z ../z_lift. Proxy rysowalo stara plyte jeszcze
// dlugo po przebudowie - renderingi pokazywaly nieistniejaca konstrukcje.
col_backbone_x     = 45;    // lico TYLNE profili = zlift Y 0 w ukladzie bazy
col_profile_d      = 80;    // glebokosc profilu w X (zlift Y)
col_profile_w      = 40;    // szerokosc profilu w Y
col_backbone_w     = 300;   // rozpietosc zewnetrzna = rail_spacing + 40
col_backbone_top   = 1090;  // = base_deck_height 240 + backbone_z0 10 + 840
col_rail_y         = 130;   // +/- Y osi prowadnic = osi profili
col_tie_thk        = 6;     // plyta spinajaca u gory
col_plate_x        = 165;   // lico przednie plyty ruchomej.
                            // WYPROWADZENIE: z_lift y_plate_front = 120,
                            // mapowanie base_x = zlift_Y + 45  ->  165.
                            // BYLO 160 - dryf o 5 mm, obecny takze przed
                            // przebudowa kregoslupa. Sprawdz przy kazdej
                            // zmianie lancucha Y w ../z_lift/parameters.scad.
// Sylwetka drukowanej osłony kolumny. KOPIE z z_lift - eksportowane przez
// interface_report(), pilnowane przez check_interface.py. Proxy zgadywało je
// wcześniej i przez to render pokazywał dwa gole slupy, choc kolumna miala
// oslony od dawna.
col_pan_x          = 189;   // +/- Y lica wewnetrznego skorupy bocznej
col_pan_front      = 106;   // przod skorupy, w zlift Y
col_cap_rear       = -7;    // tyl czapki, w zlift Y
col_cap_front      = 110;   // przod czapki - 4 mm okapu dookola
col_panel_thk      = 3;
col_panel_seg      = 4;     // na tyle czesci dzieli sie skorupa boczna
col_panel_gap      = 2;     // widoczna szczelina miedzy segmentami
col_dbox_y0        = -195;  // tyl skrzynki sterownika, w zlift Y
col_dbox_d         = 95;
col_dbox_w         = 300;
col_dbox_h         = 150;

col_plate_w        = 440;
col_plate_h        = 220;
col_carriage_low   = 377;   // = base_deck_height 240 + carriage_z_min 137
col_carriage_high  = 951;   // = 240 + carriage_z_max 711.25
carriage_z         = col_carriage_low;   // pozycja do renderu
arm_face_x         = 177;
arm_proxy_reach    = 480;   // PLACEHOLDER, nie wymiar PAR6      [MEASURE]
show_arm           = 1;     // 0 = brak, 1 = jedno, 2 = dwa
show_covers        = true;
show_keepouts      = false;

// --- serwis baterii -------------------------------------------------------
// Bateria wysuwa sie DO TYLU. Objetosc wysuwu to keepout dla panelu tylnego:
// panel musi byc zdejmowany, a nie w drodze.
battery_service_len = battery_l + 60;
