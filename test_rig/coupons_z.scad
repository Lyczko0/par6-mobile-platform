// ############################################################################
//  coupons_z.scad - hole patterns for the Z-axis parts already on the bench
//  (BOM 5.2-5.6, all MAM), 2 mm, one print. NOT robot parts: test_rig/.
//  Own file because z_lift and mobile_base clash in one include.
//
//  Each pad carries the pattern the PCBWay part will get, from the same
//  parameters. Lay the part on its pad and put its own screws through:
//    nut    - the nut bracket shelf (nut_housing() cut at mid-sheet), only a
//             ring round the flange: SFU1605 flange bolts and body bore
//    block  - one HGH20CA on the moving plate, outline blk_w x blk_len
//    bk12   - BK12 / BF12 bolts, width bk12_width
//    nema23 - nema23_pattern() of the base plate, outline motor_body
//  All screws in at once without forcing = those [VERIFY] numbers hold.
//  Printed holes come out ~0.2 small: tight is fine, a screw that has to
//  bend is not - then measure how far off it sits, not the part.
//
//  openscad -o coupons_stl/z_patterns.stl coupons_z.scad
//  openscad -D 'pad="nut"' -o coupons_stl/z_nut_v2.stl coupons_z.scad
//    v2 (2026-10-10): flange bolts at 0/45/135/180/225/315 - on v1 (every
//    60 deg) only the 0/180 pair fitted
// ############################################################################
include <../z_lift/components.scad>

pad = "all";   // all | nut
t   = 2;
$fs = 0.3;   // the model's 1.0 makes an M5 clearance hole a 17-gon

assert(bf12_bolt_pitch == bk12_bolt_pitch, "BF12 needs its own pad");

module tag(s, y = 0, size = 3) {
    translate([0, y, t - 0.6]) linear_extrude(1)
        text(s, size = size, halign = "center", valign = "center");
}

// The shelf's own holes, cut down to a ring 3 mm past the flange - the rest of
// the shelf is plain plate (Lyczko0 2026-10-10: no filament for it).
module nut_pad() {
    difference() {
        linear_extrude(t) intersection() {
            projection(cut = true)
                translate([0, 0, nut_hsg_h / 2 - nut_bracket_thk / 2]) nut_housing();
            circle(d = nut_flange_d + 6);
        }
        tag("v2", 21);          // 90 deg, where the flange is flatted - no hole
    }
}

module block_pad() {
    difference() {
        translate([-blk_w / 2, -blk_len / 2, 0]) cube([blk_w, blk_len, t]);
        for (x = [-1, 1], y = [-1, 1])
            translate([x * blk_bolt_x / 2, y * blk_bolt_z / 2, -1])
                cylinder(d = blk_bolt_d + 0.4, h = t + 2);
        tag(str("HGH20 ", blk_bolt_x, "x", blk_bolt_z));
    }
}

module bk12_pad() {
    difference() {
        translate([-bk12_width / 2, -10, 0]) cube([bk12_width, 20, t]);
        for (x = [-1, 1])
            translate([x * bk12_bolt_pitch / 2, 0, -1]) cylinder(d = bk12_bolt_d + 0.5, h = t + 2);
        tag(str("BK BF ", bk12_bolt_pitch));
    }
}

module nema_pad() {
    difference() {
        translate([-motor_body / 2, -motor_body / 2, 0]) cube([motor_body, motor_body, t]);
        nema23_pattern(t);
        tag(str("NEMA23 ", motor_bolt_pitch), -motor_body / 2 + 4);
    }
}

// one bed, 10 mm apart
row2 = nut_hsg_depth + 10;
translate([nut_hsg_w / 2, screw_axis_y - nut_hsg_y0]) nut_pad();   // shelf from Y 0
if (pad == "all") {
    translate([nut_hsg_w + 10 + motor_body / 2, motor_body / 2]) nema_pad();
    translate([blk_w / 2, row2 + blk_len / 2]) block_pad();
    translate([blk_w + 10 + bk12_width / 2, row2 + 10]) bk12_pad();
}
