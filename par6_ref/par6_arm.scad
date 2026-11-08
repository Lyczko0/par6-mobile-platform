// ############################################################################
//  par6_arm.scad  -  PRAWDZIWY model PAR6 z oficjalnego URDF
//
//  Zrodlo: https://github.com/Source-Robotics/PAR6-Collaborative-Robot-Arm
//          PAR6 Description/URDF/par6_flange/urdf/par6_flange.urdf
//          + 7 meshy STL z tego samego repo (5.0 MB)
//
//  To NIE jest juz atrapa. Lancuch kinematyczny jest przepisany 1:1 z URDF.
//
//  DWIE RZECZY, KTORE TRZEBA WIEDZIEC
//  1. Meshe sa w METRACH (konwencja URDF), stad scale(1000).
//  2. URDF ma wszystkie limity zlacz ustawione na "0 .. 0" - czyli NIE MA
//     tam limitow. Zakresy ruchu trzeba wziac z dokumentacji Source Robotics,
//     nie z tego pliku. Ponizsze j1..j6 przyjmuja dowolna wartosc.
//
//  rpy z URDF = staly XYZ (roll-pitch-yaw), a OpenSCAD rotate([a,b,c]) liczy
//  Rz(c)*Ry(b)*Rx(a) - to jest ta sama konwencja, wiec rpy w stopniach
//  wchodzi wprost do rotate().
// ############################################################################

par6_mesh_dir = "meshes/";
par6_scale    = 1000;   // metry -> milimetry

// --- interfejs montazowy podstawy, ZMIERZONY Z MESHA base_link.STL ---------
// Plyta podstawy 10 mm ma 8 otworow 5.6 mm (przelot pod M5):
//    X = +40, 0, -40, -104.7   Y = +/-52.5
// Adapter bierze 4 przy J1 (X 0 i -40): leza na jednym okregu R 56.2, wiec
// indeksowanie to rowki lukowe. 1 x otwor 10.3 mm w (0,0) - przepust kablowy.
// 2026-10-05 Lyczko0, szczeki na lbach srub: 38.5 / 101.8 / 101.5 wobec CAD
// 40 / 105 / 104.7 - uklad zgodny, liczby krotsze o metode, nie o podstawe.
// 2026-10-10 sprawdzian test_rig par6_plate (4 x M5 + szerokosc 118) pasuje
// na prawdziwej podstawie - CAD jest 1:1, odczyty suwmiarka juz niepotrzebne
par6_bolt_xy   = [[-40, -52.5], [-40, 52.5], [0, -52.5], [0, 52.5]];
par6_bolt_d    = 5.6;
par6_cable_d   = 10.4;
par6_base_x    = [-113.7, 50.0];    // obrys podstawy w X
par6_base_y    = [-59.0, 59.0];     // obrys podstawy w Y
par6_base_h    = 70.5;              // wysokosc korpusu podstawy

// --- zasieg wyliczony z URDF ----------------------------------------------
// shoulder->upper_arm 110.5 w Z, upper_arm->elbow 180, elbow->lower_arm 43.5,
// lower_arm->wrist 177.  Maksymalny wysieg od osi J1 ok. 424 mm.
par6_reach_max = 424;
par6_h_up      = 467;   // wysokosc przy ramieniu wyprostowanym w gore

// viz/export.py exports one link at a time - in one export CGAL would weld
// the links at the joints into a single body. "" draws the whole arm.
par6_only = "";

module par6_mesh(name) {
    if (par6_only == "" || par6_only == name)
        scale(par6_scale) import(str(par6_mesh_dir, name, ".STL"), convexity = 8);
}

// ---------------------------------------------------------------------------
//  PAR6, uklad lokalny = lico montazowe podstawy na Z = 0
//  j1..j6 w stopniach. Znaki zgodne z osiami z URDF.
// ---------------------------------------------------------------------------
module par6(j1 = 0, j2 = 0, j3 = 0, j4 = 0, j5 = 0, j6 = 0, col = [0.88, 0.89, 0.91]) {
    color(col) {
        par6_mesh("base_link");

        // shoulder_JOINT : xyz 0 0 0, rpy 0 0 0, axis 0 0 -1
        rotate([0, 0, -j1]) {
            par6_mesh("shoulder");

            // upper_arm_JOINT : xyz .0234207 0 .1105, rpy -90 0 0, axis 0 0 1
            translate([23.4207, 0, 110.5]) rotate([-90, 0, 0]) rotate([0, 0, j2]) {
                par6_mesh("upper_arm");

                // elbow_JOINT : xyz 0 -.18 0, rpy 180 0 -90, axis 0 0 -1
                translate([0, -180, 0]) rotate([180, 0, -90]) rotate([0, 0, -j3]) {
                    par6_mesh("elbow");

                    // lower_arm_JOINT : xyz .0435 0 0, rpy 90 0 -180, axis 0 0 -1
                    translate([43.5, 0, 0]) rotate([90, 0, -180]) rotate([0, 0, -j4]) {
                        par6_mesh("lower_arm");

                        // wrist_JOINT : xyz 0 0 -.177, rpy -90 0 0, axis 0 0 1
                        translate([0, 0, -177]) rotate([-90, 0, 0]) rotate([0, 0, j5]) {
                            par6_mesh("wrist");

                            // gripper_JOINT : xyz 0 0 0, rpy 90 0 0, axis 0 0 -1
                            rotate([90, 0, 0]) rotate([0, 0, -j6]) par6_mesh("gripper");
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
//  Obwiednia obrotu J1 - do sprawdzania kolizji z kolumna i oslonami.
//  Walec o promieniu zasiegu wokol osi J1, wysokosc = zakres pracy w Z.
//  UWAGA: to obwiednia PELNEGO obrotu 360 stopni. Jesli realny limit J1 jest
//  mniejszy, ta bryla jest zawyzona - i o to chodzi, bo limitow nie znamy.
// ---------------------------------------------------------------------------
module par6_swing_envelope(r = par6_reach_max, h = par6_h_up) {
    translate([0, 0, -60]) cylinder(r = r, h = h + 60);
}

// samo lico montazowe - do wycinania otworow w adapterze
module par6_bolt_pattern(depth = 30, d = par6_bolt_d) {
    for (p = par6_bolt_xy)
        translate([p[0], p[1], -depth / 2]) cylinder(d = d, h = depth);
    translate([0, 0, -depth / 2]) cylinder(d = par6_cable_d, h = depth);
}
