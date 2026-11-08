// ############################################################################
//  main.scad  -  VERTICAL Z-AXIS LIFT MODULE for a mobile manipulator
//
//  Original DIY design. Visually in the family of compact mobile
//  manipulation platforms, geometrically nothing is copied from any of them.
//  Built around: 2x HGR20/800 + 4x HGH20CA, SFU1605/800, BK12 + BF12,
//  NEMA23 (1.26 Nm), TMC5160 @ 24 V.
//
//  UNITS: MILLIMETRES.
//
//  THIS IS A PROTOTYPE LAYOUT, NOT A CERTIFIED DESIGN.
//  No load rating, deflection figure or safety factor in this project has
//  been calculated or tested. A ball screw vertical axis back-drives when
//  the power is removed - read README.md before you bolt an arm to it.
//
//  INCLUDE CHAIN (kept linear on purpose, one include only):
//      main.scad -> enclosure.scad -> components.scad -> parameters.scad
//  Every default lives in parameters.scad. The block below re-assigns the
//  user-facing ones; in OpenSCAD the LAST assignment in a scope wins, so
//  these override the defaults, and -D on the command line overrides these.
// ############################################################################

include <enclosure.scad>

// ===========================================================================
//  USER CONTROL PANEL
// ===========================================================================
show_frame            = true;   // backbone, base plate, risers
show_rails            = true;   // HGR20 rails + HGH20CA blocks
show_carriage         = true;   // moving plate, ribs, ball nut + housing
show_motor            = true;   // NEMA23, coupling, screw, BK12/BF12
show_enclosure        = true;   // white printed panels
show_cable_chain      = true;   // 10 x 20 cable chain
show_single_arm_mount = true;   // one centred arm interface
show_dual_arm_mount   = false;  // two symmetric arm interfaces (future)
show_dimensions       = false;  // dimension overlay
show_context          = false;  // ghost of the future mobile base deck
show_brake            = true;   // placeholder volume for the future brake
show_ribs             = true;   // stiffening ribs behind the moving plate
show_belt_drive       = false;  // optional belt reduction instead of coupling

// 0 = LOW / floor reach ... z_travel = HIGH / countertop reach.
// Values outside the range are clamped and reported in the console.
carriage_position_mm  = 300;

explode               = 0;      // mm. 0 = assembled, try 40 for exploded.
view                  = "iso";  // "iso" | "front" | "side" | "exploded"

// Set false when another file includes main.scad only for its modules
// (check_collisions.scad does this).
render_assembly       = true;

// Three canonical positions, echoed at the bottom of this file.
// LOW  : carriage_position_mm = 0
// MID  : carriage_position_mm = z_travel/2
// HIGH : carriage_position_mm = z_travel

// ===========================================================================
//  DERIVED
// ===========================================================================
cz = carriage_z(carriage_position_mm);          // plate centre height, clamped
function ex(f) = explode * f;                   // exploded view offset helper

// GUI camera. Overridden by --camera=... on the command line.
// +Y is the FRONT of the machine, so every view needs rotz around 180 to
// look at the arm side rather than the electronics bay.
$vpr = (view == "front") ? [90, 0, 180]     // looking at the arm mount
     : (view == "side")  ? [90, 0, 270]     // looking from the robot's right
     :                     [72, 0, 200];    // iso, front-left-above
$vpt = [0, 20, 430];
$vpd = (view == "exploded" || explode > 0) ? 3000 : 2400;

// ===========================================================================
//  SUB-ASSEMBLIES
// ===========================================================================

// --- structural aluminium ---------------------------------------------------
// viz() tags: each physical part on its own for the Fusion scene (2026-10-07).
module frame_group() {
    if (viz("zbase")) translate([0, 0, -ex(1.0)]) base_plate();
    if (viz("zprofile"))
        for (s = [-1, 1]) translate([0, ex(0.6), 0]) column_profile(s*column_profile_x);
    if (viz("ztie")) translate([0, 0, ex(0.8)]) column_tie(bf12_z0 - tie_plate_thk);
    if (viz("zextras")) frame_extras();
}

// Small parts on the frame, split out so check_collisions.scad can pair them
// with the enclosure without copying their positions.
module frame_extras() {
    // Cable strain relief in the electronics bay, bolted down onto the base
    // plate (+5 = half its height; +6 left it floating 1 mm up). The other
    // relief is drawn with the chain, on its fixed-end bracket: it used to
    // stand behind the posts, where the rear panel has closed the column
    // since - it ran 6 mm into the panel (enclosure_vs_frame_extras).
    translate([-60, base_plate_rear + 40, backbone_z0 + 5]) strain_relief();

    // emergency stop mounting bracket (hole + fixings only, no electronics)
    translate([base_plate_w/2 - 40, base_plate_rear + 30, backbone_z0 + 35])
        rotate([0, 0, 90]) estop_bracket();
}

// --- linear guides ----------------------------------------------------------
module rail_group() {
    for (s = [-1, 1])
        translate([s*rail_x, y_rail_plane + ex(1.1), rail_z0]) hgr20_rail();
}

module block_group(z) {
    for (s = [-1, 1], b = [-1, 1])
        translate([s*rail_x, y_rail_plane + ex(1.6), z + b*blk_pitch/2])
            hgh20_block();
}

// --- moving carriage --------------------------------------------------------
module carriage_group(z) {
    if (viz("zplate")) translate([0, ex(2.3), z]) {
        moving_plate();
        trigger_tab(trigger_tab_x);
    }

    // ball nut housing bolts to the rear of the plate; the nut sits in its
    // counterbore from below.
    if (viz("znuthsg")) translate([0, screw_axis_y + ex(1.9), z]) nut_housing();
    if (viz("zballnut")) translate([0, screw_axis_y + ex(1.5), z - nut_hsg_h/2]) ball_nut();

    // arm interface plates. Generic rectangular pattern - NOT a PAR6 pattern.
    if (show_single_arm_mount && !show_dual_arm_mount && viz("zarmif"))
        translate([0, ex(3.2), z]) arm_interface();
    if (show_dual_arm_mount && viz("zarmif"))
        for (s = [-1, 1]) translate([s*dual_arm_offset_x, ex(3.2), z]) arm_interface();
}

// --- drive train ------------------------------------------------------------
module drive_group() {
    translate([0, screw_axis_y, 0]) {
        if (!show_belt_drive) {
            if (viz("screw"))    translate([0, 0, screw_bot_z]) ball_screw();
            if (viz("coupling")) translate([0, 0, coupling_bot_z - ex(1.6)]) coupling();
            if (viz("motor"))    translate([0, 0, motor_face_z - ex(2.4)]) nema23();
            // The brake is INTEGRATED and drawn from the flange face down, so
            // it is placed at the flange, not stacked behind the motor body.
            if (show_brake && viz("brake"))
                translate([0, 0, motor_face_z - ex(2.4)]) brake_placeholder();
        } else {
            // OPTIONAL: belt reduction. The motor moves off-axis, which frees
            // the whole volume under BK12. Direct coupling stays the default.
            translate([0, 0, screw_bot_z]) ball_screw();
            translate([0, 0, motor_face_z - 30]) belt_drive_option();
        }

        // bearing supports and their pads
        if (viz("bearings")) {
            translate([0, 0, bk12_z0 + ex(1.2)]) {
                bk12();
                screw_support_pad(bk12_axial, bk12_width, bk12_pad_drop);
            }
            translate([0, 0, bf12_z0 + ex(1.2)]) {
                bf12();
                screw_support_pad(bf12_axial, bf12_width, bf12_pad_drop);
            }
        }
    }

    // TMC5160 in the electronics bay
    if (viz("driver"))
        translate([-70, base_plate_rear + 45, backbone_z0 + 40])
            rotate([0, 0, 90]) driver_pcb();
}

// --- safety and sensing -----------------------------------------------------
module safety_group(z) {
    // lower pads sit on the base plate, inboard of the profiles
    for (s = [-1, 1]) translate([s*stop_lo_x, 0, stop_lo_z1]) stop_pad(-1);
    // upper pads bolt to the front face of each column profile just above the
    // rail end, and catch the top faces of the upper pair of carriage blocks
    for (s = [-1, 1]) translate([s*rail_x, 0, stop_hi_z0]) stop_pad(1, column_profile_w);

    // limit switches on the outer face of the RIGHT profile.
    // The cable chain runs on the LEFT, so the two never meet.
    sx = rail_x + column_profile_w/2;
    translate([sx + ex(1.3), 36, sw_lo_z]) limit_switch();
    translate([sx + ex(1.3), 36, sw_hi_z]) mirror([0, 0, 1]) limit_switch();
}

// --- everything -------------------------------------------------------------
module lift_assembly(z) {
    if (show_frame)       frame_group();
    if (show_rails)     { rail_group(); block_group(z); }
    if (show_carriage)    carriage_group(z);
    if (show_motor)       drive_group();
    if (show_frame)       safety_group(z);
    if (show_cable_chain) translate([-ex(1.6), 0, 0]) cable_chain(z);

    if (show_enclosure) {
        translate([ ex(2.2), 0, 0]) side_cover(1);
        translate([-ex(2.2), 0, 0]) side_cover(-1);
        translate([0, ex(1.4), 0]) screw_guard_lower();
        translate([0, ex(1.4), 0]) screw_guard_upper();
        translate([0, 0, ex(1.8)]) top_cap();
        translate([0, -ex(2.0), 0]) driver_box();
    }

    // Ghost of the existing Mobile_Manipulator_V1 chassis - NOT part of this
    // design, drawn only so the motor bay can be judged against it.
    if (show_context) chassis_context();
}

// ===========================================================================
//  DIMENSION OVERLAY
// ===========================================================================
// ANNOTATION TEXT ORIENTATION
// The front view puts the camera at +Y looking towards -Y, so the machine's
// +X appears on the LEFT of the image. Text extruded facing +Y would read
// backwards. rotate([90,0,180]) faces it at the camera AND runs its reading
// direction along -X, which is left-to-right on screen. Everything is
// halign="center" so no offset has to be reasoned about in a flipped axis.
module dim_text(pos, label, size = 20) {
    translate(pos) rotate([90, 0, 180])
        linear_extrude(1) text(label, size = size, halign = "center",
                               valign = "center");
}

module dim_v(x, y, z0, z1, label, frac = 0.5) {
    color([0.05, 0.05, 0.05]) {
        translate([x, y, z0]) cylinder(d = 2, h = z1 - z0);
        for (z = [z0, z1]) translate([x, y, z]) sphere(d = 7);
        dim_text([x, y, z0 + frac*(z1 - z0)], label);
    }
}

module dim_h(z, y, x0, x1, label, above = true) {
    color([0.05, 0.05, 0.05]) {
        translate([x0, y, z]) rotate([0, 90, 0]) cylinder(d = 2, h = x1 - x0);
        for (x = [x0, x1]) translate([x, y, z]) sphere(d = 7);
        dim_text([(x0 + x1)/2, y, z + (above ? 26 : -26)], label);
    }
}

module dimension_overlay(z) {
    yd = y_plate_front + 20;      // annotation plane, in front of everything

    // vertical chain, staggered so the labels never overlap
    dim_v(-520, yd, 0, backbone_z1, str("overall ", backbone_z1), 0.30);
    dim_v(-360, yd, carriage_z_min, carriage_z_max,
          str("travel ", round(z_travel)), 0.62);
    dim_v( 470, yd, 0, z, str("carriage @ ", round(z)), 0.5);

    // widths
    dim_h(backbone_z1 + 60,  yd, -plate_w/2, plate_w/2,
          str("moving plate ", plate_w));
    dim_h(backbone_z1 + 140, yd, -rail_x, rail_x,
          str("rail c/c ", rail_spacing));
    dim_h(-50, yd, -base_plate_w/2, base_plate_w/2,
          str("base ", base_plate_w, " x ", base_plate_d), false);

    // LOW / MID / HIGH tick marks
    for (p = [[0, "LOW"], [z_travel/2, "MID"], [z_travel, "HIGH"]])
        color([0.9, 0.3, 0.1]) {
            translate([plate_w/2 + 20, yd, carriage_z_min + p[0]])
                rotate([0, 90, 0]) cylinder(d = 4, h = 34);
            dim_text([340, yd, carriage_z_min + p[0]], p[1], 24);
        }
}

// ===========================================================================
//  RENDER
// ===========================================================================
if (render_assembly) {
    lift_assembly(cz);
    if (show_dimensions) dimension_overlay(cz);
}

print_report();
echo(str("  carriage_position_mm = ", carriage_position_mm,
         "  ->  plate centre Z = ", cz));
echo(str("  LOW = 0   MID = ", z_travel/2, "   HIGH = ", z_travel));
if (carriage_position_mm < 0 || carriage_position_mm > z_travel)
    echo("WARNING: carriage_position_mm is outside the travel and was CLAMPED.");
