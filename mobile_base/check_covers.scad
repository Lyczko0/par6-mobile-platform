// ############################################################################
//  check_covers.scad  -  keepout checks dla BASE_FINAL_APPEARANCE_CONCEPT_V1
//
//  Kazdy test to PRZECIECIE oslon z jedna obwiednia. Pusty wynik = PASS.
//
//  Uruchamianie pojedynczo:
//    openscad -o out.stl --export-format=asciistl -D 'test="A_vs_wheel"' \
//             check_covers.scad
//  Calosc: ./check_covers.sh
//
//  Harness detekcji PASS jest przeniesiony 1:1 z ../z_lift/check_collisions.sh
//  - OpenSCAD nie zapisuje pliku i konczy sie kodem 1 przy pustym wyniku,
//  wiec ani brak pliku, ani kod 1 nie moga same oznaczac bledu. Ta logika
//  juz raz zostala zrobiona poprawnie, nie ma powodu pisac jej drugi raz.
//
//  CZEGO TO NIE SPRAWDZA
//    Wytrzymalosci, sztywnosci, drukowalnosci, chlodzenia (poza polem
//    otworow), ani dynamiki. To sa testy geometryczne.
// ############################################################################

include <main_base.scad>

test            = "list";
render_assembly = false;
show_keepouts   = false;

// ---------------------------------------------------------------------------
//  pojedyncze oslony pod testy
// ---------------------------------------------------------------------------
module cover(id) {
    if (id == "A") cover_A_front();
    if (id == "B") cover_B_rear();
    if (id == "C") cover_side(1);
    if (id == "D") cover_side(-1);
    if (id == "E") cover_E_low();
    if (id == "F") cover_F_arch();
    if (id == "G") cover_G_top();
    if (id == "H") cover_H_caster();
    if (id == "I") cover_I_elec();
    if (id == "J") cover_J_collar();
    if (id == "K") side_brackets();      // nie oslona, ale ten sam test
}

// podloga ponizej zadanego przeswitu - nic z oslon nie moze tu wejsc
module keep_ground_clearance() {
    translate([-500, -400, -10]) cube([1000, 800, ground_clearance + 10]);
}

// dostep do kola napedowego przy demontazu - kolo wyjmuje sie w bok
module keep_wheel_removal() {
    for (s = [-1, 1])
        translate([drive_axle_x, s * (wheel_y + wheel_width / 2), wheel_radius])
            rotate([90 * s, 0, 0])
                cylinder(r = wheel_keep_r, h = 200);
}

// ---------------------------------------------------------------------------
//  TESTY: oslona vs obwiednia
// ---------------------------------------------------------------------------
COVERS = ["A", "B", "C", "D", "E", "F", "G", "I", "J", "K"];  // H wypadl - patrz base_covers.scad

module run(id, what) {
    intersection() {
        cover(id);
        if (what == "wheel")     keep_wheels();
        if (what == "caster")    keep_casters();
        if (what == "antitip")   keep_antitip();
        if (what == "column")    keep_column_drive();
        if (what == "battery")   keep_battery_service();
        if (what == "cable")     keep_cable_bend();
        if (what == "ground")    keep_ground_clearance();
        if (what == "wheelout")  keep_wheel_removal();
        if (what == "estop")     access_estop();
        if (what == "charger")   access_charger();
        if (what == "fuse")      access_fuse();
        if (what == "mainsw")    access_mainsw();
        if (what == "ballast")   keep_ballast();
        if (what == "axle")      keep_axles();
    }
}

// Dwa osobne parametry zamiast parsowania nazwy testu - OpenSCAD nie ma
// sensownej obslugi stringow, a shell i tak petli po obu listach.
cover_id = "";
keep_id  = "";
// A misspelt id draws nothing, and nothing intersected is a PASS - the
// shell's lists must name things this file knows.
KEEPS = ["wheel", "caster", "antitip", "column", "battery", "cable", "ground",
         "wheelout", "estop", "charger", "fuse", "mainsw", "ballast", "axle"];
assert(cover_id == "" || len([for (c = COVERS) if (c == cover_id) 1]) == 1,
       str("unknown cover_id ", cover_id));
assert(keep_id == "" || len([for (k = KEEPS) if (k == keep_id) 1]) == 1,
       str("unknown keep_id ", keep_id));
if (cover_id != "" && keep_id != "") run(cover_id, keep_id);

// oslony nie moga wchodzic w siebie nawzajem
if (test == "covers_vs_covers")
    for (i = [0 : len(COVERS) - 1], j = [0 : len(COVERS) - 1])
        if (i < j) intersection() { cover(COVERS[i]); cover(COVERS[j]); }

// ---------------------------------------------------------------------------
//  TESTY ARCHITEKTURY (nie oslon) - obwiednia zamiatania castera kontra
//  bryly, ktore i tak tam sa. Wyszlo przy okazji oslon.
// ---------------------------------------------------------------------------
if (test == "caster_vs_battery")
    intersection() { keep_casters(); battery_pack(); }
if (test == "caster_vs_cradle")
    intersection() { keep_casters(); battery_cradle(); }
if (test == "caster_vs_cable")
    intersection() { keep_casters(); keep_battery_cables(); }
if (test == "cable_vs_column")
    intersection() { keep_battery_cables(); keep_column_drive(); }

// Balast siedzi na belkach z tyla, gdzie sa tez: zamiatanie tylnego castera,
// wysuw baterii przy serwisie, plyta koncowa i - blizej srodka - uchwyty kol.
// Z pokryciem przez oslony sprawdza go macierz wyzej (kolumna "ballast").
if (test == "ballast_vs_caster")
    intersection() { keep_ballast(); keep_casters(); }
if (test == "ballast_vs_wheels")
    intersection() { keep_ballast(); keep_wheels(); }
if (test == "ballast_vs_battery")
    intersection() { keep_ballast(); keep_battery_service(); }
if (test == "ballast_vs_drive")
    intersection() { keep_ballast(); for (s = [-1, 1]) drive_mount(s); }
if (test == "ballast_vs_endplate")
    intersection() { keep_ballast(); end_plate(-half_l); }
// Uchwyt kola: stara wersja przechodzila przez belke glowna i nie dotykala
// osi - nic tego nie parowalo. Os ma przechodzic przez otwor BEZ kolizji
// (to sprawdza drive_vs_axle), a plyta ma lezec na licu belki (styk).
// Mocowanie oslon M4 (2026-10-03): kazda para MUSI sie stykac - w
// check_covers.sh brak styku to FAIL, nie PASS. Kontrole negatywne:
//   brackets_vs_frame   -D 'side_bracket_x=[340]'      (za koncem belki)
//   brackets_vs_covers  -D 'side_bracket_x=[0]'        (w otworze na kolo)
//   tubes_vs_endplates  -D 'cover_screw_z=[300, 320]'  (nad plyta)
if (test == "brackets_vs_frame")
    intersection() { side_brackets(); base_frame("A"); }
if (test == "brackets_vs_covers")
    intersection() { side_brackets(); union() { cover_side(1); cover_side(-1); } }
if (test == "tubes_vs_endplates")
    intersection() { union() { cover_A_front(); cover_B_rear(); }
                     union() { end_plate(half_l); end_plate(-half_l); } }
if (test == "drive_vs_frame")
    intersection() { for (s = [-1, 1]) drive_mount(s); base_frame("A"); }
if (test == "drive_vs_covers")
    intersection() {
        for (s = [-1, 1]) drive_mount(s);
        union() { for (c = COVERS) cover(c); }
    }
if (test == "drive_vs_wheels")
    intersection() { for (s = [-1, 1]) drive_mount(s); keep_wheels(); }
if (test == "drive_vs_axle")
    intersection() { for (s = [-1, 1]) drive_mount(s); keep_axles(); }
// Os jest dwa razy dluzsza, niz model zakladal do 2026-10-07 - jej czolo
// z przewodami lezy POD pakietem (stad pakiet nad osiami). Kontrole negatywne:
//   axle_vs_battery   -D 'battery_z=95'       (pakiet opuszczony na czola osi)
//   drive_vs_battery  -D 'battery_z=100' -D 'hanger_y0=90'  (wieszak w pakiecie;
//                     szerszy pakiet lapie wczesniej assert w base_parameters)
//   cradle_vs_frame   -D 'cradle_x=[-400]'    (kolyska za koncem belek - wisi)
if (test == "axle_vs_battery")
    intersection() { keep_axles(); battery_pack(); }
if (test == "axle_vs_cradle")
    intersection() { keep_axles(); battery_cradle(); }
if (test == "drive_vs_battery")
    intersection() { for (s = [-1, 1]) drive_mount(s); battery_pack(); }
if (test == "drive_vs_cradle")
    intersection() { for (s = [-1, 1]) drive_mount(s); battery_cradle(); }
if (test == "battery_vs_frame")
    intersection() { battery_pack(); base_frame("A"); }
if (test == "cradle_vs_frame")
    intersection() { battery_cradle(); base_frame("A"); }
if (test == "axle_vs_cable")
    intersection() { keep_axles(); keep_battery_cables(); }
if (test == "axle_vs_frame")
    intersection() { keep_axles(); base_frame("A"); }
if (test == "axle_vs_elec")
    intersection() { keep_axles(); electronics_plate(); }
if (test == "axle_vs_column")
    intersection() { keep_axles(); keep_column_drive(); }
if (test == "axle_vs_ballast")
    intersection() { keep_axles(); keep_ballast(); }
if (test == "ballast_vs_elec")
    intersection() { keep_ballast(); electronics_plate(); }

// ---------------------------------------------------------------------------
//  RAPORT LICZBOWY - to, czego przeciecie bryl nie powie
// ---------------------------------------------------------------------------
if (test == "list") {
    echo("==========================================================");
    echo("  BASE_FINAL_APPEARANCE_CONCEPT_V1 - dane liczbowe");
    echo("==========================================================");
    echo(str("  dlugosc calkowita z bumperem : ", robot_len_total,
             "  (rama ", base_length, ")"));
    echo(str("  szerokosc calkowita          : ", 2 * (cover_side_y + cover_thk),
             "  (korpus ", base_width, ")"));
    echo(str("  wysokosc z kolumna           : ", col_backbone_top + 8));
    echo("----------------------------------------------------------");
    echo("  OBWIEDNIE RUCHOME");
    echo(str("  kolo napedowe  : R ", wheel_keep_r, " szer ", wheel_keep_w,
             "  w Y +/-", wheel_out_y));
    echo(str("  kolo omni, przod : R ", omni_keep_r, " szer ", omni_keep_w,
             "  na X ", omni_x, "  (zasieg do X ", front_keep_max_x, ")"));
    echo(str("  caster 360 deg, tyl : R ", caster_sweep_r, " wokol X ",
             caster_rear_pivot, "  (zasieg do X ", caster_sweep_min_x, ")"));
    echo(str("  skok podatnosci podparcia    : ", caster_travel, " mm"));
    echo(str("  lico wewn. bumpera przod/tyl : X ", cover_front_x, " / ",
             cover_rear_x, "  = obrys podparcia + 2"));
    echo(str("  lico wewn. boku              : Y +/-", cover_side_y,
             "  = kolo ", wheel_out_y, " + luz ", cover_gap));
    echo("----------------------------------------------------------");
    echo("  ANTI-TIP BOCZNE");
    echo(str("  pozycja        : X ", antitip_side_x, "  Y +/-", antitip_side_y));
    echo(str("  luz do podlogi : ", antitip_gap,
             " mm  -> nie przenosi ciezaru w pozycji statycznej"));
    echo(str("  odleglosc w X od obrysu kola : ",
             antitip_side_x - antitip_d / 2 - wheel_radius));
    echo("----------------------------------------------------------");
    echo("  PRZESWIT");
    echo(str("  zadany przeswit              : ", ground_clearance));
    echo(str("  dol oslon bocznych           : ", cover_bottom_z));
    echo(str("  dol oslon niskich E          : ",
             max(ground_clearance + 8, cover_bottom_z - 28), "  (nigdy < przeswit)"));
    echo("----------------------------------------------------------");
    echo("  STREFA NAPEDU KOLUMNY (z ../z_lift)");
    echo(str("  luz do baterii w X           : ", column_battery_gap_x,
             "  wymagane ", column_clear_req));
    echo("==========================================================");
}
