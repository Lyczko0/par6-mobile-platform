// ############################################################################
//  components.scad  -  every metal / hardware part of the Z-LIFT
//
//  CONVENTION
//    * Purchased hardware (rail, block, screw, nut, BK12, motor...) is drawn
//      in a LOCAL frame and placed by the caller. Local frames are documented
//      per module.
//    * One-off structural parts (backbone, base plate, risers) are
//      drawn directly in GLOBAL X/Y coordinates, and only their Z is local
//      where the part moves.
//    * Modules that move with the carriage take the plate centre height as
//      their Z origin, so main.scad only has to translate once.
//
//  Everything here is a SIMPLIFIED representation. Bearing internals, seals,
//  ball returns, chamfers and thread forms are not modelled - they do not
//  change the envelope or the interference behaviour.
// ############################################################################

include <parameters.scad>

// ---------------------------------------------------------------------------
//  generic helpers
// ---------------------------------------------------------------------------

// A slotted hole: two circles hulled together. len = total length tip to tip.
module slot(len, d, h) {
    hull() for (s = [-1, 1])
        translate([s*(len - d)/2, 0, 0]) cylinder(d = d, h = h, center = true);
}

// M3 heat-set insert boss for the printed panels.
module m3_boss(h = panel_boss_h) {
    difference() {
        cylinder(d = panel_boss_d, h = h);
        translate([0, 0, -0.5]) cylinder(d = panel_insert_d, h = h);
    }
}

// A row of ventilation slots lying in the XY plane, extruded through +Z.
module vent_row(n, len = vent_len, w = vent_w, pitch = vent_pitch, h = 10) {
    for (i = [0 : n-1])
        translate([0, (i - (n-1)/2) * pitch, -h/2]) slot(len, w, h*2);
}

// ###########################################################################
//  1.  LINEAR MOTION HARDWARE
// ###########################################################################

// HGR20 rail.
// LOCAL FRAME: X = rail width (centred), Y = 0 at the rail MOUNTING FACE and
// grows towards the block, Z = 0 at the bottom end of the rail.
module hgr20_rail(len = rail_len) {
    color(col_rail)
    difference() {
        translate([-rail_w/2, 0, 0]) cube([rail_w, rail_h, len]);

        // ball track grooves, one per side - purely cosmetic
        for (s = [-1, 1])
            translate([s*rail_w/2, rail_h*0.55, -1])
                rotate([0, 0, 45]) translate([-2, -2, 0]) cube([4, 4, len + 2]);

        // counterbored M5 mounting holes, opening on the TOP face
        for (z = [rail_hole_first : rail_hole_pitch : len - rail_hole_first])
            translate([0, rail_h + 1, z]) rotate([90, 0, 0]) {
                cylinder(d = rail_bolt_d + 1, h = rail_h + 2);
                cylinder(d = 9.5, h = 9.5);
            }
    }
}

// HGH20CA carriage block.
// LOCAL FRAME: X centred on the rail, Y = 0 at the rail mounting face,
// Z = 0 at the CENTRE of the block length.
module hgh20_block() {
    color(col_block)
    difference() {
        translate([-blk_w/2, 0, -blk_len/2]) cube([blk_w, blk_h, blk_len]);

        // rail relief
        translate([-(rail_w + 1)/2, -1, -blk_len/2 - 1])
            cube([rail_w + 1, rail_h + 1.5, blk_len + 2]);

        // 4 x M5 tapped holes in the top face
        for (x = [-1, 1], z = [-1, 1])
            translate([x*blk_bolt_x/2, blk_h + 1, z*blk_bolt_z/2])
                rotate([90, 0, 0]) cylinder(d = blk_bolt_d, h = 14);
    }
}

// ###########################################################################
//  2.  BALL SCREW ASSEMBLY
// ###########################################################################

// SFU1605 screw. LOCAL FRAME: axis on Z, Z = 0 at the bottom end face.
// The thread form is NOT modelled - only the envelope matters here.
// The machined end lengths are DERIVED from where BK12 and BF12 actually sit,
// not guessed: the reduced diameter has to run from the screw's end, through
// the bearing, and stop just past it where the thread begins. Hardcoding them
// leaves the O16 body sitting inside the bearing bore. [VERIFY on your kit -
// end lengths vary a lot between ball screw kits.]
module ball_screw(len = screw_len) {
    color(col_screw) {
        cylinder(d = screw_end_d, h = screw_end_lo);
        translate([0, 0, screw_end_lo])
            cylinder(d = screw_d, h = len - screw_end_lo - screw_end_hi);
        translate([0, 0, len - screw_end_hi]) cylinder(d = screw_end_d, h = screw_end_hi);
    }
}

// SFU1605 flanged ball nut. LOCAL FRAME: axis on Z, Z = 0 at the flange face.
module ball_nut() {
    color([0.55, 0.56, 0.60])
    difference() {
        union() {
            cylinder(d = nut_flange_d, h = nut_flange_thk);
            cylinder(d = nut_body_d,  h = nut_len);
        }
        translate([0, 0, -1]) cylinder(d = screw_d + 0.6, h = nut_len + 2);
        for (a = nut_bolt_a)
            rotate([0, 0, a])
                translate([nut_bolt_pcd/2, 0, -1])
                    cylinder(d = nut_bolt_d, h = nut_flange_thk + 2);
    }
}

// Ball nut BRACKET, bolted to the REAR of the moving plate.
// ONE 6 mm laser blank, three bends - no machining anywhere.
//   shelf   carries the nut flange, spans from the screw back to the plate
//   flanges bent up on both X edges, turn the shelf into a channel
//   leg     bent up at the plate face, takes 4 x M6 into the moving plate
//
// LOCAL FRAME: X centred on the screw, Y = 0 at the SCREW AXIS (global
// screw_axis_y), Z = 0 at the vertical centre of the keep-out envelope.
//
// The nut sits ON TOP of the shelf and bolts down through it. That puts the
// six M6 in tension under the carriage weight - 19 N each, which is nothing -
// and lets the whole nut live inside the 56 mm envelope. Flange underneath
// would be the textbook way round but the nut is 42 mm long and would then
// hang out of the envelope.
module nut_housing() {
    t   = nut_bracket_thk;
    y0  = nut_hsg_y0 - screw_axis_y;              // rear edge of the shelf
    y1  = y_carriage_face - screw_axis_y;         // plate face
    z0  = -nut_hsg_h/2;                           // shelf underside

    color(col_alu_d) {
        // shelf, with the nut bore and its flange bolt circle
        difference() {
            translate([-nut_hsg_w/2, y0, z0]) cube([nut_hsg_w, y1 - y0, t]);
            translate([0, 0, z0 - 1]) cylinder(d = nut_body_d + 1, h = t + 2);
            for (a = nut_bolt_a)
                rotate([0, 0, a])
                    translate([nut_bolt_pcd/2, 0, z0 - 1])
                        cylinder(d = nut_bolt_d + 0.5, h = t + 2);
        }

        // side flanges, bent up - these are what make it a channel
        for (sx = [-1, 1])
            translate([sx*(nut_hsg_w/2) - (sx > 0 ? t : 0), y0, z0 + t])
                cube([t, y1 - y0 - t, nut_bracket_flange_h]);

        // rear leg against the moving plate, 4 x M6
        difference() {
            translate([-nut_hsg_w/2, y1 - t, z0])
                cube([nut_hsg_w, t, nut_hsg_h]);
            for (x = [-1, 1], z = [-1, 1])
                translate([x*(nut_hsg_w/2 - 14), y1 + 1,
                           z*(nut_hsg_h/2 - 12)])
                    rotate([90, 0, 0]) cylinder(d = 6.5, h = t + 2);
        }
    }
}

// BK12 fixed bearing support (motor end).
// LOCAL FRAME: screw axis on Z, Z = 0 at the LOWER face of the block,
// Y = 0 at the screw axis, mounting face at y = -bk12_centre_h.
module bk12() {
    color(col_alu_d)
    difference() {
        translate([-bk12_width/2, -bk12_centre_h, 0])
            cube([bk12_width, bk12_body_h, bk12_axial]);

        translate([0, 0, -1]) cylinder(d = screw_end_d + 1, h = bk12_axial + 2);

        // bearing bore relief, visual only
        translate([0, 0, bk12_axial - 12]) cylinder(d = 32, h = 13);

        // 2 x M6 base bolts running horizontally into the pad
        for (x = [-1, 1])
            translate([x*bk12_bolt_pitch/2, -bk12_centre_h - 1, bk12_axial/2])
                rotate([-90, 0, 0]) cylinder(d = bk12_bolt_d + 0.5, h = 20);
    }
}

// BF12 floating bearing support (far end). Same local frame as bk12().
module bf12() {
    color(col_alu_d)
    difference() {
        translate([-bf12_width/2, -bf12_centre_h, 0])
            cube([bf12_width, bf12_body_h, bf12_axial]);
        translate([0, 0, -1]) cylinder(d = screw_end_d + 1, h = bf12_axial + 2);
        for (x = [-1, 1])
            translate([x*bf12_bolt_pitch/2, -bf12_centre_h - 1, bf12_axial/2])
                rotate([-90, 0, 0]) cylinder(d = bk12_bolt_d + 0.5, h = 20);
    }
}

// BK12 / BF12 bracket. Until 2026-08-19 this was a pad "against the backbone"
// that reached nothing: it stands at X +/-30, Y 29..35, and the backbone is two
// posts at X 110..150. Both bearings were held by their own bolts and air.
//
// Now it is an L in 6 mm sheet - one bend, one blank, two uses:
//   BK12  foot on the base plate, web 39 mm taller to reach up to it
//   BF12  foot UNDER the tie plate shelf, web up through a slot in it
//         (bf12_pad_drop - on top of the shelf its bolts fell in the bend)
// The old compression ledge is gone. It existed so the screw's thrust would
// not hang on two M6 in shear, but that thrust is 253 N at the design case and
// one M6 shears at about 8 kN. The ledge was solving a problem it did not have.
//
// LOCAL FRAME: screw axis on Z, Z = 0 at the bearing block's lower face.
// drop = distance down to the surface the foot bolts to.
module screw_support_pad(block_h, block_w, drop = 0) {
    t  = screw_pad_thk;
    r  = bend_r_in;
    y0 = -bk12_centre_h - t;          // web rear face; its front face is the
                                      // bearing's mounting plane
    zf = -drop;                       // underside of the foot
    cy = y0 - r;                      // bend centre: r from both inner faces
    cz = zf + t + r;
    color(col_alu)
    difference() {
        // ONE bent blank: flat foot, 90 deg bend of inner radius r, flat web.
        // Drawn with the bend since 2026-09-25 - as two boxes meeting on an
        // edge the model showed 4.7 mm to the NEMA23 bolt heads that the real
        // bend (reaching Y 35 at the web) does not have; see motor_bolt_head.
        // Folded at the web's REAR face: the foot runs back, away from the
        // motor bolts.
        rotate([90, 0, 90]) linear_extrude(block_w, center = true)
            union() {
                translate([y0, cz]) square([t, block_h + 6 - cz]);          // web
                translate([y0 - bearing_foot_d, zf])
                    square([bearing_foot_d - r, t]);                        // foot
                intersection() {                                            // bend
                    translate([cy, cz]) difference() { circle(r = r + t); circle(r = r); }
                    translate([cy, zf]) square([r + t, r + t]);
                }
            }
        // bearing bolts, horizontal into the block
        for (x = [-1, 1])
            translate([x*bk12_bolt_pitch/2, y0 - 1, block_h/2])
                rotate([-90, 0, 0]) cylinder(d = bk12_bolt_d + 0.5, h = t + 2);
        // foot bolts, into the plate below or the shelf above
        for (x = [-1, 1])
            translate([x*bk12_bolt_pitch/2, y0 - bearing_foot_d/2, -drop - 1])
                cylinder(d = bk12_bolt_d + 0.5, h = t + 2);
    }
}

// NEMA23 bolt heads standing on the base plate - nothing when they are flush
// countersunk, which is what the BK12 bracket's bend needs (motor_bolt_head).
module motor_bolt_heads() {
    if (motor_bolt_head[1] > 0)
        for (x = [-1, 1], y = [-1, 1])
            translate([x*motor_bolt_pitch/2, screw_axis_y + y*motor_bolt_pitch/2,
                       backbone_z0])
                cylinder(d = motor_bolt_head[0], h = motor_bolt_head[1]);
}

// Flexible shaft coupling. LOCAL FRAME: axis on Z, Z = 0 at the lower face.
module coupling() {
    color([0.85, 0.72, 0.25])
    difference() {
        union() {
            cylinder(d = coupling_d, h = coupling_len*0.42);
            translate([0, 0, coupling_len*0.42])
                cylinder(d = coupling_d*0.8, h = coupling_len*0.16);
            translate([0, 0, coupling_len*0.58])
                cylinder(d = coupling_d, h = coupling_len*0.42);
        }
        translate([0, 0, -1]) cylinder(d = motor_shaft_d, h = coupling_len/2 + 1);
        translate([0, 0, coupling_len/2])
            cylinder(d = screw_end_d, h = coupling_len/2 + 1);
    }
}

// ###########################################################################
//  3.  MOTOR / BRAKE / DRIVER
// ###########################################################################

// NEMA23 stepper. LOCAL FRAME: shaft axis on Z, Z = 0 at the MOUNTING FACE,
// body hanging in -Z, shaft sticking out in +Z.
module nema23() {
    color(col_motor) {
        translate([0, 0, -motor_len])
            hull() for (x = [-1, 1], y = [-1, 1])
                translate([x*(motor_body/2 - 3), y*(motor_body/2 - 3), 0])
                    cylinder(r = 3, h = motor_len);
        cylinder(d = motor_pilot_d, h = motor_pilot_h);
    }
    color(col_screw) cylinder(d = motor_shaft_d, h = motor_shaft_len);
    // 4-wire cable stub, so the cable chain entry is obvious in the model
    color([0.1, 0.1, 0.1])
        translate([0, motor_body/2 - 4, -motor_len + 8])
            rotate([-90, 0, 0]) cylinder(d = 7, h = 30);
}

// NEMA23 bolt pattern cutter. Use inside difference() on any mounting plate.
module nema23_pattern(thk, pilot = true) {
    for (x = [-1, 1], y = [-1, 1])
        translate([x*motor_bolt_pitch/2, y*motor_bolt_pitch/2, -1])
            cylinder(d = motor_bolt_d + 0.4, h = thk + 2);
    if (pilot) translate([0, 0, -1]) cylinder(d = motor_pilot_d + 2, h = thk + 2);
}

// PLACEHOLDER ONLY - the part is selected but not in hand, and nothing about
// it is validated.
//
// This is an INTEGRATED brake: it sits in line behind the motor body and adds
// its full length to the envelope hanging down into the mobile base. It is
// drawn to motor_brake_envelope (the conservative design figure), with the
// nominal 56+30 outline shown inside it so the margin is visible.
//
// LOCAL FRAME: axis on Z, Z = 0 at the motor FLANGE FACE, growing downward.
module brake_placeholder() {
    env = motor_brake_envelope;
    color(col_warn, 0.45)
        translate([0, 0, -env])
            hull() for (x = [-1, 1], y = [-1, 1])
                translate([x*(brake_d/2 - 4), y*(brake_d/2 - 4), 0])
                    cylinder(r = 4, h = env - motor_len);
    // envelope margin between the nominal stack and the design figure
    if (show_brake_margin && env > motor_len + brake_len_nominal)
        color([0.9, 0.35, 0.1], 0.18)
            translate([0, 0, -env])
                cube([motor_body + 6, motor_body + 6,
                      env - motor_len - brake_len_nominal], center = false);
}

// TMC5160 driver module envelope.
module driver_pcb() {
    color(col_elec)
        cube([driver_pcb[0], driver_pcb[1], driver_pcb[2]], center = true);
}

// OPTIONAL belt drive alternative to the direct coupling. Off by default.
// Moves the motor to one side so the total stack height below the screw
// drops - useful if you later need more floor reach. Reduction = pulley ratio.
belt_offset_x   = 90;   // motor axis offset from the screw axis
belt_pulley_d   = 40;   // screw pulley pitch diameter
belt_motor_d    = 20;   // motor pulley pitch diameter
belt_w          = 15;   // GT2/GT3 belt width
module belt_drive_option() {
    color([0.25, 0.25, 0.28]) {
        translate([0, 0, -belt_w/2]) cylinder(d = belt_pulley_d, h = belt_w);
        translate([belt_offset_x, 0, -belt_w/2])
            cylinder(d = belt_motor_d, h = belt_w);
        // belt envelope
        translate([0, 0, -belt_w/2]) linear_extrude(belt_w)
            difference() {
                hull() {
                    circle(d = belt_pulley_d + 4);
                    translate([belt_offset_x, 0]) circle(d = belt_motor_d + 4);
                }
                hull() {
                    circle(d = belt_pulley_d);
                    translate([belt_offset_x, 0]) circle(d = belt_motor_d);
                }
            }
    }
    translate([belt_offset_x, 0, -belt_w]) rotate([180, 0, 0]) nema23();
}

// ###########################################################################
//  4.  STRUCTURAL ALUMINIUM  (global X/Y, local Z where noted)
// ###########################################################################

// One T-slot column profile, 40 x 80 on edge. GLOBAL frame.
//
// The 40 mm face (front, at y_rail_plane) carries ONE CENTRED SLOT. That is
// the whole point: HGR20 has its mounting holes on its own centreline, so the
// rail bolts straight down onto hammer nuts with no drilling at all. The 80 mm
// side faces carry two slots each - brackets and the cable chain go there.
module column_profile(x) {
    sl = column_profile_slot;
    color(col_alu)
    difference() {
        translate([x - column_profile_w/2, 0, backbone_z0])
            cube([column_profile_w, column_profile_d, backbone_h]);

        // centred slot on the front and rear 40 mm faces
        for (yy = [column_profile_d - 3, -3])
            translate([x - sl/2, yy, backbone_z0 - 1])
                cube([sl, 6, backbone_h + 2]);

        // Two slots per 80 mm side face. The offset is measured from the
        // FACE and the cut straddles it - written as (w/2 - 3) the cut only
        // opened on the +X side, and on -X it became a sealed pocket 3 mm
        // inside solid extrusion. Cosmetic until the tie plate started
        // bolting into that very slot, at which point the drawing was
        // showing a joint that had nowhere to go.
        for (sx = [-1, 1], yy = [20, 60])
            translate([x + sx*column_profile_w/2 - 3, yy - sl/2, backbone_z0 - 1])
                cube([6, sl, backbone_h + 2]);
    }
}

// Horizontal tie plate spanning both profiles. GLOBAL frame, Z = its underside.
// Two of these turn a pair of loose posts into a frame; without a tie at each
// end the stiffness figure in backbone_stiffness.py does not hold. The bottom
// tie is base_plate(), this is the top one and it also carries BF12.
// It CANNOT be a plate laid across the posts: at Z 779 it is mid-post, not on
// top of them, and a 300 mm plate simply ran through both profiles. So it is a
// 6 mm bent channel that spans the GAP and grabs the two inner faces:
//
//     shelf  208 x 80, carries BF12 on its top face
//     tabs   2 x, bent UP 90 deg, 2 x M8 each into the profile's inner slots
//
// Bent UP, not down - down would hang into the carriage's top-of-travel
// corridor and carriage_vs_frame would catch it.
module column_tie(z) {
    t = tie_plate_thk;
    color(col_alu_d) translate([0, 0, z]) {
        difference() {
            union() {
                translate([-tie_shelf_w/2, 0, 0])
                    cube([tie_shelf_w, tie_plate_d, t]);
                for (sx = [-1, 1])
                    translate([sx * tie_plate_w/2 - (sx > 0 ? t : 0), 0, 0])
                        cube([t, tie_plate_d, t + tie_tab_h]);
            }
            // screw clearance through the shelf
            translate([0, screw_axis_y, -1])
                cylinder(d = screw_d + 10, h = t + 2);
            // The BF12 bracket's web and bend come up through the shelf and
            // its foot bolts to the underside - see bf12_pad_drop.
            translate([-(bf12_width/2 + tie_slot_clear),
                       pad_web_y0 - bend_r_in - tie_slot_clear, -1])
                cube([bf12_width + 2*tie_slot_clear,
                      screw_pad_thk + bend_r_in + 2*tie_slot_clear, t + 2]);
            for (x = [-1, 1])
                translate([x*bk12_bolt_pitch/2, pad_web_y0 - bearing_foot_d/2, -1])
                    cylinder(d = bk12_bolt_d + 0.5, h = t + 2);
            // tab bolts, horizontal into the profile slots
            for (sx = [-1, 1], by = tie_bolt_y)
                translate([sx * (tie_plate_w/2 + 1), by, t + tie_bolt_z])
                    rotate([0, -90 * sx, 0])
                        cylinder(d = tie_bolt_d + 1, h = t + 2);
        }
    }
}

// The backbone as a whole: two profiles plus the top tie.
module backbone() {
    for (s = [-1, 1]) column_profile(s * column_profile_x);
    column_tie(bf12_z0 - tie_plate_thk);
}

// Base interface plate with slotted mounting holes to the future mobile base.
// GLOBAL frame, Z = 0 at its bottom face.
module base_plate() {
    color(col_alu)
    difference() {
        translate([-base_plate_w/2, base_plate_rear, 0])
            cube([base_plate_w, base_plate_d, base_plate_thk]);

        // slotted holes to the mobile base - slots run fore/aft, straight down
        // the beam's top slot, so the whole column slides to trim the arm reach
        for (x = [-1, 1], y = base_bolt_y)
            translate([x*base_bolt_pitch_x/2, y, base_plate_thk/2])
                rotate([0, 0, 90]) slot(base_slot_len, base_slot_d, base_plate_thk + 2);

        // THE COLUMN JOINT: 4 x M8 up into the profile end bores, countersunk
        // from below so the plate still lies flat on the beams. 6.8 mm core
        // bore is the M8 tapping drill, so the profile ends tap by hand.
        for (x = [-1, 1], y = column_end_bolt_y)
            translate([x*column_profile_x, y, 0]) {
                translate([0, 0, -1])
                    cylinder(d = column_end_bolt_d + 0.5, h = base_plate_thk + 2);
                translate([0, 0, -0.01])
                    cylinder(d1 = column_end_cs_d, d2 = column_end_bolt_d + 0.5,
                             h = (column_end_cs_d - column_end_bolt_d - 0.5) / 2
                                 / tan(column_end_cs_ang / 2));
            }

        // motor / coupling bore + NEMA23 flange pattern
        translate([0, screw_axis_y, 0]) {
            translate([0, 0, -1]) cylinder(d = base_motor_bore_d, h = base_plate_thk + 2);
            nema23_pattern(base_plate_thk, pilot = false);
        }

        // Cable pass-through to the electronics bay. Was at X -140, 90 long,
        // which put it straight over the left main beam (chassis Y -157.5 ..
        // -117.5) - the cables would have come out onto solid extrusion.
        // Moved inboard into the gap between the beams. 7 mm clear of the
        // X = 0 cross member on the other axis, which is why it is no longer.
        translate([cable_slot_x, base_plate_cy - 40, base_plate_thk/2])
            slot(cable_slot_len, cable_slot_w, base_plate_thk + 2);
    }
}

// base_gusset() DELETED 2026-08-19 - see parameters.scad. It was 21 mm clear
// of the backbone and in no BOM; the joint is now 4 x M8 into the profile ends.

// ###########################################################################
//  5.  MOVING CARRIAGE
// ###########################################################################

// Moving plate + optional rear ribs.
// LOCAL FRAME: global X/Y, Z = 0 at the VERTICAL CENTRE of the plate.
module moving_plate() {
    color(col_alu)
    union() {
        difference() {
            translate([-plate_w/2, y_carriage_face, -plate_h/2])
                cube([plate_w, plate_thk, plate_h]);

            // 16 x M5 clearance holes for the four HGH20CA blocks
            for (sx = [-1, 1], sz = [-1, 1], bx = [-1, 1], bz = [-1, 1])
                translate([sx*rail_x + bx*blk_bolt_x/2,
                           y_carriage_face - 1,
                           sz*blk_pitch/2 + bz*blk_bolt_z/2])
                    rotate([-90, 0, 0]) cylinder(d = blk_bolt_d + 0.4, h = plate_thk + 2);

            // 4 x M8 for the ball nut housing
            for (x = [-1, 1], z = [-1, 1])
                translate([x*(nut_hsg_w/2 - 14), y_carriage_face - 1,
                           z*(nut_hsg_h/2 - 12)])
                    rotate([-90, 0, 0]) cylinder(d = 8.5, h = plate_thk + 2);

            // arm interface bolts: BLIND TAPPED from the front face so the
            // rail blocks behind the plate never interfere. See README.
            for (ax = show_dual_arm_mount ? [-dual_arm_offset_x, dual_arm_offset_x]
                                          : [0])
                translate([ax, 0, 0]) {
                    for (x = [-1, 1], z = [-1, 1])
                        translate([x*arm_bolt_pitch_x/2, y_plate_front + 1,
                                   z*arm_bolt_pitch_y/2])
                            rotate([90, 0, 0]) cylinder(d = 5, h = 8.5);
                    translate([0, y_carriage_face - 1, 0]) rotate([-90, 0, 0])
                        cylinder(d = arm_centre_bore, h = plate_thk + 2);
                }

            // cable chain bracket + trigger tab fixings
            for (x = [chain_x, trigger_tab_x], z = [-1, 1])
                translate([x, y_carriage_face - 1, z*18])
                    rotate([-90, 0, 0]) cylinder(d = 5.5, h = plate_thk + 2);
        }

        if (show_ribs) {
            // Horizontal edge ribs, top and bottom. These are also what the
            // hard stop pads catch, so they are the only ribs that matter
            // structurally AND for the travel limits.
            //
            // They stop at +/- rib_span, NOT at the plate edge: further out
            // they would sweep through the printed side covers, the trigger
            // tab and the cable chain bracket. They also stop short of the
            // centre line - BK12 and BF12 stand 63 mm proud of the backbone
            // and the ribs would drive straight through them on the way past.
            for (z = [-1, 1], s = [-1, 1])
                translate([s == 1 ? rib_gap_x : -rib_span,
                           y_carriage_face - rib_depth,
                           z*(plate_h/2) - (z > 0 ? rib_h : 0)])
                    cube([rib_span - rib_gap_x, rib_depth, rib_h]);
            // vertical ribs either side of the nut housing
            for (x = [-1, 1])
                translate([x*rib_x - rib_thk/2, y_carriage_face - rib_depth,
                           -plate_h/2])
                    cube([rib_thk, rib_depth, plate_h]);
        }
    }
}

// Generic rectangular arm mounting interface.
// THE BOLT PATTERN IS A GUESS - measure your PAR6 base and set the
// arm_bolt_pitch_* parameters before machining anything.
// LOCAL FRAME: X centred on the mount, Z = 0 at its centre, global Y.
module arm_interface() {
    color([0.80, 0.55, 0.20])
    difference() {
        translate([-arm_iface_w/2, y_plate_front, -arm_iface_h/2])
            cube([arm_iface_w, arm_iface_thk, arm_iface_h]);
        translate([0, y_plate_front - 1, 0]) rotate([-90, 0, 0])
            cylinder(d = arm_centre_bore, h = arm_iface_thk + 2);
        for (x = [-1, 1], z = [-1, 1])
            translate([x*arm_bolt_pitch_x/2, y_plate_front - 1, z*arm_bolt_pitch_y/2])
                rotate([-90, 0, 0]) cylinder(d = arm_bolt_d, h = arm_iface_thk + 2);
    }
}

// ###########################################################################
//  5b.  MOBILE BASE CONTEXT  -  NOT part of this design
//
//  A ghost of the existing Mobile_Manipulator_V1 chassis, drawn in LIFT
//  coordinates so the motor bay can be checked against it.
//
//  The two bolt patterns must coincide, which fixes the transform. Inverting
//  chassis_X = lift_Y - base_plate_cy gives:
//      lift_X = -chassis_Y                        (chassis +Y is LEFT)
//      lift_Y =  chassis_X + base_plate_cy        (base_plate_cy is negative)
//      lift_Z =  chassis_Z - base_deck_from_floor
//  Only the parts that matter to the motor bay are drawn.
// ###########################################################################

// place a box given in CHASSIS coordinates
module in_chassis(x0, x1, y0, y1, z0, z1) {
    translate([-max(y0, y1), x0 + base_plate_cy, z0 - base_deck_from_floor])
        cube([abs(y1 - y0), x1 - x0, z1 - z0]);
}

module chassis_battery() {
    in_chassis(battery_centre_x - battery_len/2, battery_centre_x + battery_len/2,
               -battery_wid/2, battery_wid/2,
               battery_bot_from_floor, battery_top_from_floor);
}

// Frame members the motor can NEVER pass through: a clash here is a real
// fault that no amount of machining fixes.
module chassis_structure() {
    // two main 40x80 profiles
    for (s = [-1, 1])
        in_chassis(-300, 300,
                   s*chassis_profile_y - chassis_profile_w/2,
                   s*chassis_profile_y + chassis_profile_w/2,
                   chassis_frame_z0, chassis_frame_z1);
    // 40x40 cross members between the inner faces of the main profiles,
    // flush with their tops. Positions are the chassis copy, not literals -
    // the literals [-280, 0, 280] had silently gone stale.
    for (cx = chassis_cross_x)
        in_chassis(cx - 20, cx + 20,
                   -(chassis_profile_y - chassis_profile_w/2),
                   chassis_profile_y - chassis_profile_w/2,
                   chassis_frame_z1 - 40, chassis_frame_z1);
}

// The column mount plate is a CNC part the motor is meant to pass through, so
// an intersection with it is the required clearance bore, not a collision.
// What matters is whether that bore stays inside the plate's edges.
module chassis_column_plate() {
    in_chassis(-chassis_plate_size/2, chassis_plate_size/2,
               -chassis_plate_size/2, chassis_plate_size/2,
               chassis_frame_z1, base_deck_from_floor);
}

module chassis_frame() { chassis_structure(); chassis_column_plate(); }

module chassis_context() {
    color([0.30, 0.42, 0.55], 0.35) chassis_battery();
    color([0.45, 0.45, 0.48], 0.30) chassis_frame();
}

// The volume the motor installation actually needs: envelope + wiring + cover.
// This is what must clear the battery, NOT the bare motor.
module motor_install_envelope() {
    w = motor_body + 2*motor_cover_radial;
    translate([-w/2, screw_axis_y - w/2, motor_install_bot])
        cube([w, w, -motor_install_bot]);
}

// ###########################################################################
//  6.  SAFETY, SENSING, CABLE MANAGEMENT
// ###########################################################################

// Hard mechanical stop pad. Both pads catch the horizontal EDGE RIBS of the
// moving plate - see the note above stop_pad_h in parameters.scad.
// Add a 3 mm polyurethane bumper on the contact face before you rely on it.
//
// LOCAL FRAME: X centred on the pad, Y global, Z = 0 at the CONTACT face.
// dir = -1 -> pad hangs below the contact face (lower stop)
// dir = +1 -> pad stands above the contact face (upper stop)
module stop_pad(dir = -1, w = stop_pad_w) {
    color(col_warn)
    translate([-w/2, stop_pad_y, dir > 0 ? 0 : -stop_pad_h])
        difference() {
            cube([w, stop_pad_d, stop_pad_h]);
            for (y = [stop_pad_d*0.3, stop_pad_d*0.7])
                translate([w/2, y, -1]) cylinder(d = 5.5, h = stop_pad_h + 2);
        }
}

// Limit switch on a slotted bracket, bolted into the OUTER side slot of the
// right hand column profile - no drilling, it rides the T-slot.
//
// GEOMETRY THAT MATTERS: the switch BODY is kept entirely out of the trigger
// tab's swept volume in Y. Only the roller lever reaches into it. The tab can
// therefore cam the lever over and keep travelling all the way to the hard
// stop without ever crushing the switch. That is the whole point of the
// layout - a tab that runs into a switch body destroys the switch on the
// first software fault.
//
// LOCAL FRAME: bracket plate lies in the YZ plane at X = 0 (against the
// riser). Body stands off in +X, lever reaches out in +Y, and Z = 0 is the
// top face of the switch body.
module limit_switch() {
    color(col_alu_d)                                    // bracket + M3 slots
    difference() {
        translate([0, -8, -46]) cube([sw_bracket_thk, sw_body[0] + 16, 58]);
        for (z = [-38, -16])
            translate([-1, sw_body[0]/2, z]) rotate([0, 90, 0])
                slot(14, 3.4, sw_bracket_thk + 2);
    }
    color([0.15, 0.15, 0.15])                            // switch body
        translate([sw_bracket_thk, 0, -sw_body[2]])
            cube([sw_body[1] + 10, sw_body[0], sw_body[2]]);
    // roller lever: starts 1 mm inside the body - it met the body on one
    // edge only and exported as a part of its own (viz/export.py count)
    color([0.75, 0.75, 0.78])
        translate([sw_bracket_thk + 3, sw_body[0] - 1, -1])
            rotate([-14, 0, 0]) cube([10, 15, 1.2]);
}

// Adjustable trigger tab (flag) on the rear of the moving plate.
// The vertical slots let you tune the trip point after assembly without
// re-drilling. The flag stands in front of the switch body in Y so it only
// ever touches the lever.
// LOCAL FRAME: Z = 0 at the moving plate centre, global X/Y.
module trigger_tab(x) {
    color(col_alu_d)
    difference() {
        union() {
            // flag - this is what cams the roller lever
            translate([x - 12, 68, -24]) cube([24, 10, 48]);
            // mounting flange against the rear face of the moving plate
            translate([x - 12, 78, -24]) cube([24, y_carriage_face - 78, 48]);
        }
        for (z = [-1, 1])
            translate([x, y_carriage_face + 1, z*18]) rotate([90, 0, 0])
                slot(trigger_tab_slot, 5.5, 20);
    }
}

// Cable strain relief anchor - a bar with zip-tie slots.
module strain_relief() {
    color(col_alu_d)
    difference() {
        cube([90, 14, 10], center = true);
        for (i = [0 : strain_relief_n - 1])
            translate([(i - (strain_relief_n - 1)/2) * 26, 0, 0])
                cube([4, 20, 5], center = true);
        for (x = [-1, 1])
            translate([x*36, 0, -6]) cylinder(d = 5.5, h = 12);
    }
}

// Emergency stop mounting bracket. Wiring itself is out of scope - this is
// only the 22 mm hole and somewhere to bolt it.
module estop_bracket() {
    color(col_alu_d)
    difference() {
        cube([70, 6, 70], center = true);
        rotate([90, 0, 0]) cylinder(d = estop_hole_d, h = 10, center = true);
        for (x = [-1, 1], z = [-1, 1])
            translate([x*28, 0, z*28]) rotate([90, 0, 0])
                cylinder(d = 4.5, h = 10, center = true);
    }
}

// 10 x 20 cable chain, drawn as a swept envelope rather than as links.
// Fixed anchor at the TOP, loop hangs BELOW, moving anchor on the carriage:
// the standard arrangement for a vertical axis. The loop bottom rises at
// half the carriage speed, which is what chain_len is solved for.
module cable_chain(cz) {
    zb = chain_bend_z(cz);
    zm = chain_moving_z(cz);
    ycen = (chain_fixed_y + chain_moving_y)/2;

    color(col_chain) {
        // fixed run, from the top anchor down to the loop
        translate([chain_x - chain_w/2, chain_fixed_y - chain_thk/2, zb])
            cube([chain_w, chain_thk, chain_fixed_z - zb]);

        // moving run, from the carriage bracket down to the loop
        translate([chain_x - chain_w/2, chain_moving_y - chain_thk/2, zb])
            cube([chain_w, chain_thk, zm - zb]);

        // the 180 degree loop, arching DOWNWARDS. The cutter takes local
        // x < 0 (= above the bend after the rotation). It was twice as long
        // and cut the whole ring: the loop was never drawn (viz/export.py
        // body count, 2026-10-03).
        translate([chain_x, ycen, zb]) rotate([0, 90, 0])
            difference() {
                cylinder(h = chain_w, d = 2*chain_bend_r + chain_thk, center = true);
                cylinder(h = chain_w + 2, d = 2*chain_bend_r - chain_thk, center = true);
                translate([-chain_bend_r - chain_thk, -chain_bend_r - chain_thk,
                           -chain_w/2 - 1])
                    cube([chain_bend_r + chain_thk, 2*(chain_bend_r + chain_thk),
                          chain_w + 2]);
            }
    }

    translate([0, 0, cz]) chain_moving_bracket();
    chain_fixed_end();
}

// Moving end of the chain, carriage-local (Z = 0 at the plate centre); the
// collision test sweeps this same module. A leg on the plate's two M5 holes
// at Z +/-18 and the tab the chain end bolts to, at chain_bracket_z. Until
// 2026-10-03 only the tab was drawn, at -80: on no hole, and with the
// carriage down the anchor stood 27 mm below the bend - a chain that cannot
// reach (assert in parameters.scad). 24 wide, not 32: any wider and it clips
// the inner face of the left side cover.
module chain_moving_bracket() {
    color(col_alu_d)
    difference() {
        union() {
            translate([chain_x - 12, y_carriage_face - 4, chain_bracket_z - 10])
                cube([24, 4, 30 - (chain_bracket_z - 10)]);
            translate([chain_x - 12, chain_moving_y - 4, chain_bracket_z - 10])
                cube([24, y_carriage_face - chain_moving_y + 4, 10]);
        }
        for (z = [-18, 18])
            translate([chain_x, y_carriage_face + 1, z]) rotate([90, 0, 0])
                cylinder(d = 5.5, h = 6);
    }
}

// The static end of the chain, apart so check_collisions.scad can pair it
// with the enclosure, the posts and the moving parts - chain_swept() is a
// box that stops at the top of the fixed run and never saw either part.
module chain_fixed_end() {
    // The bracket runs on to the left post's outer face and bolts into its
    // slot - it stopped 13 mm short and held the chain end in air. It ends
    // 4 mm short of the rail plane: the carriage blocks are 2 mm wider than
    // the post each side, and at the top of travel they pass that corner.
    y0 = chain_fixed_y - 4;
    y1 = y_rail_plane - 4;
    color(col_alu_d)
        translate([chain_x - 12, y0, chain_fixed_z])
            cube([-column_face_out - (chain_x - 12), y1 - y0, 10]);
    // Loom strain relief, bolted down on the bracket: it holds the cables
    // where they leave the chain, right under the top-cap pass-through.
    translate([chain_x, (y0 + y1) / 2, chain_fixed_z + 10 + 5])
        rotate([0, 0, 90]) strain_relief();
}
