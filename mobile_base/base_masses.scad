// ############################################################################
//  base_masses.scad  -  mass budget and centre of mass
//
//  Feeds the numbers that base_stability.scad has been waiting for:
//  total_robot_mass, arm_mass, arm_payload, arm_reach, com_x/y/z.
//  Overrides the undef placeholders in base_parameters.scad, so this file
//  must be included AFTER it (see the chain note in main_base.scad).
//
//  EVERY ROW CARRIES ITS SOURCE. Four kinds, and the difference matters:
//    MEAS  - weighed or measured on a real part
//    CALC  - geometry from the parameter files x material density
//    CAT   - manufacturer catalogue figure for a standard part
//    BRACKET - genuinely unknown: given as [lo, hi], never as one number
//
//  Unknowns are intervals, not guesses. The report evaluates the budget at
//  both ends of every interval and a PASS requires both ends to pass.
//  An interval is not a guessed number - it is an honest statement of what
//  is not yet known.
//
//  Item format:  [name, m_lo, m_hi, [x, y, z], count, source]
//  Position is the part CENTROID in base coordinates (floor origin,
//  +X front, +Y left, +Z up). For a symmetric pair modelled as one row with
//  count = 2, give the centroid of the pair (so y = 0 for a left/right pair).
// ############################################################################

include <base_parameters.scad>

// ---------------------------------------------------------------------------
//  MATERIALS AND STANDARD PARTS
// ---------------------------------------------------------------------------
rho_al = 2.70e-6;   // kg/mm3, 6082-T6 / 6061
rho_fe = 7.85e-6;   // kg/mm3, steel
rho_petg = 1.27e-6; // kg/mm3, PETG lity
// Wydruk to nie lita bryla: 4-5 linii sciany plus ~40 % wypelnienia daje
// okolo 60 % masy litej. Do wyliczenia PO zwazeniu pierwszego wydruku.
print_fill = 0.60;                                             // [VERIFY]

// Flat parts are computed as solid boxes. Real plates lose mass to bolt
// holes, cable pass-throughs and lightening pockets. This is the knob for
// that - lower it after the first real plate comes back from PCBWay and
// gets weighed.
plate_hole_factor = 0.85;                                      // [VERIFY]

// Extruded profile, 8 mm slot. Light and heavy series differ by ~20 %, so
// this must be checked against the actual Allegro listing before ordering.
// 2026-08-19: 40x80 is now a DATASHEET value. V-SLOT 40x80, 6063-T5, slot 8:
// 3.2 kg/m, Ix 78.8 cm4, Iy 21.6 cm4, E 68 600 N/mm2. The 3.20 guessed here
// was right. The Ix is NOT comfortable - see z_lift/backbone_stiffness.py.
prof_4080_kgm = 3.20;   // DATASHEET
prof_4040_kgm = 1.60;                                          // [VERIFY]

// Linear motion, catalogue figures
hgr20_kgm     = 3.05;   // HGR20 rail alone                    [VERIFY]
hgh20ca_kg    = 0.35;   // one HGH20CA block                   [VERIFY]

// ---------------------------------------------------------------------------
//  THE THREE GENUINE UNKNOWNS
//  These are the only reason this budget is an interval rather than a number.
//  Both parts arrive later: the hub motors come with the Manta board, the
//  casters are not bought yet.
// ---------------------------------------------------------------------------
hub_motor_kg = [2.4, 3.6];   // 8.5" hoverboard hub motor, per wheel
// 2026-08-19: caster WYBRANY - D125 gumowo-zelazny, skretny, z hamulcem
// postojowym, 1.1 kg z karty. Przedzial 0.9-2.0 zamyka sie w liczbe.
// UWAGA: ten caster NIE MA podatnosci pionowej. Poprzedni opis zakladal
// "WITH vertical compliance" i to zalozenie wlasnie upadlo - cala podatnosc
// musi teraz dac uchwyt, ktory nadal nie istnieje.
caster_kg    = [1.1, 1.1];   // D125, z karty - od 2026-10-03 tylko TYL
// Przod: kolo omni D127, nie kupione. Przedzial, nie pomiar - zwazyc.
omni_kg      = [0.4, 1.2];   //                                    [MEASURE]
// Covers from the VOLUME of their own meshes (viz/mesh, 2026-10-03), not a
// band picked by eye. Low end: PETG at 55 % of solid - Lyczko0 sliced the
// fluted wall coupon (test_rig/coupons.scad) in Anycubic Slicer Next on
// 2026-10-04: 25.92 g against 47.1 g solid, 2 walls, lying flat. A 3 mm wall
// is NOT nearly solid at 2 walls - the guess here was 90 % for one day. High
// end: solid PETG (4+ walls). Until 2026-10-03 one band [1.6, 3.0] kg stood
// for all of it at Z 160, and the column shell has its centroid at Z 682.
// viz/export.py recomputes volume and centroid from the meshes and fails if
// these literals drift.
cover_kg      = [2.18, 3.96];   // 9 base panels, 3.12 dm3
cover_com     = [43, 0, 177];
col_shell_kg  = [1.82, 3.31];   // column shell, 6 parts, 2.60 dm3
col_shell_com = [41, 0, 682];

// ---------------------------------------------------------------------------
//  HELPERS
// ---------------------------------------------------------------------------
function plate_kg(l, w, t) = l * w * t * rho_al * plate_hole_factor;
function print_kg(l, w, t) = l * w * t * rho_petg * print_fill;
function bar_kg(len, kgm)  = len / 1000 * kgm;
function rod_kg(d, len, rho) = PI * pow(d / 2, 2) * len * rho;
function ssum(v, i = 0) = i >= len(v) ? 0 : v[i] + ssum(v, i + 1);
function mean(v) = ssum(v) / len(v);

// ===========================================================================
//  Z COLUMN - dimensions copied from ../z_lift/parameters.scad
//
//  ponytail: literal copy instead of including z_lift/parameters.scad.
//  Ceiling: the two files can drift, which has already happened once and
//  produced a false "44 mm deficit" alarm. Upgrade path: pull z_lift into
//  the include chain once its variable names stop colliding with
//  base_parameters (col_alu / col_profile was the last clash). Until then
//  zlift_report() echoes these numbers so a mismatch is visible.
//
//  Coordinate mapping, derived and verified against arm_mount_x = 177:
//     base_x = zlift_Y + 45        (zlift Y=132 arm face -> base x=177 OK)
//     base_z = zlift_Z + base_deck_height
// ===========================================================================
// 2026-08-18: the backbone plate and both riser bars are GONE, replaced by
// two 40x80 T-slot profiles on edge. Rails bolt to the profile's centre slot
// on hammer nuts, so nothing is drilled or tapped. See ../z_lift/parameters.
zl_profile    = [40, 80, 840];    // column_profile_w, _d, backbone_h
zl_profile_x  = 130;              // +/- X, = rail_spacing/2
zl_tie        = [208 + 2*30, 80, 6]; // shelf 208 + dwa zagiete uchwyty po 30
                                  // (blank giety, nie plyta 300 - ta nie
                                  //  miescila sie miedzy profilami)
zl_baseplate  = [420, 300, 10];   // base_plate_w, base_plate_d, base_plate_thk
zl_movplate   = [440, 220, 10];   // plate_w, plate_h, plate_thk
zl_nut_bracket = [150, 140, 6];   // plaski blank wspornika nakretki
zl_rail_len   = 800;
zl_screw_d    = 16;
zl_screw_len  = 800;
zl_motor_kg   = 0.9;              // motor_brake_mass, three agreeing sources

// base_x = zlift_Y - base_plate_cy. The base plate is derived from
// y_carriage_face, so it moved back with the deeper backbone and the offset
// went 75 -> 45. Checked: the arm face still lands on base x = 177.
function zx(zlift_y) = zlift_y + 45;
function zz(zlift_z) = zlift_z + base_deck_height;

// ===========================================================================
//  ITEM LIST
// ===========================================================================
// 5 poprzeczek, nie 6. Dodatkowa wariantu A nachodzila na te z X=-260
// o 20 mm; teraz jest jedna na -240, wysrodkowana pod tylnym casterem.
cross_all = cross_x;

frame_items = [
    ["profil 4080 belka glowna",
     bar_kg(base_length, prof_4080_kgm), bar_kg(base_length, prof_4080_kgm),
     [0, 0, (frame_bottom_z + frame_top_z) / 2], 2, "CAT"],

    ["profil 4040 poprzeczka",
     bar_kg(2 * main_beam_y - profile_main_w, prof_4040_kgm),
     bar_kg(2 * main_beam_y - profile_main_w, prof_4040_kgm),
     [mean(cross_all), 0, frame_top_z - profile_cross / 2], len(cross_all), "CAT"],
];

plate_items = [
    // 2026-10-07: gniazdo + oryginalne strzemie + 2 giete wieszaki na kolo.
    // Byla plyta-zastepnik 160 x 150 x 10 (0.55 kg), stojaca w silniku.
    ["gniazdo osi kola",
     plate_kg(seat_w, seat_len, seat_h), plate_kg(seat_w, seat_len, seat_h),
     [drive_axle_x, 0, seat_top_z - seat_h / 2], 2, "CALC"],
    // jedna gieta czesc na kolo: 2 scianki + plyta pod belka + noga na licu
    ["wieszak uchwytu kola, giety",
     2 * plate_kg(main_beam_y + profile_main_w / 2 - 0.5 - hanger_y0,
                  frame_bottom_z - (seat_top_z - seat_h), hanger_t)
       + plate_kg(seat_w + 2 * hanger_t, profile_main_w - 0.5, hanger_t)
       + plate_kg(seat_w + 2 * hanger_t, hanger_leg_top - frame_bottom_z + hanger_t, hanger_t),
     2 * plate_kg(main_beam_y + profile_main_w / 2 - 0.5 - hanger_y0,
                  frame_bottom_z - (seat_top_z - seat_h), hanger_t)
       + plate_kg(seat_w + 2 * hanger_t, profile_main_w - 0.5, hanger_t)
       + plate_kg(seat_w + 2 * hanger_t, hanger_leg_top - frame_bottom_z + hanger_t, hanger_t),
     [drive_axle_x, 0, (seat_top_z - seat_h + hanger_leg_top) / 2], 2, "CALC"],
    // oryginal z hoverboardu, stal ~40 x 75 x 3 po rozwinieciu      [VERIFY]
    ["strzemie oryginalne",
     40 * 75 * strap_t * rho_fe, 40 * 75 * strap_t * rho_fe,
     [drive_axle_x, 0, axle_flat_z], 2, "CALC"],

    // nie istnieje - masa zastepcza plyty 110 x 110 x 6, jak u castera
    ["uchwyt kola omni przedni",
     plate_kg(110, 110, 6), plate_kg(110, 110, 6),
     [omni_x, 0, frame_bottom_z - 4], 1, "CALC"],

    ["uchwyt castera tylny",
     plate_kg(110, 110, 6), plate_kg(110, 110, 6),
     [caster_rear_x, 0, frame_bottom_z - 4], 1, "CALC"],

    // 2026-10-07: kolyski z blachy zamiast wanny drukowanej na dnie
    ["kolyska pakietu, gieta",
     plate_kg(cradle_w, 2 * (main_beam_y - profile_main_w / 2)
                        + 2 * (frame_top_z - 10 - battery_z + cradle_t), cradle_t),
     plate_kg(cradle_w, 2 * (main_beam_y - profile_main_w / 2)
                        + 2 * (frame_top_z - 10 - battery_z + cradle_t), cradle_t),
     [mean(cradle_x), 0, battery_z], 2, "CALC"],

    ["plyta elektroniki DRUK",
     print_kg(elec_plate_l, elec_plate_w, elec_plate_thk),
     print_kg(elec_plate_l, elec_plate_w, elec_plate_thk),
     [elec_plate_x, 0, frame_top_z + elec_plate_thk / 2], 1, "CALC"],

    // was print_kg(250, 80, 5): the plate is drawn 315 x 80 x 10
    ["plyta koncowa ramy DRUK",
     print_kg(end_plate_thk, 2 * (main_beam_y + profile_main_w / 2), profile_main_h),
     print_kg(end_plate_thk, 2 * (main_beam_y + profile_main_w / 2), profile_main_h),
     [0, 0, (frame_bottom_z + frame_top_z) / 2], 2, "CALC"],

    // mocowanie oslon M4 (2026-10-03), pod belkami
    ["wsporniki oslon bocznych DRUK",
     print_kg(side_bracket_w, cover_side_y - main_beam_y + 12.5, side_bracket_h),
     print_kg(side_bracket_w, cover_side_y - main_beam_y + 12.5, side_bracket_h),
     [ssum(side_bracket_x) / len(side_bracket_x), 0,
      frame_bottom_z - side_bracket_h / 2], 2 * len(side_bracket_x), "CALC"],

    ["katowniki narozne katalogowe",
     0.05, 0.05, [0, 0, frame_top_z], 8, "CAT"],

    ["wspornik anti-tip bocznego",
     plate_kg(80, 60, 6), plate_kg(80, 60, 6),
     [antitip_side_x, 0, antitip_gap + antitip_d / 2], 2, "CALC"],
];

drive_items = [
    ["kolo hub-motor 8.5\"",
     hub_motor_kg[0], hub_motor_kg[1],
     [drive_axle_x, 0, wheel_radius], 2, "BRACKET"],

    ["kolo omni D127 przednie",
     omni_kg[0], omni_kg[1],
     [omni_x, 0, omni_d / 2], 1, "BRACKET"],

    ["caster D125 tylny",
     caster_kg[0], caster_kg[1],
     [caster_rear_x, 0, caster_diameter / 2], 1, "BRACKET"],

    // Masa liczona z geometrii plaskownika, nie wpisana - zmiana grubosci
    // albo liczby plaskownikow przelicza wszystko sama. Para jest symetryczna
    // w Y, wiec jeden wiersz x2 na Y = 0 daje ten sam CoM co dwa lustrzane.
    ["balast: plaskownik stal 150x80x12 na licu belki, tyl",
     ballast_kg / 2, ballast_kg / 2,
     [ballast_cx, 0, ballast_cz], 2, "CALC"],

    ["kolko anti-tip D80",
     0.25, 0.25,
     [antitip_side_x, 0, antitip_gap + antitip_d / 2], 2, "CAT"],
];

power_items = [
    ["pakiet 36 V 12.8 Ah",
     battery_mass, battery_mass,
     [battery_x, battery_y, battery_z + battery_h / 2], 1, "MEAS"],

    ["skrzynka RCB + Pi 5",
     1.5, 1.5, [elec_plate_x, 0, frame_top_z + 45], 1, "CAT"],

    ["plyta Manty + przetwornica + przekazniki",
     1.8, 1.8, [elec_plate_x, 0, frame_top_z + 25], 1, "CAT"],

    ["okablowanie, koszulki, zlaczki",
     1.0, 1.0, [elec_plate_x, 0, frame_top_z], 1, "CAT"],

    ["oslony PETG/ASA, 9 paneli",
     cover_kg[0], cover_kg[1], cover_com, 1, "BRACKET"],
    ["skorupa kolumny PETG/ASA, 6 czesci",
     col_shell_kg[0], col_shell_kg[1], col_shell_com, 1, "BRACKET"],
];

// --- Z column ---------------------------------------------------------------
// Everything here sits ABOVE the deck and forward of the frame centre, which
// is exactly why it dominates both com_z and com_x.
column_items = [
    ["z_lift plyta bazowa",
     plate_kg(zl_baseplate[0], zl_baseplate[1], zl_baseplate[2]),
     plate_kg(zl_baseplate[0], zl_baseplate[1], zl_baseplate[2]),
     [zx(-75), 0, zz(zl_baseplate[2] / 2)], 1, "CALC"],

    ["profil kolumny 40x80 na sztorc",
     bar_kg(zl_profile[2], prof_4080_kgm), bar_kg(zl_profile[2], prof_4080_kgm),
     [zx(zl_profile[1] / 2), 0, zz(10 + zl_profile[2] / 2)], 2, "CAT"],

    ["z_lift plyta spinajaca (gora)",
     plate_kg(zl_tie[0], zl_tie[1], zl_tie[2]),
     plate_kg(zl_tie[0], zl_tie[1], zl_tie[2]),
     [zx(60), 0, zz(777)], 1, "CALC"],

    // Designed 2026-08-19. Both bearings used to be held by their own bolts
    // and nothing else - the "pad" they referenced stood in the gap between
    // the two posts. 6 mm bent sheet, L, one blank used at both ends.
    ["wspornik BK12 (giety)",
     plate_kg(60, 82 + 40, 6), plate_kg(60, 82 + 40, 6),
     [zx(20), 0, zz(50)], 1, "CALC"],

    // foot under the tie shelf since 2026-09-25 - web 6 mm taller
    ["wspornik BF12 (giety)",
     plate_kg(60, 37 + 40, 6), plate_kg(60, 37 + 40, 6),
     [zx(20), 0, zz(790)], 1, "CALC"],

    ["prowadnica HGR20/800",
     bar_kg(zl_rail_len, hgr20_kgm), bar_kg(zl_rail_len, hgr20_kgm),
     [zx(80), 0, zz(20 + zl_rail_len / 2)], 2, "CAT"],

    ["wozek HGH20CA",
     hgh20ca_kg, hgh20ca_kg, [zx(95), 0, carriage_z], 4, "CAT"],

    ["sruba SFU1605/800",
     rod_kg(zl_screw_d, zl_screw_len, rho_fe),
     rod_kg(zl_screw_d, zl_screw_len, rho_fe),
     [zx(60), 0, zz(430)], 1, "CALC"],

    ["nakretka + wspornik gięty",
     0.35 + plate_kg(zl_nut_bracket[0], zl_nut_bracket[1], zl_nut_bracket[2]),
     0.35 + plate_kg(zl_nut_bracket[0], zl_nut_bracket[1], zl_nut_bracket[2]),
     [zx(60), 0, carriage_z], 1, "CALC"],

    ["lozyskowanie BK12 + BF12",
     0.55, 0.55, [zx(60), 0, zz(430)], 1, "CAT"],

    ["sprzeglo elastyczne",
     0.15, 0.15, [zx(60), 0, zz(30)], 1, "CAT"],

    ["NEMA23 + hamulec zintegrowany",
     zl_motor_kg, zl_motor_kg, [zx(60), 0, 202], 1, "MEAS"],

    ["z_lift plyta ruchoma + zebra",
     plate_kg(zl_movplate[0], zl_movplate[1], zl_movplate[2]) * 1.25,
     plate_kg(zl_movplate[0], zl_movplate[1], zl_movplate[2]) * 1.25,
     [col_plate_x - zl_movplate[2] / 2, 0, carriage_z], 1, "CALC"],

    // P2 2026-09-25: bent 6 mm angle + two ribs over the whole shelf (was
    // 10 mm plates + 8 mm gussets, 2.30 kg here). Mass of the drawn part from
    // par6_ref/adapter_stiffness.py, which asserts this literal.
    ["wspornik PAR6 (katownik giety + 2 zebra)",
     1.67, 1.67, [arm_mount_x + 72, 0, carriage_z - 48], 1, "CALC"],
];

all_items = concat(frame_items, plate_items, drive_items, power_items, column_items);

// ===========================================================================
//  AGGREGATION
// ===========================================================================
// hi: false = all intervals low, true = all high, "worst" = see below
// worst_x_ref: about the system com_x with the arm out front - the case the
// worst corner is chosen for. Asserted against the real one further down.
worst_x_ref = 90;
function it_m(it, hi) =
    it[4] * (hi == "worst" ? (is_bracket(it) && !has_mirror(all_items, it)
                              && it[3][0] > worst_x_ref ? it[2] : it[1])
           : hi ? it[2] : it[1]);
function tot_m(items, hi) = ssum([for (it = items) it_m(it, hi)]);
function tot_mx(items, hi, k) = ssum([for (it = items) it_m(it, hi) * it[3][k]]);
function com_of(items, hi) =
    let (m = tot_m(items, hi))
    [tot_mx(items, hi, 0) / m, tot_mx(items, hi, 1) / m, tot_mx(items, hi, 2) / m];

// Two-corner evaluation (all intervals low, all intervals high) brackets the
// true extreme ONLY while every bracketed item is x-symmetric - either sitting
// on x = 0 or paired with a mirror row of identical mass. An unmirrored one
// pulls com_x on its own, so the worst case is a MIXED corner: since the
// omni front wheel (2026-10-03) that corner is "worst" in it_m() - symmetric
// intervals low, an unmirrored item AHEAD of the arm-loaded CoM high (it
// drags com_x forward), one behind it low (heavier would pull com_x back).
// Picking the end by side is only valid while the item stands well clear of
// that CoM; the assert below enforces it.
// (The side pose prefers the omni light instead: < 1 mm, 2026-10-03.)
function is_bracket(it) = it[2] > it[1] + 1e-9;
function has_mirror(items, it) =
    len([for (o = items) if (is_bracket(o)
             && abs(o[3][0] + it[3][0]) < 0.5
             && abs(o[1] - it[1]) < 1e-9 && abs(o[2] - it[2]) < 1e-9) 1]) > 0;

assert(len([for (it = all_items)
            if (is_bracket(it) && !has_mirror(all_items, it)
                && abs(it[3][0] - worst_x_ref) < 40)
            it[0]]) == 0,
       "base_masses: an unmirrored bracketed item stands within 40 mm of the arm-loaded CoM - its worst end can no longer be picked by side; enumerate the corners.");

// ---------------------------------------------------------------------------
//  WORST CASE = ALL SYMMETRIC INTERVALS LOW (+ the "worst" rule above).
//  The arm hangs forward of the base centroid, so system com_x =
//  (Mb*cbx + Ma*ax)/(Mb+Ma) grows as the base gets lighter. A lighter base is
//  therefore the unsafe end, and it is one physically consistent corner -
//  not a mix of the worst number from each column.
// ---------------------------------------------------------------------------
base_com_lo = com_of(all_items, "worst");
base_com_hi = com_of(all_items, true);
base_m_lo   = tot_m(all_items, "worst");
base_m_hi   = tot_m(all_items, true);

// ===========================================================================
//  OVERRIDES CONSUMED BY base_stability.scad
// ===========================================================================
payload_object   = 0.5;    // object in the gripper, design assumption  [VERIFY]

mass_data_known  = true;
total_robot_mass = base_m_lo;        // worst corner, consistently
com_x            = base_com_lo[0];
com_y            = base_com_lo[1];
com_z            = base_com_lo[2];

// 2026-08-19: Lyczko0 ZWAZYL cale ramie w komplecie - 6.6 kg. Model mial
// 3.4 + 0.552 = 3.952, czyli mylil sie o 2.65 kg (+67 %) i to na koncu
// najdluzszej dzwigni w calej maszynie. To jest pomiar, nie oszacowanie,
// i zastepuje oba stare skladniki.
// arm_payload zostaje SAMYM przenoszonym obiektem - chwytak jest juz w 6.6.
arm_mass         = 6.6;    // PAR6 + chwytak + oprzyrzadowanie, ZWAZONE  MEAS
arm_payload      = payload_object;           // sam obiekt w chwytaku
arm_reach        = 424;    // par6_reach_max, from the official URDF

// The worst corner (it_m) picked each unmirrored item's end by which side of
// worst_x_ref it stands on. Check that reference against the real com_x
// with the arm out front - the pose that corner is chosen for.
worst_x_real = (total_robot_mass * com_x
                + (arm_mass + arm_payload) * (arm_mount_x + arm_reach))
               / (total_robot_mass + arm_mass + arm_payload);
assert(abs(worst_x_real - worst_x_ref) < 25,
       str("base_masses: arm-loaded com_x is ", worst_x_real, ", worst_x_ref ",
           worst_x_ref, " - move the reference and recheck the worst corner"));

// ===========================================================================
//  REPORT
// ===========================================================================
module mass_group_report(title, items) {
    echo(str("  -- ", title, " --"));
    for (it = items)
        echo(str("    ", it[5], "  ", it[4], " x ",
                 is_bracket(it) ? str(it[1], "..", it[2]) : str(it[1]),
                 " kg  @x=", it[3][0], "  = ",
                 is_bracket(it) ? str(it_m(it, false), "..", it_m(it, true))
                                : str(it_m(it, false)), " kg   ", it[0]));
    echo(str("    suma grupy: ", tot_m(items, false), " .. ",
             tot_m(items, true), " kg"));
}

module mass_report() {
    echo("======================================================");
    echo("  BUDZET MAS - baza + kolumna Z, bez ramienia");
    echo("======================================================");
    mass_group_report("rama", frame_items);
    mass_group_report("plyty CNC", plate_items);
    mass_group_report("naped i podpory", drive_items);
    mass_group_report("zasilanie, elektronika, oslony", power_items);
    mass_group_report("kolumna Z", column_items);
    echo("------------------------------------------------------");
    echo(str("  MASA CALKOWITA        : ", base_m_lo, " .. ", base_m_hi, " kg"));
    echo(str("  udzial kolumny Z      : ",
             round(1000 * tot_m(column_items, false) / base_m_lo) / 10, " %"));
    echo(str("  CoM (dolny kraniec)   : [", base_com_lo[0], ", ",
             base_com_lo[1], ", ", base_com_lo[2], "]"));
    echo(str("  CoM (gorny kraniec)   : [", base_com_hi[0], ", ",
             base_com_hi[1], ", ", base_com_hi[2], "]"));
    echo(str("  wozek Z na            : ", carriage_z, " mm"));
    echo("  UWAGA: com_x i com_y NIE zaleza od wysokosci wozka - os Z jest");
    echo("  czysto pionowa, wiec podnoszenie zmienia tylko com_z. Statyczny");
    echo("  margines w planie jest niezalezny od wysokosci. Wysokosc wchodzi");
    echo("  dopiero do dynamiki, ktorej ten test nie obejmuje.");
    echo("------------------------------------------------------");
    echo(str("  z ramieniem: arm_mass ", arm_mass, " + payload ", arm_payload,
             " kg, zasieg ", arm_reach, " mm"));
    echo(str("  do stabilnosci przyjeto DOLNY kraniec: total_robot_mass = ",
             total_robot_mass, " kg, com_x = ", com_x));
    echo("======================================================");
}

// Echo of the copied z_lift numbers, so a drift against
// ../z_lift/parameters.scad is visible without opening both files.
module zlift_echo() {
    echo(str("  [z_lift kopia] profil kolumny ", zl_profile,
             " na X +/-", zl_profile_x,
             "  spinajaca ", zl_tie,
             "  plyta bazowa ", zl_baseplate,
             "  plyta ruchoma ", zl_movplate,
             "  wspornik nakretki ", zl_nut_bracket,
             "  silnik+hamulec ", zl_motor_kg, " kg"));
}
