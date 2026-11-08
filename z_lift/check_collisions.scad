// ############################################################################
//  check_collisions.scad  -  runnable interference check
//
//  Renders the INTERSECTION of two sub-assemblies. An empty result, or a
//  result with zero thickness (parts that merely touch face to face), means
//  no interference. Run one test at a time:
//
//      openscad -o out.stl --export-format=asciistl \
//               -D 'test="chain_vs_screw"' check_collisions.scad
//
//  check_collisions.sh runs every test and measures the result.
//
//  HOW THE MOVING PARTS ARE SWEPT
//    The carriage only ever translates along Z, so the swept volume of a part
//    is exactly hull(part@zlo, part@zhi) PROVIDED the part is a box. hull()
//    of a non-convex part would fill its concavities and raise false alarms
//    (a hull of the moving plate fills the whole space between its rear ribs
//    and its front face, which then "collides" with BK12).
//
//    So every moving part is represented here by an ENVELOPE built from
//    boxes, derived from the same parameters as the real geometry. The
//    envelope ignores holes and pockets, which makes it CONSERVATIVE: an
//    empty intersection is a guaranteed pass.
//
//    If you change a moving part in components.scad, change its envelope
//    here too - that duplication is the price of an exact sweep.
//
//  WHAT THIS DOES NOT CHECK
//    Deflection, fastener strength, screw column buckling, thermal growth,
//    or whether the axis back-drives. Those need real analysis and testing.
// ############################################################################

include <main.scad>

test            = "list";
render_assembly = false;    // we want the intersection only, not the model

zlo = carriage_z_min;
zhi = carriage_z_max;

// Exact prismatic sweep along Z. Each DIRECT CHILD is hulled on its own -
// hulling a group of boxes together would fill the space between them and
// invent collisions that do not exist.
module sweep(z0 = undef, z1 = undef) {
    for (i = [0 : $children - 1])
        hull() {
            translate([0, 0, is_undef(z0) ? zlo : z0]) children(i);
            translate([0, 0, is_undef(z1) ? zhi : z1]) children(i);
        }
}

// ===========================================================================
//  ENVELOPES OF THE MOVING ASSEMBLY  (Z = 0 at the moving plate centre)
// ===========================================================================
module env_plate() {
    translate([-plate_w/2, y_carriage_face, -plate_h/2])
        cube([plate_w, plate_thk, plate_h]);
}
// one box at a time, so each can be swept on its own
module env_rib_h(s, z) {
    translate([s > 0 ? rib_gap_x : -rib_span, y_carriage_face - rib_depth,
               z*(plate_h/2) - (z > 0 ? rib_h : 0)])
        cube([rib_span - rib_gap_x, rib_depth, rib_h]);
}
module env_rib_v(s) {
    translate([s*rib_x - rib_thk/2, y_carriage_face - rib_depth, -plate_h/2])
        cube([rib_thk, rib_depth, plate_h]);
}
module env_ribs() {
    if (show_ribs) {
        for (s = [-1, 1]) { for (z = [-1, 1]) env_rib_h(s, z); env_rib_v(s); }
    }
}
module env_nuthsg() {
    translate([-nut_hsg_w/2, nut_hsg_y0, -nut_hsg_h/2])
        cube([nut_hsg_w, nut_hsg_depth, nut_hsg_h]);
}
module env_tab() {
    translate([trigger_tab_x - 12, 68, -24])
        cube([24, y_carriage_face - 68, 48]);
}
module env_arm_one(x) {
    translate([x - arm_iface_w/2, y_plate_front, -arm_iface_h/2])
        cube([arm_iface_w, arm_iface_thk, arm_iface_h]);
}
function arm_x_list() =
    show_dual_arm_mount ? [-dual_arm_offset_x, dual_arm_offset_x] : [0];
module env_chain_bracket() { chain_moving_bracket(); }   // the real part, not a copy

// swept versions - one box per sweep() call
module moving_ribs_swept() {
    if (show_ribs) {
        for (s = [-1, 1]) {
            for (z = [-1, 1]) sweep() env_rib_h(s, z);
            sweep() env_rib_v(s);
        }
    }
}
module moving_arms_swept() { for (x = arm_x_list()) sweep() env_arm_one(x); }

module moving_swept() {
    sweep() env_plate();
    sweep() env_nuthsg();
    sweep() env_tab();
    sweep() env_chain_bracket();
    moving_ribs_swept();
    moving_arms_swept();
}
// the carriage without the nut housing: the housing is SUPPOSED to enclose
// the screw, so it is excluded from screw clearance tests
module moving_no_nut() {
    sweep() env_plate();
    sweep() env_tab();
    sweep() env_chain_bracket();
    moving_ribs_swept();
    moving_arms_swept();
}
module blocks_swept() {
    for (s = [-1, 1], b = [-1, 1])
        sweep(zlo + b*blk_pitch/2, zhi + b*blk_pitch/2)
            translate([s*rail_x - blk_w/2, y_rail_plane, -blk_len/2])
                cube([blk_w, blk_h, blk_len]);
}

// Cable chain corridor: the whole volume the chain can occupy over the
// travel, as one box per run plus the loop band.
module chain_swept() {
    lo = chain_bend_z(zlo) - (chain_bend_r + chain_thk/2);
    translate([chain_x - chain_w/2, chain_fixed_y - chain_thk/2, lo])
        cube([chain_w, (chain_moving_y - chain_fixed_y) + chain_thk,
              chain_fixed_z + 10 - lo]);
}

// ===========================================================================
//  FIXED GROUPS  (real geometry, no sweep needed)
// ===========================================================================
module bearings() {
    translate([0, screw_axis_y, 0]) {
        translate([0, 0, bk12_z0]) { bk12(); screw_support_pad(bk12_axial, bk12_width, bk12_pad_drop); }
        translate([0, 0, bf12_z0]) { bf12(); screw_support_pad(bf12_axial, bf12_width, bf12_pad_drop); }
    }
}
module screw_only()  { translate([0, screw_axis_y, screw_bot_z]) ball_screw(); }
module rails_only()  { rail_group(); }
module risers_only() { for (s = [-1, 1]) column_profile(s*column_profile_x); }
module stops_only()  {
    for (s = [-1, 1]) translate([s*stop_lo_x, 0, stop_lo_z1]) stop_pad(-1);
    for (s = [-1, 1]) translate([s*rail_x,   0, stop_hi_z0]) stop_pad(1, column_profile_w);
}
// Switch bracket + body only. The roller lever is deliberately left out -
// the trigger tab is MEANT to touch it, that is the whole point.
module switch_bodies() {
    sx = rail_x + column_profile_w/2;
    for (z = [sw_lo_z, sw_hi_z])
        translate([sx, 36, z]) {
            translate([0, -8, -46]) cube([sw_bracket_thk, sw_body[0] + 16, 58]);
            translate([sw_bracket_thk, 0, -sw_body[2]])
                cube([sw_body[1] + 10, sw_body[0], sw_body[2]]);
        }
}
// The two posts alone. Frame parts were never paired against each other, which
// is how a 300 mm tie plate ran straight through both of them unnoticed.
//
module profiles_only() {
    for (s = [-1, 1]) column_profile(s * column_profile_x);
}
module frame_only() {
    base_plate();
    backbone();
    risers_only();
}
module enclosure_only() { enclosure_all(); }

// ===========================================================================
//  TESTS
// ===========================================================================
if (test == "carriage_vs_bearings")  intersection() { moving_swept();  bearings(); }
if (test == "carriage_vs_frame")     intersection() { moving_swept();  frame_only(); }
if (test == "carriage_vs_screw")     intersection() { moving_no_nut(); screw_only(); }
if (test == "carriage_vs_rails")     intersection() { moving_no_nut(); rails_only(); }
if (test == "carriage_vs_blocks")    intersection() { moving_no_nut(); blocks_swept(); }
if (test == "carriage_vs_stops_lo")  intersection() {
                                        translate([0, 0, zlo]) { env_plate(); env_ribs(); }
                                        stops_only(); }
if (test == "carriage_vs_stops_mid") intersection() {
                                        translate([0, 0, (zlo + zhi)/2])
                                            { env_plate(); env_ribs(); }
                                        stops_only(); }
if (test == "carriage_vs_stops_hi")  intersection() {
                                        for (s = [-1, 1], b = [-1, 1])
                                            translate([s*rail_x, y_rail_plane,
                                                       zhi + b*blk_pitch/2])
                                                hgh20_block();
                                        stops_only(); }
if (test == "blocks_vs_frame")       intersection() { blocks_swept(); frame_only(); }
if (test == "tie_vs_profiles")       intersection() {
                                        column_tie(bf12_z0 - tie_plate_thk);
                                        profiles_only(); }
if (test == "baseplate_vs_profiles") intersection() { base_plate(); profiles_only(); }
// Panels were never tested against the frame either - only against the moving
// parts. The side covers' rear return flanges reach into the profile band.
if (test == "enclosure_vs_profiles") intersection() {
                                        enclosure_only(); profiles_only(); }
// Nor against the frame's small parts. When the side covers' rear legs were
// extended to close the back of the column, the upper cable strain relief -
// which stood behind the profiles - ended up inside the new rear panel. It
// showed on a Fusion render (2026-09-25), with every test green. That relief
// now sits on the chain's fixed bracket; the chain_end tests below guard it.
if (test == "enclosure_vs_frame_extras") intersection() {
                                        enclosure_only(); frame_extras(); }
if (test == "chain_end_vs_enclosure")   intersection() {
                                        enclosure_only(); chain_fixed_end(); }
if (test == "chain_end_vs_moving")      intersection() {
                                        chain_fixed_end();
                                        union() { moving_swept(); blocks_swept(); } }
// touching is expected: the bracket bolts to the post's outer face
if (test == "chain_end_vs_profiles")    intersection() {
                                        chain_fixed_end(); profiles_only(); }
if (test == "chain_vs_screw")        intersection() { chain_swept(); screw_only(); }
if (test == "chain_vs_rails")        intersection() { chain_swept(); rails_only(); }
if (test == "chain_vs_blocks")       intersection() { chain_swept(); blocks_swept(); }
if (test == "chain_vs_risers")       intersection() { chain_swept(); risers_only(); }
if (test == "chain_vs_enclosure")    intersection() { chain_swept(); enclosure_only(); }
if (test == "chain_vs_stops")        intersection() { chain_swept(); stops_only(); }
if (test == "chain_vs_bearings")     intersection() { chain_swept(); bearings(); }
if (test == "enclosure_vs_moving")   intersection() { enclosure_only(); moving_swept(); }
if (test == "enclosure_vs_blocks")   intersection() { enclosure_only(); blocks_swept(); }
if (test == "enclosure_vs_bearings") intersection() { enclosure_only(); bearings(); }
if (test == "enclosure_vs_screw")    intersection() { enclosure_only(); screw_only(); }
if (test == "switches_vs_moving")    intersection() { switch_bodies(); moving_swept(); }
if (test == "switches_vs_blocks")    intersection() { switch_bodies(); blocks_swept(); }
if (test == "stops_vs_rails")        intersection() { stops_only(); rails_only(); }

// The support pads sit directly under the bearings, and the screw's machined
// end plus (at the bottom) the coupling run down through them. A solid ledge
// there is a real interference and is easy to miss by eye.
module bk12_pad_only() {
    translate([0, screw_axis_y, bk12_z0]) screw_support_pad(bk12_axial, bk12_width, bk12_pad_drop);
}
module bf12_pad_only() {
    translate([0, screw_axis_y, bf12_z0]) screw_support_pad(bf12_axial, bf12_width, bf12_pad_drop);
}
module screw_pads_only() { bk12_pad_only(); bf12_pad_only(); }

// The brackets are drawn with their real bend since 2026-09-25, and the bend
// is what these two pairings are about. The BK12 one passes over the rear
// NEMA23 bolt heads (flush countersunk, motor_bolt_head); the BF12 one comes
// up through a slot in the tie shelf and hangs its foot under it - touching
// the shelf's underside is the expected result there.
if (test == "pads_vs_motor_bolts")  intersection() { bk12_pad_only(); motor_bolt_heads(); }
if (test == "bf12_pad_vs_tie")      intersection() {
                                        bf12_pad_only();
                                        column_tie(bf12_z0 - tie_plate_thk); }
module rotating_parts() {
    translate([0, screw_axis_y, screw_bot_z]) ball_screw();
    translate([0, screw_axis_y, coupling_bot_z]) coupling();
}
if (test == "rotating_vs_pads")     intersection() { rotating_parts(); screw_pads_only(); }
if (test == "screw_vs_bearings")
    intersection() {
        translate([0, screw_axis_y, screw_bot_z]) ball_screw();
        union() {
            translate([0, screw_axis_y, bk12_z0]) bk12();
            translate([0, screw_axis_y, bf12_z0]) bf12();
        }
    }

// --- the motor bay against the existing mobile base -------------------------
// motor_install_envelope() is the motor + integrated brake + wiring + cover,
// i.e. what actually has to fit, not the bare motor body.
if (test == "motorbay_vs_battery")
    intersection() { motor_install_envelope(); chassis_battery(); }
// Frame members the motor can never pass through - this one must be CLEAR.
if (test == "motorbay_vs_structure")
    intersection() { motor_install_envelope(); chassis_structure(); }
// Intersection with the column plate is the required BORE, not a fault. It is
// listed so its size is visible; compare it against plate_edge_margin.
if (test == "motorbay_bore_in_plate")
    intersection() { motor_install_envelope(); chassis_column_plate(); }
if (test == "motor_bare_vs_battery")
    intersection() {
        translate([-motor_body/2, screw_axis_y - motor_body/2, motor_stack_bot])
            cube([motor_body, motor_body, -motor_stack_bot]);
        chassis_battery();
    }

// dual arm variant. The runner passes -D show_dual_arm_mount=true
if (test == "dualarm_vs_rails")
    intersection() {
        moving_arms_swept();
        union() { rails_only(); risers_only(); blocks_swept(); }
    }
if (test == "dualarm_vs_enclosure")
    intersection() { moving_arms_swept(); enclosure_only(); }

// numeric checks that are not about volume intersection
if (test == "list") {
    echo("--- alignment / envelope checks -------------------------------");
    echo(str("motor axis      X,Y = 0, ", screw_axis_y));
    echo(str("coupling axis   X,Y = 0, ", screw_axis_y));
    echo(str("screw axis      X,Y = 0, ", screw_axis_y, "   -> concentric"));
    echo(str("BK12 bore axis  X,Y = 0, ", screw_axis_y));
    echo(str("BF12 bore axis  X,Y = 0, ", screw_axis_y));
    echo(str("motor shaft top Z   = ", shaft_top_z,
             "   coupling spans Z ", coupling_bot_z, "..", coupling_top_z,
             "   grip on motor shaft = ", shaft_top_z - coupling_bot_z));
    echo(str("screw bottom Z      = ", screw_bot_z,
             "   grip in coupling  = ", coupling_top_z - screw_bot_z));
    echo(str("screw spans Z       = ", screw_bot_z, "..", screw_top_z,
             "   BK12 ", bk12_z0, "..", bk12_z1,
             "   BF12 ", bf12_z0, "..", bf12_z1));
    echo(str("nut housing bore    = ", nut_body_d + 1, " for a ", screw_d, " screw"));
    echo(str("nut housing Z LOW   = ", zlo - nut_hsg_h/2, "..", zlo + nut_hsg_h/2,
             "   clear above BK12 by ", (zlo - nut_hsg_h/2) - bk12_z1));
    echo(str("nut housing Z HIGH  = ", zhi - nut_hsg_h/2, "..", zhi + nut_hsg_h/2,
             "   clear below BF12 by ", bf12_z0 - (zhi + nut_hsg_h/2)));
    echo(str("dual arm plate X    = ", dual_arm_offset_x - arm_iface_w/2, "..",
             dual_arm_offset_x + arm_iface_w/2,
             "   moving plate edge ", plate_w/2));
    echo(str("cable chain X       = ", chain_x - chain_w/2, "..", chain_x + chain_w/2,
             "   profil outer ", -(rail_x + column_profile_w/2),
             "   side cover inner ", -backbone_w/2));
    echo(str("chain loop bottom Z = ",
             chain_bend_z(zlo) - (chain_bend_r + chain_thk/2), " (low) .. ",
             chain_bend_z(zhi) - (chain_bend_r + chain_thk/2), " (high)",
             "   base plate top ", backbone_z0));
    echo(str("hard stop overtravel= lower ",
             (zlo - plate_h/2) - stop_lo_z1, "   upper ", stop_hi_gap));
    echo("--------------------------------------------------------------");
}
