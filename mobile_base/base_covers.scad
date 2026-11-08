// ############################################################################
//  base_covers.scad  -  BASE_FINAL_APPEARANCE_CONCEPT_V1
//
//  Modulowe oslony PETG/ASA + strefy keepout + strefy dostepu serwisowego
//  + wizualne proxy kolumny Z i ramion.
//
//  ZASADA NADRZEDNA: zadna oslona nie przenosi obciazenia. Zadna nie jest
//  elementem konstrukcyjnym. Wszystkie sa zdejmowane, wszystkie na M3/M4
//  w inserty heat-set, wszystkie srubami od strony serwisowej.
//
//  Pozycje paneli NIE sa dobrane na oko - wynikaja z obwiedni ruchomych
//  (cover_front_x, cover_side_y, cover_side_x_end w base_parameters.scad).
//  Zmiana kola albo castera automatycznie przesuwa panele.
//
//  Wszystkie kolizje sprawdza check_covers.sh - macierz paneli x 12 stref.
// ############################################################################

// base_stability.scad wciaga base_variants -> base_components -> parameters.
// Musi byc TU, bo main_base.scad wlacza juz tylko ten plik.
include <base_stability.scad>

// PRAWDZIWY PAR6 z oficjalnego URDF Source Robotics + adapter kolumna->PAR6.
include <../par6_ref/par6_adapter.scad>
// UWAGA: OpenSCAD rozwiazuje sciezki import() wzgledem pliku TOP-LEVEL, a nie
// wzgledem pliku z importem. Dlatego katalog meshy trzeba nadpisac stad.
par6_mesh_dir = "../par6_ref/meshes/";

col_white  = [0.96, 0.96, 0.95];
col_accent = [0.16, 0.17, 0.19];   // grafit
col_keep   = [0.90, 0.25, 0.10];
col_access = [0.15, 0.55, 0.85];

// ---------------------------------------------------------------------------
//  pomocnicze
// ---------------------------------------------------------------------------
module boss(h = boss_h) {
    difference() {
        cylinder(d = boss_d, h = h);
        translate([0, 0, -0.5]) cylinder(d = boss_insert_d, h = h);
    }
}

// Rury srub M4 przez skorupe A albo B: od lica plyty koncowej ramy do lica
// zewnetrznego skorupy. Sruba wchodzi od zewnatrz w wkladke w plycie.
// Zastapily 8 tulei, ktore w skorupie wisialy w powietrzu (2026-10-03).
module cover_tubes(xa, xb, hole = false) {
    for (s = [-1, 1], z = cover_screw_z)
        translate([min(xa, xb) - (hole ? 1 : 0), s * cover_screw_y, z])
            rotate([0, 90, 0])
                cylinder(d = hole ? cover_screw_hole : cover_tube_d,
                         h = abs(xb - xa) + (hole ? 2 : 0));
}

module vents(n, len = vent_slot_len, w = vent_slot_w, pitch = vent_pitch, h = 20) {
    for (i = [0 : n - 1])
        translate([0, (i - (n - 1) / 2) * pitch, -h / 2])
            linear_extrude(h) slot2d(len, w);
}

// ###########################################################################
//  KEEPOUT - obwiednie, w ktore zadna oslona nie moze wejsc
// ###########################################################################

// pelny obrys kola napedowego
// Os piasty z przewodami, prawdziwa dlugosc od 2026-10-07 (139 mm do srodka).
module keep_axles() {
    for (s = [-1, 1])
        translate([drive_axle_x, s * wheel_y, wheel_radius]) hub_axle(s);
}

module keep_wheels() {
    for (s = [-1, 1])
        translate([drive_axle_x, s * wheel_y, wheel_radius])
            rotate([90, 0, 0])
                cylinder(r = wheel_keep_r, h = wheel_keep_w, center = true);
}

// Podparcie wariantu A: tylny caster - pelny obrot 360 stopni + skok
// podatnosci w gore; przednie kolo omni - tylko jego walec, podniesiony o
// ten sam skok (nie skreca, wiec nie zamiata).
module keep_casters() {
    translate([caster_rear_pivot, 0, -1])
        cylinder(r = caster_sweep_r, h = caster_top_z + caster_travel + cover_gap);
    hull() for (dz = [0, caster_travel])
        translate([omni_x, 0, omni_d / 2 + dz]) rotate([90, 0, 0])
            cylinder(r = omni_keep_r, h = omni_keep_w, center = true);
}

// Kolko anti-tip to TARCZA w plaszczyznie XZ (os wzdluz Y), a nie slup.
// Modelowanie go jako pionowego walca R46 wymuszalo w oslonie bocznej dziure
// 116 mm szerokosci - bylo ja widac na renderze jako okno na wylot.
module keep_antitip() {
    for (s = [-1, 1])
        translate([antitip_side_x, s * antitip_side_y, 0]) {
            translate([0, 0, antitip_gap + antitip_d / 2]) rotate([90, 0, 0])
                cylinder(r = antitip_d / 2 + cover_gap,
                         h = 22 + 2 * cover_gap, center = true);
            translate([0, 0, antitip_gap + antitip_d / 2 + antitip_d * 0.3])
                cube([40 + 2 * cover_gap, 34 + 2 * cover_gap,
                      antitip_d * 0.6 + 2 * cover_gap], center = true);
        }
}

// strefa napedu kolumny Z - 20 mm luzu, przeniesiona z ../z_lift
// Do 2026-10-07 kostka stala ROGIEM w osi silnika (center = false przy
// translate do srodka) - testy widzialy cwiartke strefy, X 105..214 zamiast
// 50.5..159.5. Teraz wysrodkowana jak keepout_x0/x1 w base_parameters.
module keep_column_drive() {
    e = keepout_w / 2 + column_clear_req;
    translate([column_motor_x - e, column_y - e, keepout_safe_z])
        cube([2 * e, 2 * e, base_deck_height - keepout_safe_z]);
}

// Serwis pakietu od 2026-10-07: wisi nad osiami napedu, wiec wychodzi W DOL,
// po zdjeciu obu kol (czola osi leza pod nim) i odkreceniu kolysek. Korytarz
// to obrys pakietu od jego spodu do podlogi. Do 2026-10-07: wysuw do tylu.
module keep_battery_service() {
    translate([battery_x0 - 3, -battery_w / 2 - 3, 0])
        cube([battery_l + 6, battery_w + 6, battery_z]);
}

// Promien giecia liczy sie TAM, gdzie przewod wychodzi - lokalnie przy
// przepuscie, nie na calej szerokosci pokladu, i dopiero OD GORY kolnierza
// odciazenia, bo dopiero tam przewod zaczyna sie giac.
cable_bend_r = 35;   // min. promien giecia wiazki               [MEASURE]
// Strefa przewodow przy scianie pakietu - osobny modul, zeby testy
// architektury zderzaly ja z casterem i napedem kolumny bez kopiowania
// geometrii. Kopia to kolejne miejsce na rozjazd.
module keep_battery_cables() {
    z0 = battery_z + 20;
    translate([battery_zone_x0, -60, z0])
        cube([battery_cable_zone, 120, min(80, frame_top_z - profile_cross - 1 - z0)]);
}

module keep_cable_bend() {
    keep_battery_cables();
    for (s = [-1, 1])
        translate([column_x - 105, s * cable_pass_y,
                   base_deck_height + cover_thk + 10])
            cylinder(r = cable_bend_r, h = cable_bend_r + 20);
}

// balast na licach belek + lby M8 z podkladka, ktore wystaja na zewnatrz.
// Statyczny, wiec bez cover_gap - to nie jest nic, co sie rusza.
module keep_ballast() {
    for (s = [-1, 1])
        translate([ballast_x1,
                   s > 0 ? ballast_y_in : -(ballast_y_out + ballast_head_clr),
                   frame_bottom_z])
            cube([ballast_bar_l,
                  ballast_y_out - ballast_y_in + ballast_head_clr,
                  ballast_bar_h]);
}

module keep_all() {
    color(col_keep, 0.30) {
        keep_wheels(); keep_casters(); keep_antitip();
        keep_column_drive(); keep_battery_service(); keep_cable_bend();
        keep_ballast();
    }
}

// ###########################################################################
//  STREFY DOSTEPU
//  Zaczynaja sie na LICU ZEWNETRZNYM skorupy i ida NA ZEWNATRZ. Gdyby
//  przechodzily przez panel, kazdy test bylby FAIL tylko dlatego, ze panel
//  istnieje - a pytanie brzmi "czy cos zaslania reke", nie "czy jest otwor".
// ###########################################################################
module access_estop() {
    translate([estop_pos[0], estop_pos[1], base_deck_height + cover_thk + 1])
        cylinder(d = estop_access_d, h = access_depth);
}
module access_charger() {
    translate([shell_rear_x - 1, charger_pos[1], charger_pos[0] + 150])
        rotate([0, -90, 0]) cylinder(d = charger_d + 45, h = access_depth);
}
module access_fuse() {
    translate([shell_rear_x - 1, fuse_pos[1], fuse_pos[0] + 300])
        rotate([0, -90, 0]) cylinder(d = fuse_d + 45, h = access_depth);
}
module access_mainsw() {
    translate([mainsw_pos[0], -shell_side_y - 1, mainsw_pos[1] + 170])
        rotate([90, 0, 0]) cylinder(d = mainsw_d + 45, h = access_depth);
}
module access_all() {
    color(col_access, 0.30) {
        access_estop(); access_charger(); access_fuse(); access_mainsw();
    }
}

// ###########################################################################
//  PANELE  A .. I
// ###########################################################################

// --- A. przedni bumper / panel przedni -------------------------------------
// Srodki hulla przesuniete o promien naroza, zeby LICO WEWNETRZNE wypadlo
// dokladnie na cover_front_x. Inaczej skorupa wchodzi w obrys kola omni.
// Zebra pionowe na plaskim licu. Rosna NA ZEWNATRZ - do srodka jest
// wszystko, co osłona ma zakryc. Zapas w drzwiach to 70 mm na strone przy
// wymaganych 40, wiec 3 mm sie miesci.
module flutes_x(x0, x1, y, ydir, z0, z1) {
    for (x = [(x0 + x1)/2 - (x1 - x0)*col_flute_band/2
              : col_flute_pitch
              : (x0 + x1)/2 + (x1 - x0)*col_flute_band/2 - col_flute_w])
        translate([x, ydir > 0 ? y : y - col_flute_d, z0])
            cube([col_flute_w, col_flute_d, z1 - z0]);
}

// Skorupa "stadionowa" przodu i tylu, ze scieciem gornej krawedzi. Bez tego
// sciecie urywalo sie na bokach i narozniki zostawaly proste - widac to bylo
// od razu na renderze jako uskok.
// Wciecie naroza nie moze zjesc calego promienia, stad min().
module stadium_shell(x0, r, zb, zt) {
    ci  = min(cover_chamfer_in, r - 6);
    ch  = cover_chamfer_h;
    t   = cover_thk;
    module ring(rad, dy, z, h) {
        hull() for (s = [-1, 1])
            translate([x0, s * (cover_side_y - r - dy), z])
                cylinder(r = rad, h = h);
    }
    difference() {
        union() {
            ring(r, 0, zb, zt - zb - ch);
            hull() { ring(r, 0, zt - ch, 0.01); ring(r - ci, 0, zt - 0.01, 0.01); }
        }
        union() {
            ring(r - t, t, zb - 1, zt - zb - ch + 1);
            hull() { ring(r - t, t, zt - ch, 0.01);
                     ring(max(r - ci - t, 0.5), t, zt + 1, 0.01); }
        }
    }
}

// Wszystko, co siedzi pod scieciem gornej krawedzi, musi sie w nim zmiescic.
// Nadkole F stalo pionowo do Z 228, a sciecie zaczyna sie na 210 - zlapane
// jako oslona-vs-oslona, 122 x 12 x 17 mm. Zamiast zmniejszac sciecie,
// przycinam nadkole do jego plaszczyzny. Ta sama bryla przyda sie kazdemu
// nastepnemu panelowi w tym naroznniku.
module chamfer_keepout(s) {
    yi = cover_side_y;
    zt = cover_top_z;
    ch = cover_chamfer_h;
    ci = cover_chamfer_in;
    translate([-2000, 0, 0]) rotate([90, 0, 90]) linear_extrude(4000)
        polygon([[s*yi, zt - ch], [s*(yi - ci), zt],
                 [s*(yi - ci), zt + 60], [s*(yi + 300), zt + 60],
                 [s*(yi + 300), zt - ch]]);
}

module cover_A_front() {
    x0 = cover_front_x + cover_corner_r;
    r  = cover_corner_r;
    if (viz("white"))
    color(col_white)
    difference() {
        union() {
            stadium_shell(x0, r, cover_bottom_z, cover_top_z);
            cover_tubes(half_l + end_plate_thk / 2, shell_front_x);
        }
        cover_tubes(half_l + end_plate_thk / 2, shell_front_x, hole = true);
        // pas LED stanu
        translate([x0 + 20, 0, cover_bottom_z + 40]) rotate([0, 90, 0])
            linear_extrude(40, center = true) slot2d(led_strip[0], led_strip[1]);
        // plytki napis - opcjonalny
        translate([x0 + 20, 0, cover_top_z - 55])
            rotate([0, 90, 0]) rotate([0, 0, 180])
                linear_extrude(4, center = true)
                    text("PAROL-MB", size = 26, halign = "center",
                         valign = "center");
    }
    // miekki zderzak - chroni meble, wymienny
    if (viz("accent"))
    color(col_accent)
        hull() for (s = [-1, 1])
            translate([shell_front_x + bumper_off, s * (cover_side_y - r),
                       cover_bottom_z + 12])
                cylinder(r = bumper_r, h = 26);
}

// --- B. tylny panel serwisowy baterii --------------------------------------
// Zdejmowany w calosci -> bateria wysuwa sie do tylu BEZ demontazu kolumny.
module cover_B_rear() {
    x0 = cover_rear_x - cover_corner_r;
    r  = cover_corner_r;
    color(col_white)
    difference() {
        union() {
            stadium_shell(x0, r, cover_bottom_z, cover_top_z);
            cover_tubes(-(half_l + end_plate_thk / 2), shell_rear_x);
        }
        cover_tubes(-(half_l + end_plate_thk / 2), shell_rear_x, hole = true);
        // port ladowania
        translate([x0 - 20, charger_pos[1], charger_pos[0] + 150])
            rotate([0, 90, 0]) cylinder(d = charger_d, h = 40);
        // bezpiecznik glowny
        translate([x0 - 20, fuse_pos[1], fuse_pos[0] + 300])
            rotate([0, 90, 0]) cylinder(d = fuse_d, h = 40);
        // wentylacja komory baterii
        translate([x0 - 20, 0, cover_bottom_z + 30]) rotate([0, 90, 0])
            vents(7, 60, vent_slot_w, vent_pitch, 40);
    }
}

// --- C / D. oslony boczne ---------------------------------------------------
// side = +1 lewa (Y+), -1 prawa (Y-)
// Obrys skorupy bocznej w plaszczyznie YZ: pion, potem sciecie do gory.
// local x -> global Y,  local y -> global Z.
function side_profile(s) =
    let (yi = cover_side_y, yo = cover_side_y + cover_thk,
         zb = cover_bottom_z, zt = cover_top_z,
         ch = cover_chamfer_h, ci = cover_chamfer_in)
    [[s*yi, zb], [s*yi, zt - ch], [s*(yi - ci), zt],
     [s*(yo - ci), zt], [s*yo, zt - ch], [s*yo, zb]];

module cover_side(side = 1) {
    y0 = side * cover_side_y;
    color(col_white)
    difference() {
        union() {
            // Skorupa z ustawionym profilem, nie plaski prostopadloscian:
            // gorne 30 mm wchodzi 22 mm do srodka. Profil w plaszczyznie YZ
            // wyciagniety wzdluz X - ten sam chwyt co przy gussetach.
            translate([cover_side_x_rear, 0, 0]) rotate([90, 0, 90])
                linear_extrude(cover_side_x_end - cover_side_x_rear)
                    polygon(side_profile(side));
            flutes_x(cover_side_x_rear, cover_side_x_end,
                     side > 0 ? y0 + cover_thk : y0 - cover_thk, side,
                     cover_bottom_z + 4, cover_top_z - cover_chamfer_h - 6);
        }
        // M4 od zewnatrz we wsporniki pod belka (side_brackets). Zastapily
        // 8 tulei, ktore wisialy 4-25 mm od sciany (2026-10-03).
        for (x = side_bracket_x)
            translate([x, y0, side_screw_z]) rotate([90, 0, 0])
                cylinder(d = cover_screw_hole, h = 3 * cover_thk, center = true);
        // otwor na kolo napedowe - kolo ma byc widoczne i wyjmowalne
        translate([drive_axle_x, y0 + side, wheel_radius]) rotate([90, 0, 0])
            cylinder(r = wheel_keep_r + 4, h = 20, center = true);
        // szczelina tylko na wysiegnik anti-tipa, nie na cala tarcze
        translate([antitip_side_x, y0 + side, cover_bottom_z + 6])
            rotate([90, 0, 0]) linear_extrude(20, center = true)
                square([40 + 2 * cover_gap + 8, 76], center = true);
        // wentylacja
        for (x = [-230, 230])
            translate([x, y0 + side, cover_bottom_z + 60])
                rotate([90, 0, 0]) rotate([0, 0, 90])
                    vents(5, 70, vent_slot_w, vent_pitch, 20);
        // prawy bok: wylacznik glowny
        if (side < 0)
            translate([mainsw_pos[0], y0 + 20, mainsw_pos[1] + 170])
                rotate([90, 0, 0]) cylinder(d = mainsw_d, h = 40);
        // lewy bok: panel USB / serwisowy
        if (side > 0)
            translate([usb_pos[0], y0 - 20, usb_pos[1] + 170])
                rotate([-90, 0, 0]) linear_extrude(40)
                    slot2d(usb_panel[0], usb_panel[1]);
    }
}

// --- E. niskie oslony ramy miedzy kolami ------------------------------------
module cover_E_low() {
    // Dol listwy NIGDY ponizej ground_clearance - to byloby obnizenie
    // przeswitu dla wygladu, czyli dokladnie to, czego nie wolno.
    h  = 22;
    z0 = max(ground_clearance + 8, cover_bottom_z - h - 6);
    // Tyl zaczyna sie za obrysem kola. Przod dodatkowo za anti-tipem.
    x_rear  = wheel_keep_r + 14;
    x_front = antitip_side_x + antitip_d / 2 + cover_gap + 10;
    color(col_accent)
    for (s = [-1, 1], sx = [-1, 1])
        let (x0 = sx > 0 ? x_front : x_rear,
             xl = (sx > 0 ? cover_side_x_end : -cover_side_x_rear) - x0 - 10)
        translate([sx * (x0 + xl / 2), s * (cover_side_y - 2), z0 + h / 2])
            cube([xl, cover_thk, h], center = true);
}

// --- F. nadkola / oslony przeciwbryzgowe ------------------------------------
// Tylko luk NAD kolem. Szerokosc nie moze siegnac lica oslony bocznej.
module cover_F_arch() {
    w = min(wheel_keep_w, 2 * (cover_side_y - wheel_y) - 2);
    color(col_accent)
    for (s = [-1, 1])
        difference() {
            translate([drive_axle_x, s * wheel_y, wheel_radius])
                rotate([90, 0, 0])
                    rotate_extrude(angle = 150)
                        translate([wheel_keep_r + 2, -w / 2])
                            square([cover_thk + 1, w]);
            chamfer_keepout(s);
        }
}

// --- G. gorny panel wokol podstawy kolumny ----------------------------------
module cover_G_top() {
    if (viz("white"))
    color(col_white)
    difference() {
        translate([cover_rear_x + cover_chamfer_in,
                   -cover_side_y + cover_chamfer_in, base_deck_height])
            cube([cover_front_x - cover_rear_x - 2 * cover_chamfer_in,
                  2 * (cover_side_y - cover_chamfer_in), cover_thk]);
        // Otwor pod plyte bazowa kolumny - aluminium zostaje widoczne.
        // Wymiar bierze sie z plyty z_lift (420 x 300), bo plyta montazowa
        // podwozia zostala usunieta 2026-08-18 i to ta plyta siedzi teraz
        // wprost na belkach.
        translate([column_x - col_baseplate_d / 2 - 4,
                   column_y - col_baseplate_w / 2 - 4, base_deck_height - 1])
            cube([col_baseplate_d + 8, col_baseplate_w + 8, cover_thk + 2]);
        // E-stop
        translate([estop_pos[0], estop_pos[1], base_deck_height - 1])
            cylinder(d = estop_d, h = cover_thk + 2);
        // przepusty kablowe - poza sciana obudowy elektroniki
        for (s = [-1, 1])
            translate([column_x - 105, s * cable_pass_y, base_deck_height - 1])
                linear_extrude(cover_thk + 2) slot2d(60, 22);
        // Otwor pod obudowe elektroniki - bez tego plaska plyta przechodzi
        // wprost przez sciany obudowy I.
        translate([elec_plate_x - elec_box_d / 2 - 4, -elec_box_w / 2 - 4,
                   base_deck_height - 1])
            cube([elec_box_d + 8, elec_box_w + 8, cover_thk + 2]);
    }
    // kolnierze odciazenia przewodow
    if (viz("accent"))
    color(col_accent)
    for (s = [-1, 1])
        translate([column_x - 105, s * cable_pass_y, base_deck_height + cover_thk])
            difference() {
                linear_extrude(10) offset(r = 4) slot2d(60, 22);
                translate([0, 0, -1]) linear_extrude(12) slot2d(60, 22);
            }
}

// --- H. oslona modulu castera -----------------------------------------------
// !!! H NIE JEST BUDOWALNY W TEJ ARCHITEKTURZE - patrz BASE_COVERS_CONCEPT.md.
// Trzy niezalezne przeszkody, kazda zmierzona przez check_covers.sh:
//   1. NAD casterem: caster_top_z + skok + luz = 165 > spod ramy 160, wiec
//      kolnierz od gory wychodzi z UJEMNA wysokoscia;
//   2. PIERSCIEN wokol zamiatania: caster_sweep_r + scianka = 106.5, a do lica
//      bumpera jest 105.5 - brakuje 1 mm;
//   3. TYLNY pierscien lezy w korytarzu wysuwu baterii i w strefie przewodow.
// Zeby H istnial, trzeba zmniejszyc obrys zamiatania castera, czyli ruszyc
// zatwierdzona architekture. Nie robie tego dla czesci kosmetycznej.
// Modul zostaje w pliku jako dowod, ale jest POZA covers_all().
module cover_H_caster() {
    r_in = caster_sweep_r + 1;
    color(col_white)
    for (px = [caster_front_pivot, caster_rear_pivot])
        translate([px, 0, cover_bottom_z])
            difference() {
                cylinder(r = r_in + cover_thk, h = frame_bottom_z - cover_bottom_z);
                translate([0, 0, -1])
                    cylinder(r = r_in, h = frame_bottom_z - cover_bottom_z + 2);
                translate([px > 0 ? -(2 * r_in + 40) : 0, -r_in - 20, -1])
                    cube([2 * r_in + 40, 2 * (r_in + 20),
                          frame_bottom_z - cover_bottom_z + 2], center = false);
            }
}

// --- I. obudowa elektroniki z wentylacja -------------------------------------
module cover_I_elec() {
    w = elec_box_w; d = elec_box_d; h = elec_box_h;
    x0 = elec_plate_x - d / 2;
    color(col_white)
    difference() {
        union() {
            translate([x0, -w / 2, frame_top_z + elec_plate_thk])
                difference() {
                    cube([d, w, h]);
                    translate([cover_thk, cover_thk, -1])
                        cube([d - 2 * cover_thk, w - 2 * cover_thk, h]);
                }
            for (sx = [-1, 1], sy = [-1, 1])
                translate([elec_plate_x + sx * (d / 2 - 14), sy * (w / 2 - 14),
                           frame_top_z + elec_plate_thk + h - boss_h]) boss();
        }
        for (sy = [-1, 1])
            translate([elec_plate_x, sy * (w / 2 - cover_thk / 2),
                       frame_top_z + elec_plate_thk + h / 2])
                rotate([90, 0, 0]) vents(6, 110, vent_slot_w, vent_pitch, 20);
        translate([x0 + cover_thk / 2, 0, frame_top_z + elec_plate_thk + 30])
            rotate([0, 90, 0]) linear_extrude(20, center = true) slot2d(90, 26);
    }
}

// ---------------------------------------------------------------------------
//  J - cokol podstawy kolumny
// ---------------------------------------------------------------------------
// Panel G ma w srodku dziure 428 x 308 na plyte bazowa kolumny, i to celowo -
// plyta ma 10 mm i lezy WPROST na belkach, wiec plaski panel nie ma jak jej
// przykryc. Efekt uboczny: na renderze widac gola krawedz plyty, prowadnice
// i lancuch, a kolumna wyrasta z dziury zamiast z czegokolwiek.
//
// To jest obwodka, nie pokrywa. Zakrywa KRAWEDZ plyty i konczy sie 2 mm nad
// nia, wiec nie moze wejsc w nic, co na plycie stoi - a stoi tam wspornik
// BK12, lancuch, skrzynka sterownika i krancowki.
module cover_J_collar() {
    x0 = column_x - col_baseplate_d / 2;
    y0 = -col_baseplate_w / 2;
    w  = cover_thk;
    h  = 10 + 2;                         // grubosc plyty + 2 mm nakladki
    color(col_white)
    difference() {
        translate([x0 - w, y0 - w, base_deck_height])
            cube([col_baseplate_d + 2*w, col_baseplate_w + 2*w, h]);
        translate([x0, y0, base_deck_height - 1])
            cube([col_baseplate_d, col_baseplate_w, h + 2]);
        // Wyciecia na kolnierze odciazenia przewodow z panelu G. Cokol
        // przechodzil przez nie na wylot - zlapane jako oslona-vs-oslona,
        // 60 x 3 x 9 mm. Kolnierz jest funkcjonalny, cokol jest kosmetyczny,
        // wiec ustepuje cokol. Wymiar z kolnierza, nie z oka.
        for (sy = [-1, 1])
            translate([column_x - 105 - 40, sy * col_baseplate_w / 2 - w - 2,
                       base_deck_height - 1])
                cube([80, 2 * w + 4, h + 2]);
    }
}

// Wsporniki oslon bocznych (DRUK): pod belka glowna, 2 x M5 w jej dolny
// rowek, w czole wkladka M4 na srube oslony. Gora styka sie z belka (z tylu
// tez ze spodem balastu), czolo z licem wewnetrznym oslony - testy styku
// w check_covers.sh. Pod belka, bo jej boczne lico zajmuje z tylu balast.
module side_brackets() {
    color(col_print)
    for (s = [-1, 1], x = side_bracket_x)
        difference() {
            translate([x - side_bracket_w / 2,
                       s > 0 ? main_beam_y - 12.5 : -cover_side_y,
                       frame_bottom_z - side_bracket_h])
                cube([side_bracket_w, cover_side_y - main_beam_y + 12.5,
                      side_bracket_h]);
            for (dx = [-1, 1])
                translate([x + dx * side_bracket_dx, s * main_beam_y,
                           frame_bottom_z - side_bracket_h - 1])
                    cylinder(d = 5.5, h = side_bracket_h + 2);
            translate([x, s * (cover_side_y + 1), side_screw_z])
                rotate([s * 90, 0, 0]) cylinder(d = insert_m4_d, h = insert_m4_l + 1);
        }
}

module covers_all() {
    cover_J_collar();
    e = explode;
    translate([ e * 1.6, 0, 0])  cover_A_front();
    translate([-e * 1.6, 0, 0])  cover_B_rear();
    translate([0,  e * 1.4, 0])  cover_side(1);
    translate([0, -e * 1.4, 0])  cover_side(-1);
    side_brackets();
    translate([0,  0, -e * 0.5]) cover_E_low();
    translate([0,  0,  e * 0.8]) cover_F_arch();
    translate([0,  0,  e * 2.2]) cover_G_top();
    // cover_H_caster();  <- nie miesci sie, patrz komentarz przy module
    translate([0,  0,  e * 3.0]) cover_I_elec();
}

// ###########################################################################
//  ANTI-TIP BOCZNE  (warunek 2 rekomendacji wariantu A)
// ###########################################################################
module antitip_side_pair() {
    for (s = [-1, 1])
        translate([antitip_side_x, s * antitip_side_y, 0]) {
            color(col_warn) {
                translate([0, 0, antitip_gap + antitip_d / 2]) rotate([90, 0, 0])
                    cylinder(d = antitip_d, h = 22, center = true);
                translate([0, 0, antitip_gap + antitip_d / 2 + antitip_d * 0.3])
                    cube([40, 34, antitip_d * 0.6], center = true);
            }
            // widoczny luz 8 mm - anti-tip NIE przenosi ciezaru
            %color([1, 0.9, 0.2, 0.5])
                translate([0, 0, antitip_gap / 2])
                    cube([antitip_d, 24, antitip_gap], center = true);
        }
}

// ###########################################################################
//  PROXY WIZUALNE: kolumna Z i ramiona
//  To NIE jest model z ../z_lift. Te same wymiary zewnetrzne, przeliczone do
//  ukladu bazy. Wnetrze kolumny bylo weryfikowane osobno.
// ###########################################################################
// Split in two so viz/ can export the shell apart from the structure: in one
// export CGAL would weld the rear panel to the profile faces it sits on.
module column_proxy(cz = carriage_z) {
    column_structure_proxy(cz);
    column_shell_proxy();
}

module column_structure_proxy(cz = carriage_z) {
    z0 = base_deck_height + 10;          // backbone_z0
    h  = col_backbone_top - z0;

    // dwa profile 40x80 NA SZTORC, po jednym pod kazda prowadnica.
    // alu_profile_z, nie cube - inaczej kregoslup wyglada jak plaskownik.
    for (s = [-1, 1])
        translate([col_backbone_x + col_profile_d / 2, s * col_rail_y, z0 + h / 2])
            alu_profile_z(h, col_profile_w, col_profile_d);

    // prowadnice HGR20 na przednim licu profili
    color([0.80, 0.81, 0.83])
        for (s = [-1, 1])
            translate([col_backbone_x + col_profile_d, s * col_rail_y - 10,
                       base_deck_height + 20])
                cube([17.5, 20, 800]);

    // plyta spinajaca u gory, pod BF12
    color(col_cnc)
        translate([col_backbone_x, -col_backbone_w / 2,
                   col_backbone_top - 65 - col_tie_thk])
            cube([col_profile_d, col_backbone_w, col_tie_thk]);

    // plyta ruchoma wozka
    color(col_cnc)
        translate([col_plate_x - 10, -col_plate_w / 2, cz - col_plate_h / 2])
            cube([10, col_plate_w, col_plate_h]);
}

module column_shell_proxy() {
    // Drukowana skorupa kolumny. Rysowana z wymiarow EKSPORTOWANYCH przez
    // z_lift, nie zgadywanych: dwie skorupy boczne siegajace poza lancuch
    // kablowy, panel tylny zamykajacy plecy i czapka na gorze.
    // Przod zostaje otwarty i to jest celowe - tamtedy jezdzi wozek.
    color(col_white) {
        px = col_pan_x;
        t  = col_panel_thk;
        x0 = col_backbone_x;                    // zlift Y = 0
        h  = col_backbone_top - (base_deck_height + 10);
        z0 = base_deck_height + 10;

        // Skorupy boczne i panel tylny, w segmentach - bo tak sie je drukuje
        // i bo bez szczelin kolumna wygladala jak jednolity kloc.
        seg = h / col_panel_seg;
        for (i = [0 : col_panel_seg - 1]) {
            sz = z0 + i * seg;
            sh = seg - col_panel_gap;
            for (s = [-1, 1])
                difference() {
                    union() {
                        translate([x0, s * px - (s > 0 ? 0 : t), sz])
                            cube([col_pan_front, t, sh]);
                        for (fy = [col_pan_front*(1 - col_flute_band)/2
                                   : col_flute_pitch
                                   : col_pan_front*(1 + col_flute_band)/2 - col_flute_w])
                            translate([x0 + fy,
                                       s * (px + t) - (s > 0 ? 0 : col_flute_d),
                                       sz + 5])
                                cube([col_flute_w, col_flute_d, sh - 10]);
                    }
                    // zaluzje. Wymiary KOSMETYCZNE - nie decyduja o pasowaniu,
                    // wiec swiadomie nie ida przez interface_report().
                    for (v = [0 : 4])
                        translate([x0 + col_pan_front * 0.45 - 20 + v * 10,
                                   s * px - (s > 0 ? 1 : t + 1), sz + sh / 2 - 20])
                            cube([4, t + 2, 40]);
                }
            translate([x0 - t, -px - t, sz]) cube([t, 2 * (px + t), sh]);
            for (fy = [-px*col_flute_band : col_flute_pitch : px*col_flute_band - col_flute_w])
                translate([x0 - t - col_flute_d, fy, sz + 5])
                    cube([col_flute_d, col_flute_w, sh - 10]);
        }

        // czapka
        translate([x0 + col_cap_rear, -px - t, col_backbone_top])
            cube([col_cap_front - col_cap_rear, 2 * (px + t), 8]);

        // Skrzynka sterownika ZA kolumna. Istnieje w z_lift od dawna, ale
        // proxy jej nie rysowalo - i dlatego na renderze za kolumna byla
        // dziura z gola plyta bazowa i lancuchem.
        difference() {
            union() {
                translate([x0 + col_dbox_y0, -col_dbox_w / 2, z0])
                    cube([col_dbox_d, col_dbox_w, col_dbox_h]);
                for (fy = [-col_dbox_w*col_flute_band/2 : col_flute_pitch : col_dbox_w*col_flute_band/2 - col_flute_w])
                    translate([x0 + col_dbox_y0 - col_flute_d, fy, z0 + 8])
                        cube([col_flute_d, col_flute_w, col_dbox_h - 16]);
            }
            for (v = [0 : 4])
                translate([x0 + col_dbox_y0 - 1,
                           -60 + v * 30, z0 + col_dbox_h / 2 - 25])
                    cube([t + 2, 4, 50]);
        }
    }
}

// PAR6 - prawdziwy model z URDF, na adapterze. Lico montazowe kolumny jest
// PIONOWE (normalna +X), wiec adapter obraca sie o 90 st: lokalne +Z -> +X.
// KONSEKWENCJA: os J1 jest POZIOMA, ramie zamiata w plaszczyznie pionowej.
// Patrz odpowiedz - to jest decyzja do potwierdzenia.
// PAR6 na wsporniku, os J1 PIONOWA (jak na blacie). Uklad lokalny wspornika
// jest juz ukladem bazy, wiec tylko przesuniecie na lico montazowe kolumny.
module arm_proxy(y = 0, cz = carriage_z, j = [0, -40, 75, 0, -35, 0]) {
    translate([arm_face_x, y, cz]) par6_with_adapter(j);
}

module arms_proxy(cz = carriage_z) {
    if (show_arm == 1) arm_proxy(0, cz);
    if (show_arm == 2) for (s = [-1, 1]) arm_proxy(s * dual_arm_dy, cz);
}
