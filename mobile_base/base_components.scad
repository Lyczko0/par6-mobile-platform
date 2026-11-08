// ############################################################################
//  base_components.scad  -  czesci kupowane i czesci CNC bazy mobilnej
//
//  KONWENCJA
//    * Czesci kupowane (profil, kolo, caster, bateria) rysowane w LOKALNYM
//      ukladzie, ustawiane przez wywolujacego.
//    * Czesci CNC rysowane wprost w ukladzie GLOBALNYM bazy.
//    * Wszystko uproszczone do obwiedni i interfejsow montazowych. Rowki
//      T-slot, lozyska, uszczelnienia i fazy nie sa modelowane.
//
//  ZADNA z tych czesci nie jest gotowa do CNC. To koncept do oceny ukladu.
// ############################################################################

include <base_masses.scad>

// ---------------------------------------------------------------------------
//  pomocnicze
// ---------------------------------------------------------------------------
module slot2d(len, d) {
    hull() for (s = [-1, 1]) translate([s * (len - d) / 2, 0]) circle(d = d);
}

module slot(len, d, h) {
    linear_extrude(h, center = true) slot2d(len, d);
}

// ---------------------------------------------------------------------------
//  profil aluminiowy, os wzdluz X
//  LOKALNIE: X = dlugosc (wysrodkowana), Y = szerokosc, Z = wysokosc
// ---------------------------------------------------------------------------
module alu_profile(len, w, h) {
    color(col_profile)
    difference() {
        translate([-len / 2, -w / 2, -h / 2]) cube([len, w, h]);
        // uproszczone rowki T-slot na czterech bokach
        for (s = [-1, 1]) {
            translate([-len / 2 - 1, s * w / 2, 0])
                rotate([0, 90, 0]) cylinder(d = profile_slot, h = len + 2);
            translate([-len / 2 - 1, 0, s * h / 2])
                rotate([0, 90, 0]) cylinder(d = profile_slot, h = len + 2);
        }
        // rowek dodatkowy dla profilu 80 mm (dwa kanaly w pionie)
        if (h >= 80)
            for (s = [-1, 1], t = [-1, 1])
                translate([-len / 2 - 1, s * w / 2, t * h / 4])
                    rotate([0, 90, 0]) cylinder(d = profile_slot, h = len + 2);
    }
}

// profil o osi wzdluz Y
module alu_profile_y(len, w, h) {
    rotate([0, 0, 90]) alu_profile(len, w, h);
}

// profil o osi wzdluz Z - kolumna. Ten sam modul co rama, zeby kolumna
// WYGLADALA jak profil, a nie jak plaskownik. Proxy rysowalo goly szescian
// i kregoslup czytal sie jak dwie dlugie sztaby zamiast dwoch profili.
// len = wysokosc (Z), w = szerokosc w Y, h = glebokosc w X.
// rotate([0,90,0]) przenosi lokalne X -> globalne Z, wiec dlugosc profilu
// staje sie pionem, a jego przekroj zostaje w Y/X bez zamiany.
module alu_profile_z(len, w, h) {
    rotate([0, 90, 0]) alu_profile(len, w, h);
}

// ---------------------------------------------------------------------------
//  kolo napedowe 8.5 cala (hub motor)
//  LOKALNIE: os obrotu wzdluz Y, srodek w osi kola
// ---------------------------------------------------------------------------
module hub_wheel(s = 1) {
    rotate([90, 0, 0]) {
        if (viz("tire"))
            color(col_wheel) cylinder(d = wheel_diameter, h = wheel_width, center = true);
    }
    // obudowa silnika: od zewnatrz w oponie, od srodka do lica hub_face_in
    if (viz("hub")) {
        color([0.72, 0.73, 0.75]) mirror([0, s > 0 ? 0 : 1, 0]) rotate([90, 0, 0])
            translate([0, 0, -82 / 2]) cylinder(d = wheel_hub_d, h = 82 / 2 + hub_face_in);
        color([0.8, 0.8, 0.82]) hub_axle(s);
    }
}

// Os piasty z przewodami, s = strona kola (+1 = Y+). Jednostronna: od srodka
// opony DO SRODKA robota. Walec do axle_flat_from, dalej plask na gorze do
// czola - strzemie dociska go od gory. Przewody wychodza z czola i ida
// prosto axle_cable_l, zanim sie zegna - to ich strefa.
module hub_axle(s) {
    mirror([0, s > 0 ? 0 : 1, 0]) rotate([90, 0, 0]) {
        cylinder(d = axle_d, h = axle_flat_from + 1);
        translate([0, 0, axle_flat_from]) linear_extrude(axle_end - axle_flat_from)
            intersection() {
                circle(d = axle_d);
                translate([-axle_d, -axle_d]) square([2 * axle_d, axle_d / 2 + axle_flat]);
            }
        translate([0, 0, axle_end - 1]) cylinder(d = 10, h = axle_cable_l + 1);
    }
}

// ---------------------------------------------------------------------------
//  kolo omni, przod wariantu A: os wzdluz Y, dwa rzedy rolek
//  LOKALNIE: Z = 0 na PODLODZE, srodek kola nad poczatkiem ukladu.
//  Bez uchwytu - podatny uchwyt nie istnieje (BOM_V1.md sekcja 11).
// ---------------------------------------------------------------------------
module omni_wheel() {
    color(col_caster)
    translate([0, 0, omni_d / 2]) rotate([90, 0, 0]) {
        for (s = [-1, 1])
            translate([0, 0, s * omni_w / 4])
                cylinder(d = omni_d, h = omni_w / 2 - 2, center = true);
        cylinder(d = omni_d * 0.45, h = omni_w, center = true);   // piasta
        cylinder(d = 12, h = omni_w + 30, center = true);          // os
    }
}

// ---------------------------------------------------------------------------
//  caster skretny
//  LOKALNIE: Z = 0 na PODLODZE, plyta montazowa na gorze
// ---------------------------------------------------------------------------
module caster(d = caster_diameter, plate = true) {
    r = d / 2;
    color(col_caster) {
        translate([0, 0, r]) rotate([90, 0, 0])
            cylinder(d = d, h = caster_width, center = true);
        // widelec
        for (s = [-1, 1])
            translate([-caster_swivel_off, s * (caster_width / 2 + 3), r])
                cube([d * 0.5, 6, d * 0.55], center = true);
        // trzpien obrotowy
        translate([-caster_swivel_off, 0, r + d * 0.28])
            cylinder(d = 26, h = d * 0.35);
    }
    if (plate)
        color(col_cnc)
        translate([-caster_swivel_off, 0, r + d * 0.28 + d * 0.35])
            linear_extrude(caster_plate_thk)
                difference() {
                    square([70, 70], center = true);
                    for (x = [-1, 1], y = [-1, 1])
                        translate([x * 25, y * 25]) circle(d = 6.6);
                }
}

// kolko anti-tip - male, sztywne, z zadanym luzem nad podloga
module antitip_wheel() {
    color(col_warn) {
        translate([0, 0, antitip_gap + antitip_d / 2]) rotate([90, 0, 0])
            cylinder(d = antitip_d, h = 25, center = true);
        translate([0, 0, antitip_gap + antitip_d / 2 + antitip_d * 0.3])
            cube([40, 34, antitip_d * 0.6], center = true);
    }
}

// ---------------------------------------------------------------------------
//  bateria + taca
// ---------------------------------------------------------------------------
module battery_pack() {
    color(col_batt)
        translate([battery_x0, battery_y - battery_w / 2, battery_z])
            cube([battery_l, battery_w, battery_h]);
    // strefa przewodow - to NIE jest bryla pakietu, to zajeta przestrzen
    %color([0.9, 0.7, 0.2, 0.35])
        translate([battery_x1, battery_y - 50, battery_z + battery_h * 0.4])
            cube([battery_cable_zone, 100, battery_h * 0.6]);
}

// Kolyski pakietu (2026-10-07, zamiast wanny na dnie). Pakiet wisi nad
// osiami napedu: dwie kolyski z blachy 3 mm, dno pod pakietem, nogi na
// wewnetrznych licach belek (2 x M6 w rowki Z 180 i 220), pas z gory.
// Wyjmowanie: W DOL, po zdjeciu obu kol - czola osi leza pod pakietem.
module battery_cradle() {
    yi = main_beam_y - profile_main_w / 2;          // 117.5, lico wewn. belki
    for (cx = cradle_x) {
        if (viz("cradle")) color(col_cnc) difference() {
            union() {
                translate([cx - cradle_w / 2, -yi, battery_z - cradle_t])
                    cube([cradle_w, 2 * yi, cradle_t]);
                for (s = [-1, 1])
                    translate([cx - cradle_w / 2, s > 0 ? yi - cradle_t : -yi,
                               battery_z - cradle_t])
                        cube([cradle_w, cradle_t, frame_top_z - 10 - (battery_z - cradle_t)]);
            }
            for (s = [-1, 1], z = [frame_bottom_z + 20, frame_top_z - 20])
                translate([cx, s * yi, z]) rotate([90, 0, 0])
                    cylinder(d = 6.6, h = 3 * cradle_t, center = true);
        }
        if (viz("batt_strap")) color([0.12, 0.12, 0.12])
            translate([cx - 12.5, -yi + cradle_t, battery_top_z])
                cube([25, 2 * (yi - cradle_t), 1.5]);
    }
}

// Uchwyt kola napedowego (2026-10-07). Gniazdo jak w ramie hoverboardu,
// oryginalne strzemie, dwa giete wieszaki w dolny rowek belki. Trzy czesci,
// kazda pod wlasnym tagiem viz() - w Fusion maja sie dac rozebrac.
// Poprzednik, plyta 160 x 150 x 10 na boku belki, stal w obudowie silnika:
// silnik od srodka siega lica 69 mm od srodka opony, a nie 46.
// Pary: drive_vs_frame (styk ze spodem belki), drive_vs_axle (os w rowku,
// strzemie na plasku), drive_vs_battery, drive_vs_cradle.
module drive_mount(s) {
    assert(seat_y0 >= wheel_y - axle_end + 2, "gniazdo wychodzi za czolo osi");
    assert(seat_y1 <= wheel_y - axle_flat_from, "gniazdo zachodzi na walcowa czesc osi");
    assert(main_beam_y + profile_main_w / 2 < wheel_y - hub_face_in,
           "wieszak wchodzi w obudowe silnika");
    assert(seat_top_z - seat_h >= ground_clearance, "gniazdo ponizej przeswitu");
    mirror([0, s > 0 ? 0 : 1, 0]) {
        if (viz("seat"))   color(col_cnc) drive_seat();
        if (viz("strap"))  color([0.55, 0.56, 0.58]) drive_strap();
        if (viz("hanger")) color(col_cnc) drive_hangers();
    }
}

// Blok gniazda: polokragly rowek pod os 16, 4 gwinty strzemienia, po 2 M5
// z bokow na wieszaki. Rysowany dla strony Y+.
module drive_seat() {
    yc = (seat_y0 + seat_y1) / 2;
    difference() {
        translate([drive_axle_x - seat_w / 2, seat_y0, seat_top_z - seat_h])
            cube([seat_w, seat_len, seat_h]);
        translate([drive_axle_x, seat_y0 - 1, wheel_radius]) rotate([-90, 0, 0])
            cylinder(r = axle_d / 2 + 0.1, h = seat_len + 2);
        for (i = [-1, 1], j = [-1, 1])
            translate([drive_axle_x + i * seat_pitch[0] / 2, yc + j * seat_pitch[1] / 2,
                       seat_top_z - 12])
                cylinder(d = 5, h = 13);                   // gwint [MEASURE]
        for (i = [-1, 1], y = [hanger_y0 + 8, seat_y1 - 8])
            translate([drive_axle_x + i * seat_w / 2, y, seat_top_z - seat_h / 2])
                rotate([0, 90, 0]) cylinder(d = 4.2, h = 20, center = true);
    }
}

// Oryginalne strzemie (omega): stopki na podkladkach, dach na plasku osi.
module drive_strap() {
    yc = (seat_y0 + seat_y1) / 2;
    difference() {
        translate([0, seat_y1, 0]) rotate([90, 0, 0]) linear_extrude(seat_len)
            translate([drive_axle_x, 0]) {
                for (m = [0, 1]) mirror([m, 0]) {
                    translate([strap_in_w / 2, seat_top_z])
                        square([seat_w / 2 - strap_in_w / 2, strap_t]);
                    translate([strap_in_w / 2, seat_top_z])
                        square([strap_t, axle_flat_z + strap_t - seat_top_z]);
                }
                translate([-strap_in_w / 2 - strap_t, axle_flat_z])
                    square([strap_in_w + 2 * strap_t, strap_t]);
            }
        for (i = [-1, 1], j = [-1, 1])
            translate([drive_axle_x + i * seat_pitch[0] / 2, yc + j * seat_pitch[1] / 2,
                       seat_top_z - 1])
                cylinder(d = 6.5, h = strap_t + 2);
    }
}

// Wieszak: JEDNA gieta czesc na kolo (po drive_hanger.py, 2026-10-07) -
// dwie scianki po bokach gniazda, plyta pod cala belka i noga w gore po
// wewnetrznym licu belki, 4 x M6 w jego dolnym rowku (Z 180), 2 x M6 w rowku
// spodu. Moment kola trzyma para: docisk zewnetrznej krawedzi plyty o spod
// belki i sruby nogi na scinanie, ramie ~43 mm. Noga konczy sie pod
// katownikami poprzeczki X 0 (gorny rowek lica, Z 220).
module drive_hangers() {
    y1 = main_beam_y + profile_main_w / 2 - 0.5;   // przed licem silnika
    yi = main_beam_y - profile_main_w / 2;         // lico wewnetrzne belki
    zb = seat_top_z - seat_h;
    xw = seat_w / 2 + hanger_t;
    difference() {
        union() {
            for (i = [-1, 1])
                translate([drive_axle_x + (i > 0 ? seat_w / 2 : -xw), hanger_y0, zb])
                    cube([hanger_t, y1 - hanger_y0, frame_bottom_z - zb]);
            translate([drive_axle_x - xw, yi, frame_bottom_z - hanger_t])
                cube([2 * xw, y1 - yi, hanger_t]);
            translate([drive_axle_x - xw, yi - hanger_t, frame_bottom_z - hanger_t])
                cube([2 * xw, hanger_t, hanger_leg_top - frame_bottom_z + hanger_t]);
        }
        for (i = [-1, 1], y = [hanger_y0 + 8, seat_y1 - 8])
            translate([drive_axle_x + i * (seat_w / 2 + hanger_t / 2), y, seat_top_z - seat_h / 2])
                rotate([0, 90, 0]) cylinder(d = 5.5, h = hanger_t + 2, center = true);
        for (x = hanger_leg_bolts_x)
            translate([drive_axle_x + x, yi - hanger_t / 2, frame_bottom_z + 20])
                rotate([90, 0, 0]) cylinder(d = 6.6, h = hanger_t + 2, center = true);
        for (x = hanger_base_bolts_x)
            translate([drive_axle_x + x, main_beam_y, frame_bottom_z - hanger_t - 1])
                cylinder(d = 6.6, h = hanger_t + 2);
    }
}

// ---------------------------------------------------------------------------
//  CNC: uchwyt castera. Plaska plyta pod plyte skretnego, przykrecona
//  od spodu do belek glownych. 6 mm - caster niesie ~15 kg pionowo,
//  sruby przelotowe, zero gwintow.
// ---------------------------------------------------------------------------
module caster_mount(x, y) {
    w = 110; t = 6;
    color(col_cnc)
    difference() {
        translate([x - w / 2, y - w / 2, frame_bottom_z - t])
            cube([w, w, t]);
        for (i = [-1, 1], j = [-1, 1])
            translate([x + i * 35, y + j * 35, frame_bottom_z - t - 1])
                cylinder(d = 8.5, h = t + 2);
        translate([x, y, frame_bottom_z - t - 1]) cylinder(d = 40, h = t + 2);
    }
}

// ---------------------------------------------------------------------------
//  BALAST: plaskowniki stalowe na licach belek, tyl. KUPIONE, nie wyciete -
//  patrz base_parameters.scad 4b. Dwa M8 po przekatnej, po jednym w kazdy
//  z dwoch rowkow lica 80 mm (Z 180 i 220), zeby plaskownik nie obracal sie
//  na jednej srubie.
// ---------------------------------------------------------------------------
module ballast_bars() {
    color([0.33, 0.34, 0.36])
    for (s = [-1, 1])
        difference() {
            translate([ballast_x1, s > 0 ? ballast_y_in : -ballast_y_out,
                       frame_bottom_z])
                cube([ballast_bar_l, ballast_y_out - ballast_y_in, ballast_bar_h]);
            for (k = [-1, 1])
                translate([ballast_cx + k * 50, s * (ballast_y_in - 1),
                           ballast_cz + k * 20])
                    rotate([-s * 90, 0, 0])
                        cylinder(d = 9, h = ballast_y_out - ballast_y_in + 2);
        }
}

// ---------------------------------------------------------------------------
module electronics_plate() {
    color(col_print)   // DRUK, nie metal - print_vs_metal.py
    difference() {
        translate([elec_plate_x - elec_plate_l / 2, -elec_plate_w / 2, frame_top_z])
            cube([elec_plate_l, elec_plate_w, elec_plate_thk]);
        // M6 into the top slot of each main beam. The old +/-100 x +/-120
        // pattern was left over from a longer plate: it lay outside the
        // 140 mm plate and bolted it to nothing.
        for (i = [-1, 1], j = [-1, 1])
            translate([elec_plate_x + i * 50, j * main_beam_y, frame_top_z - 1])
                cylinder(d = 6.6, h = elec_plate_thk + 2);
        // wentylacja / przepusty - ACROSS the plate. Laid along it, the five
        // slots ran into one 340 mm slot and cut the plate in two (found by
        // viz/export.py 2026-09-25); three fit in 140 mm at the old pitch.
        for (i = [-1 : 1])
            translate([elec_plate_x + i * 45, 0, frame_top_z - 1])
                rotate(90) linear_extrude(elec_plate_thk + 2) slot2d(160, 12);
    }
}

// ---------------------------------------------------------------------------
//  CNC: plyta koncowa ramy (przod / tyl)
// ---------------------------------------------------------------------------
module end_plate(x) {
    o = sign(x);
    color(col_print)   // DRUK, nie metal - print_vs_metal.py
    difference() {
        translate([x - end_plate_thk / 2, -(main_beam_y + profile_main_w / 2),
                   frame_bottom_z]) cube([end_plate_thk, 2 * (main_beam_y + profile_main_w / 2),
                                          profile_main_h]);
        // wkladki M4 pod sruby oslony A / B, od lica zewnetrznego
        for (s = [-1, 1], z = cover_screw_z)
            translate([x + o * (end_plate_thk / 2 + 1), s * cover_screw_y, z])
                rotate([0, -o * 90, 0]) cylinder(d = insert_m4_d, h = insert_m4_l + 1);
        for (s = [-1, 1], z = [-1, 1])
            translate([x - 6, s * main_beam_y, frame_bottom_z + profile_main_h / 2 + z * 20])
                rotate([0, 90, 0]) cylinder(d = 6.6, h = 12);
        // 120 along Y, 40 in Z. It stood 120 tall in an 80 mm plate and cut
        // the plate in two - caught by viz/export.py's body count 2026-09-25.
        translate([x - 6, 0, frame_bottom_z + profile_main_h / 2])
            rotate([0, 90, 0]) rotate([0, 0, 90]) linear_extrude(12) slot2d(120, 40);
    }
}

// ---------------------------------------------------------------------------
//  elektronika - bryly zastepcze
// ---------------------------------------------------------------------------
// Bryly zastepcze MUSZA miescic sie w obudowie I (elec_box_d x elec_box_w),
// inaczej wystaja przez jej sciane - bylo widac na renderze.
module electronics_boxes() {
    z = frame_top_z + elec_plate_thk;
    color(col_elec) {
        // Tylko 140 mm glebokosci w X, wiec skrzynki stoja OBOK SIEBIE W Y,
        // nie jedna za druga. Y ma 300 mm i to tam jest miejsce.
        translate([elec_plate_x - bms_box[0] / 2, 55, z]) cube(bms_box);
        translate([elec_plate_x - driver_box[0] / 2, -45, z]) cube(driver_box);
        translate([elec_plate_x - driver_box[0] / 2, -145, z]) cube(driver_box);
    }
}

// ---------------------------------------------------------------------------
//  strefa keep-out napedu kolumny Z
//  Czerwona bryla = obwiednia instalacyjna silnika z hamulcem.
//  Przezroczysta obwodka pod nia = wymagany luz column_clear_req.
// ---------------------------------------------------------------------------
module column_keepout() {
    color(col_keepout, 0.45)
        translate([column_motor_x, column_y, (keepout_bot_z + keepout_top_z) / 2])
            cube([keepout_w, keepout_w, column_motor_inst], center = true);
    color(col_keepout, 0.15)
        translate([column_motor_x, column_y, (keepout_safe_z + keepout_bot_z) / 2])
            cube([keepout_w + 10, keepout_w + 10, column_clear_req], center = true);
}

// obrys kolumny Z dla kontekstu - NIE jest czescia tego projektu
module zlift_ghost() {
    %translate([column_x - 75, 0, base_deck_height])
        cube([300, 420, 20], center = true);
    %translate([column_x - 70, 0, base_deck_height + 435])
        cube([10, 380, 850], center = true);
}

// ---------------------------------------------------------------------------
//  estetyczne oslony boczne (ALOHA-style: szerokie, niskie, gladkie)
//  Niekonstrukcyjne. Druk 3D lub giete blachy.
// ---------------------------------------------------------------------------
module side_skirts() {
    for (s = [-1, 1])
        color(col_skirt)
        difference() {
            translate([-half_l, s * (half_w - 3), ground_clearance + 10])
                cube([base_length, 3, frame_top_z - ground_clearance - 10]);
            // wyciecie na kolo napedowe
            translate([drive_axle_x, s * half_w, wheel_radius])
                rotate([90, 0, 0])
                    cylinder(d = wheel_diameter + 30, h = 20, center = true);
        }
}
