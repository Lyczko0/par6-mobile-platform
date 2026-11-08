// ############################################################################
//  coupons.scad - print coupons. NOT robot parts: test_rig/, nothing here
//  belongs in BOM_V1.md. Each one replaces a guess with a measurement.
//
//  wall_plain, wall_fluted - WEIGH them. The cover masses in
//    mobile_base/base_masses.scad (cover_kg, col_shell_kg) span 55 % of solid
//    (the slicer on wall_fluted, 2 walls, 2026-10-04) to solid PETG. Print
//    them with the settings the covers will get, then mass / (volume x
//    density) is the real fill - and the scale checks the slicer.
//  inserts - which hole a heat-set insert holds in: insert_m4_d (5.6, the
//    cover screws) and boss_insert_d (4.2, M3 of the column shell) are both
//    [VERIFY]. M4 row front, M3 row back, sizes engraved on the side faces.
//  bracket_stub - the outer 40 mm of a real side_brackets() part, insert
//    hole in its end face, printed lying as the bracket will. With a wall
//    coupon and an M4 x 10 it is the side-cover joint: does the 3 mm wall
//    crack under the head, does the insert hold (Lyczko0 2026-10-04: the
//    walls had no holes - they were for weighing only, now both).
//  seam_halves, seam_splice - the joint proposed 2026-10-05 for the covers
//    that do not fit the 250 bed: butt joint in a flute valley plus a glued
//    20 x 2 mm splice strip on the inside. Glue, then judge two things: is
//    the seam visible from a metre, and does it break before the wall does.
//  seat_gauge - drive_seat() itself, 1:1, groove up. Real axle in the groove
//    (flat up), ORIGINAL strap on top, no screws: the gap under the strap
//    feet is the clamp. Read it with paper strips (~0.1 mm each), and the
//    same gap on the hoverboard frame - they should match. Then the four
//    original screws: straight in, or seat_pitch (+/-1 from the casting) is
//    off. Closes wheel_mount.py: groove depth, strap gap, pitch, screw size.
//  par6_plate - under the PAR6 base: the adapter's four bolts (par6_bolt_xy)
//    and the cable hole, as long as the base is wide (par6_base_y). M5
//    through all four and both ends flush with the sides of the base = the
//    CAD is 1:1, which closes the three [VERIFY] readings in par6_arm.scad.
//  Z-axis parts: coupons_z.scad (z_lift clashes with this include).
//
//  Same geometry as the covers, not copies: wall, flutes, holes and the
//  bracket come from the model, so a change there changes the coupon too.
//
//  openscad -D 'part="wall_fluted"' -o coupons_stl/wall_fluted.stl coupons.scad
// ############################################################################
include <../mobile_base/base_covers.scad>   // draws nothing on its own

part   = "wall_fluted";   // wall_plain | wall_fluted | inserts | bracket_stub
                          // | seam_halves | seam_splice | seat_gauge | par6_plate
coupon = 100;              // mm square

// Lies as it prints: wall on the bed, flutes up. Two side-cover screw holes
// (cover_screw_hole) on flat wall between the flutes.
module wall(fluted) {
    difference() {
        union() {
            cube([coupon, coupon, cover_thk]);
            if (fluted)
                for (x = [col_flute_pitch / 2 : col_flute_pitch : coupon - col_flute_w])
                    translate([x, 0, cover_thk]) cube([col_flute_w, coupon, col_flute_d]);
        }
        for (x = [27, 75])
            translate([x, coupon / 2, -1]) cylinder(d = cover_screw_hole, h = 10, $fn = 48);
    }
}

// The outer 40 mm of the first left bracket, moved to the origin: insert
// face up the Y axis, as side_brackets() draws it on the robot.
stub = 40;
module bracket_stub() {
    x0 = side_bracket_x[0];
    translate([-(x0 - side_bracket_w / 2), -(cover_side_y - stub),
               -(frame_bottom_z - side_bracket_h)])
        intersection() {
            side_brackets();
            translate([x0 - side_bracket_w, cover_side_y - stub, 0])
                cube([2 * side_bracket_w, stub + 1, frame_bottom_z + 1]);
        }
}

m4_holes = [insert_m4_d - 0.2, insert_m4_d, insert_m4_d + 0.2];
m3_holes = [boss_insert_d - 0.2, boss_insert_d, boss_insert_d + 0.2];
pitch = 16;
block = [3 * pitch, 32, 12];

// one decimal always - str(4.0) is "4"
function fmt(x) = str(floor(x), ".", round((x - floor(x)) * 10));

module label(t, y, rot) {
    translate([0, y, block[2] / 2]) rotate([90, 0, rot])
        linear_extrude(1.2, center = true)
            text(t, size = 3.5, halign = "center", valign = "center");
}

module inserts() {
    difference() {
        cube(block);
        for (i = [0 : 2]) {
            // M4 front row, 9 deep; M3 back row, 7 deep
            translate([pitch / 2 + i * pitch, 9, block[2] - insert_m4_l - 1])
                cylinder(d = m4_holes[i], h = insert_m4_l + 2, $fn = 64);
            translate([pitch / 2 + i * pitch, block[1] - 9, block[2] - 7])
                cylinder(d = m3_holes[i], h = 8, $fn = 64);
            translate([pitch / 2 + i * pitch, 0, 0])
                label(fmt(m4_holes[i]), 0, 0);
            translate([pitch / 2 + i * pitch, 0, 0])
                label(fmt(m3_holes[i]), block[1], 180);
        }
    }
}

// Cut in the middle valley (ribs 36..42 and 60..66), the two halves printed
// 10 mm apart. Valley k: pitch/2 + k*pitch + (pitch + flute_w)/2.
seam_x = col_flute_pitch * 1.5 + (col_flute_pitch + col_flute_w) / 2;
splice = [20, coupon - 10, 2];

module seam_halves() {
    intersection() { wall(true); cube([seam_x, coupon, 20]); }
    translate([10, 0, 0]) difference() { wall(true); translate([-1, -1, -1]) cube([seam_x + 1, coupon + 2, 20]); }
}

// The seat moved to the origin, lying as it prints: groove up. Fine facets -
// the model's $fs 1.2 would make the groove a polygon the axle rocks in.
module seat_gauge() {
    $fn = 96;
    translate([-(drive_axle_x - seat_w / 2), -seat_y0, -(seat_top_z - seat_h)])
        drive_seat();
}

// 2 mm under the PAR6 base, 12 mm past the outer bolts in X.
module par6_plate() {
    xs = [for (p = par6_bolt_xy) p[0]];
    linear_extrude(2) difference() {
        translate([min(xs) - 12, par6_base_y[0]])
            square([max(xs) - min(xs) + 24, par6_base_y[1] - par6_base_y[0]]);
        for (p = par6_bolt_xy) translate(p) circle(d = par6_bolt_d, $fn = 48);
        circle(d = par6_cable_d, $fn = 48);
    }
}

if (part == "wall_plain")  wall(false);
if (part == "wall_fluted") wall(true);
if (part == "inserts")     inserts();
if (part == "bracket_stub") bracket_stub();
if (part == "seam_halves") seam_halves();
if (part == "seam_splice") cube(splice);
if (part == "seat_gauge")  seat_gauge();
if (part == "par6_plate")  par6_plate();
