// ############################################################################
//  main_base.scad  -  MOBILE BASE V1 (KONCEPT) - zlozenie glowne
//
//  Baza mobilna pod istniejacy modul osi Z (../z_lift) i docelowo pod jedno
//  lub dwa ramiona PAR6/PAROL6.
//
//  JEDNOSTKI: MILIMETRY.
//  UKLAD: origin na PODLODZE, w srodku obrysu. +X przod, +Y lewo, +Z gora.
//
//  TO JEST KONCEPT, NIE DOKUMENTACJA WYKONAWCZA.
//  Nie wysylac nic na CNC z tego modelu. Zadna masa, zaden margines
//  stabilnosci i zadna nosnosc nie zostaly policzone ani zmierzone.
//  Lista wymiarow do pomiaru: MEASURE_BEFORE_CNC.md
//
//  LANCUCH INCLUDE (liniowy, jeden include):
//    main_base.scad -> base_stability.scad -> base_variants.scad
//                   -> base_components.scad -> base_parameters.scad
// ############################################################################

include <base_covers.scad>

// ===========================================================================
//  PANEL STEROWANIA
// ===========================================================================
variant           = "A";      // "A" | "B" | "C"  <- A = rekomendowany V1
show_frame        = true;
show_drive        = true;
show_casters      = true;
show_battery      = true;
show_cnc          = true;
show_electronics  = true;
show_skirts       = false;    // estetyczne oslony boczne
show_stability    = false;    // polygon podparcia + strefa CoM
show_dimensions   = false;
show_zlift_ghost  = false;    // stary, prosty obrys - zastapiony przez proxy
show_covers       = true;     // modulowe oslony PETG/ASA
show_column       = true;     // strefa keep-out napedu kolumny Z
show_column_proxy = true;     // wizualne proxy kolumny Z
show_keepouts     = false;    // obwiednie ruchome + strefy dostepu
show_arm          = 1;        // 0 = brak, 1 = jedno PAR6, 2 = dwa
carriage_z        = col_carriage_low;   // col_carriage_low | col_carriage_high
arm_pose          = "front";  // "front" | "side" | "max"

view              = "iso";    // "iso" | "top" | "bottom" | "side" | "front"
explode           = 0;

render_assembly   = true;     // false gdy inny plik importuje tylko moduly

// ===========================================================================
//  KAMERA
// ===========================================================================
$vpr = (view == "top")    ? [  0, 0,   0]
     : (view == "bottom") ? [180, 0,   0]
     : (view == "side")   ? [ 90, 0, 270]
     : (view == "front")  ? [ 90, 0, 180]
     :                      [ 62, 0, 205];
$vpt = [0, 0, view == "top" || view == "bottom" ? 120 : 160];
$vpd = (view == "top" || view == "bottom") ? 1400 : 1900;

// ===========================================================================
//  ZLOZENIE
// ===========================================================================
module base_assembly(v) {
    base_variant(v);
    antitip_side_pair();
    ballast_bars();
    if (show_covers)       covers_all();
    if (show_column_proxy) { column_proxy(carriage_z); arms_proxy(carriage_z); }
    if (show_keepouts)     { keep_all(); access_all(); }

    if (show_stability) {
        draw_support(v);
        draw_turning(v);
        draw_forces(v);
        com_marker(system_com(arm_pose));
    }
}

// ---------------------------------------------------------------------------
//  wymiarowanie - tylko kilka wielkosci, ktore realnie steruja projektem
// ---------------------------------------------------------------------------
module dim_text(pos, s, size = 18) {
    translate(pos) rotate([90, 0, 180])
        linear_extrude(1) text(s, size = size, halign = "center",
                               valign = "center");
}

module dim_line(a, b) {
    color([0.05, 0.05, 0.05]) {
        hull() { translate(a) sphere(d = 3); translate(b) sphere(d = 3); }
        for (p = [a, b]) translate(p) sphere(d = 8);
    }
}

module dimensions_overlay() {
    y = half_w + 120;
    dim_line([-half_l, y, 0], [half_l, y, 0]);
    dim_text([0, y, 40], str("base_length ", base_length));

    dim_line([half_l + 90, -half_w, 0], [half_l + 90, half_w, 0]);
    dim_text([half_l + 90, 0, 40], str("base_width ", base_width));

    dim_line([half_l + 200, 0, 0], [half_l + 200, 0, base_deck_height]);
    dim_text([half_l + 200, 0, base_deck_height / 2],
             str("deck ", base_deck_height));

    dim_line([-half_l - 120, 0, 0], [-half_l - 120, 0, ground_clearance]);
    dim_text([-half_l - 120, 0, 90], str("przeswit ", ground_clearance));

    dim_line([drive_axle_x, -wheel_y, wheel_diameter + 60],
             [drive_axle_x,  wheel_y, wheel_diameter + 60]);
    dim_text([drive_axle_x, 0, wheel_diameter + 100],
             str("wheel_track ", wheel_track));
}

// ===========================================================================
//  RENDER
// ===========================================================================
if (render_assembly) {
    base_assembly(variant);
    if (show_dimensions) dimensions_overlay();
}

base_report();
variant_report(variant);
if (show_stability || true) stability_report(variant);
