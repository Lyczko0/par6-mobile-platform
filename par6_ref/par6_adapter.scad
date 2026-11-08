// ############################################################################
//  par6_adapter.scad  -  wspornik kolumna Z  ->  PAR6, os J1 PIONOWA
//
//  Laczy dwa REALNE interfejsy:
//    * kolumna (../z_lift): raster 100 x 100 M6, otwor srodkowy 60,
//      lico PIONOWE na przedzie plyty ruchomej (chassis X = 177)
//    * PAR6 (zmierzone z base_link.STL): 4 x M5 w prostokacie 40 x 105,
//      otwor kablowy 10.4 w srodku
//
//  DLACZEGO WSPORNIK, A NIE PLASKA PLYTA
//  Os J1 jest prostopadla do lica montazowego PAR6. Lico kolumny jest
//  pionowe, wiec plaska plyta dalaby J1 POZIOMA - ramie zamiatalo by w
//  pionie i sterczalo w bok. Przy J1 PIONOWEJ grawitacja dziala wzdluz osi
//  J1, wiec moment od ciezaru ramienia na J1 = 0. Dlatego polka pozioma.
//
//  DLACZEGO WYSIEGNIK 130 mm
//  Z J1 obraca sie link "shoulder" (R 140.7), nie "base_link" - base_link
//  jest nieruchomy i tylko musi sie zmiescic.
//
//  HACZYK: ogon base_link (114 mm) i kierunek pracy ramienia leza po
//  PRZECIWNYCH stronach osi J1. Obrocenie ramienia tak, zeby ogon minal
//  kolumne (index 180) obraca tez CALY ROBOT tylem - ramie patrzy w kolumne
//  i jest bezuzyteczne. Wiec index = 0 i wysieg musi pomiescic ogon:
//    wysieg 130 = ogon 114 + luz 15  ->  ramie pracuje DO PRZODU
//  Przy 130 mm martwa strefa J1 to tylko 45 st, dokladnie z tylu w kolumne.
//  Kosztuje 15.9 Nm na wozku Z zamiast 12.5 - warte tego, bo alternatywa
//  jest ramie skierowane w niewlasciwa strone.
//
//  UKLAD LOKALNY = uklad bazy (X przod, Y lewo, Z gora),
//  origin w SRODKU lica montazowego kolumny.
// ############################################################################

include <par6_arm.scad>

// --- interfejs kolumny (z ../z_lift/parameters.scad) ------------------------
col_bolt_pitch   = 100;   // arm_bolt_pitch_x / _y
col_bolt_d       = 6.6;   // arm_bolt_d

// --- wspornik: GIETA BLACHA (P2, 2026-09-25) --------------------------------
// Katownik (plyta pionowa + polka, jedno giecie) i dwa giete zebra, wszystko
// 6 mm 5754/5052 z uslugi blacharskiej PCBWay: zero CNC, zero plyt 10 mm.
// Bylo: plyty 10 mm, polka CNC (rowki lukowe) i zebra 8 mm do 150 mm.
// par6_ref/adapter_stiffness.py: blad na chwytaku 0.056 mm i postac ramienia
// 68 Hz, wobec 0.123 mm i 44 Hz poprzedniej wersji. Robi to zebro przez CALA
// polke - konczace sie na 150 mialo nad J1 juz tylko 8 mm wysokosci.
adapter_thk      = 6;     // katownik
adapter_bend_r   = adapter_thk;   // wewn. promien giecia, 1t     [VERIFY] PCBWay
plate_size       = 165;   // plyta pionowa: wysokosc (Z)
shelf_reach      = 130;   // os J1 przed licem kolumny  <- glowny parametr
shelf_width      = 200;   // polka i plyta w Y - zakladki zeber siegaja krawedzi
shelf_z          = -75;   // gora polki wzgledem srodka lica (nisko = blizej
                          // podlogi przy kolumnie w dole)
shelf_tilt       = 0;     // giecie jest 90 st.; pochylenie polki to inne giecie
gusset_thk       = 6;
gusset_y         = 64;    // os zebra: lico wewn. 61, podstawa PAR6 konczy sie na 59
gusset_h         = 63;    // nad polka, u nasady; bark PAR6 zaczyna sie 70.5 nad nia
gusset_tab       = 33;    // zagiete zakladki na M5 - krotszych 6 mm blachy nie zegnie
gusset_bolt_y    = shelf_width / 2 - 9;   // os srub zakladek, 91
gusset_bolts_x   = [50, 120, 190];        // zakladka dolna, w polke
gusset_bolts_z   = [30, 52];              // zakladka tylna, w plyte (nad polka)

// --- PAR6 na polce ---------------------------------------------------------
par6_bolt_r      = 56.2;  // wszystkie 4 sruby na JEDNYM okregu (zmierzone)
par6_pattern_cx  = -20;   // srodek rastru wzgledem osi J1
par6_index_angle = 0;     // 0 = ramie PRACUJE DO PRZODU. Ogon base_link (114 mm)
                          // i kierunek pracy ramienia sa po PRZECIWNYCH
                          // stronach, wiec index 180 owszem chowa ogon, ale
                          // obraca cale ramie tylem - patrzy w kolumne.
                          // Dlatego index 0 + wiekszy wysieg.
adapter_index    = 20;    // +/- st. regulacji katowej w rowkach lukowych
adapter_bore     = 40;    // przepust kablowy w polce

// ---------------------------------------------------------------------------
//  wzorzec PAR6 jako otwory w polce: 4 ROWKI LUKOWE na R 56.2.
//  Wszystkie sruby leza na tym samym promieniu, wiec indeksowanie katowe to
//  4 luki, a nie 4 x N osobnych otworow.
// ---------------------------------------------------------------------------
module par6_arc_slots(h) {
    translate([par6_pattern_cx, 0, -1])
        linear_extrude(h + 2)
            for (p = par6_bolt_xy) {
                a0 = atan2(p[1], p[0] - par6_pattern_cx);
                hull() for (t = [-adapter_index, adapter_index])
                    rotate(a0 + t) translate([par6_bolt_r, 0])
                        circle(d = par6_bolt_d);
            }
}

// ---------------------------------------------------------------------------
//  WSPORNIK - katownik giety + 2 giete zebra, skrecane M5.
//  Katownik rysowany z prawdziwym gieciem (jak wsporniki BK12/BF12 w z_lift),
//  bo polka zaczyna sie plasko dopiero t + r przed plyta.
// ---------------------------------------------------------------------------
module par6_bracket() {
    assert(shelf_tilt == 0, "gieta blacha: giecie 90 st., pochylenie to inne giecie");
    t  = adapter_thk;
    r  = adapter_bend_r;
    L  = shelf_reach + 95;                  // polka od lica wozka
    cx = t + r;                             // srodek giecia, r od obu lic wewn.
    cz = shelf_z + r;
    // par6_only "bracket_angle" / "bracket_ribs": katownik i zebra osobno,
    // zeby w Fusion daly sie rozebrac (2026-10-07)
    color([0.72, 0.74, 0.76]) {
        if (par6_only != "bracket_ribs") difference() {
            // katownik: profil w XZ wyciagniety wzdluz Y
            rotate([90, 0, 0]) linear_extrude(shelf_width, center = true)
                union() {
                    translate([0, cz]) square([t, plate_size / 2 - cz]);      // plyta
                    translate([cx, shelf_z - t]) square([L - cx, t]);         // polka
                    intersection() {                                          // giecie
                        translate([cx, cz]) difference() { circle(r = r + t); circle(r = r); }
                        translate([0, shelf_z - t]) square([cx, r + t]);
                    }
                }
            // raster kolumny + przepust kablowy w osi rastru
            for (y = [-1, 1], z = [-1, 1])
                translate([-1, y * col_bolt_pitch / 2, z * col_bolt_pitch / 2])
                    rotate([0, 90, 0]) cylinder(d = col_bolt_d, h = t + 2);
            translate([-1, 0, 0]) rotate([0, 90, 0]) cylinder(d = adapter_bore, h = t + 2);
            // PAR6: rowki lukowe z lasera + przepust
            translate([shelf_reach, 0, shelf_z - t]) {
                par6_arc_slots(t);
                translate([0, 0, -1]) cylinder(d = adapter_bore, h = t + 2);
            }
            // sruby zakladek zeber
            for (s = [-1, 1]) {
                for (x = gusset_bolts_x)
                    translate([x, s * gusset_bolt_y, shelf_z - t - 1]) cylinder(d = 5.5, h = t + 2);
                for (z = gusset_bolts_z)
                    translate([-1, s * gusset_bolt_y, shelf_z + z]) rotate([0, 90, 0])
                        cylinder(d = 5.5, h = t + 2);
            }
        }
        if (par6_only != "bracket_angle") for (s = [-1, 1]) par6_gusset(s);
    }
}

// Zebro: trojkat przez cala polke + zakladki zagiete NA ZEWNATRZ (od
// podstawy PAR6), dolna na polce, tylna na plycie. Naroze wyciete pod giecie
// katownika. ponytail: zakladki rysowane z ostrym naroznikiem - to male
// giecia, a naroze, ktore niesie moment, jest wyciete; model zebra na to
// wystarcza. Rysowac z promieniem, jesli zakladka zacznie cos dotykac.
module par6_gusset(s) {
    t   = gusset_thk;
    x0  = adapter_thk;                      // lico plyty
    L   = shelf_reach + 95;
    rel = adapter_bend_r + 1;               // wyciecie pod giecie katownika
    yo  = s > 0 ? gusset_y + t / 2 : -(gusset_y + t / 2 + gusset_tab);  // zakladki
    difference() {
        union() {
            translate([0, s * gusset_y + t / 2, 0]) rotate([90, 0, 0]) linear_extrude(t)
                polygon([[x0, shelf_z], [L, shelf_z], [x0, shelf_z + gusset_h]]);
            translate([x0 + rel, yo, shelf_z]) cube([L - x0 - rel, gusset_tab, t]);
            translate([x0, yo, shelf_z + rel]) cube([t, gusset_tab, gusset_h - rel]);
        }
        translate([x0 - 1, s * gusset_y - t / 2 - 1, shelf_z - 1]) cube([rel + 1, t + 2, rel + 1]);
        for (x = gusset_bolts_x)
            translate([x, s * gusset_bolt_y, shelf_z - 1]) cylinder(d = 5.5, h = t + 2);
        for (z = gusset_bolts_z)
            translate([x0 - 1, s * gusset_bolt_y, shelf_z + z]) rotate([0, 90, 0])
                cylinder(d = 5.5, h = t + 2);
    }
}

// ---------------------------------------------------------------------------
//  Wspornik + PAR6 w pozycji montazowej
// ---------------------------------------------------------------------------
module par6_with_adapter(j = [0, -40, 75, 0, -35, 0], idx = par6_index_angle,
                         show_arm_body = true) {
    if (par6_only == "" || par6_only == "bracket" || par6_only == "bracket_angle"
        || par6_only == "bracket_ribs") par6_bracket();
    if (show_arm_body)
        translate([0, 0, shelf_z]) rotate([0, -shelf_tilt, 0])
            translate([shelf_reach, 0, 0])
                rotate([0, 0, idx])
                    par6(j[0], j[1], j[2], j[3], j[4], j[5]);
}

// obwiednia zamiatania J1 przy zlozonym ramieniu - do testow kolizji
par6_shoulder_r = 140.7;   // zmierzone z shoulder.STL
module par6_swing_folded() {
    translate([0, 0, shelf_z]) rotate([0, -shelf_tilt, 0])
        translate([shelf_reach, 0, 0])
            cylinder(r = par6_shoulder_r, h = 160);
}
