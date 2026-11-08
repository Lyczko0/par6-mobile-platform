// ############################################################################
//  enclosure.scad  -  white 3D printed cosmetic / protective panels
//
//  NONE OF THESE PARTS ARE STRUCTURAL. They carry their own weight and
//  nothing else. Every panel is retained by M3 screws into heat-set inserts
//  in the printed part, screwed through clearance holes in the aluminium.
//
//  WHY THERE IS NO SINGLE FULL-LENGTH FRONT SCREW COVER
//    The ball nut housing sweeps the whole volume between the backbone and
//    the moving plate over the entire travel. A fixed panel in front of the
//    screw would be driven through by the housing. The screw is therefore
//    covered by two FIXED guards (below and above the travel) plus, if you
//    want full coverage, a bellows - see README "next design steps".
//    The lower guard is the one that matters for safety: it encloses the
//    rotating coupling and the exposed screw end at the motor.
// ############################################################################

// components.scad already includes parameters.scad. Pulling parameters.scad
// in again here would re-run every assignment and spam the console with
// redefinition warnings, so the include chain is kept strictly linear:
//     main.scad -> enclosure.scad -> components.scad -> parameters.scad
include <components.scad>

// Panel geometry now lives in parameters.scad, next to everything else the
// chassis has to copy - it is exported through interface_report() and
// check_interface.py polices the copies.

// Screw guard footprint. Two hard constraints:
//   guard_x     <= rib_gap_x, or the moving plate's horizontal ribs hit it
//   guard_front <  y_carriage_face, and it must reach past the front face of
//                  the BK12/BF12 bodies (screw_axis_y + bk12_body_h/2) or the
//                  bearing blocks poke straight through the panel
guard_x      = min(rib_gap_x, 44);
// Derived, not a magic number. The two constraints above are the definition:
// stay behind the moving plate, and reach past the front face of the bearing
// bodies. Hardcoding 70 silently broke both when the screw moved back.
guard_front  = min(y_carriage_face - 4,
                   screw_axis_y - bk12_centre_h + bk12_body_h + 4);
// window in the guard lips that the bearing block, its pad and the ball nut
// flange all pass through
bearing_win_x = bk12_width/2 + 4;
bearing_win_y = (screw_axis_y + bk12_body_h - bk12_centre_h + 4)
                - y_backbone_front + 1;
// Top of the lower guard. Must clear the TOP of the BK12 body (its corners
// stand outside the screw hole in the lip) and stay below the lowest position
// of the ball nut housing.
guard_lo_z1  = bk12_z1 + 8;
guard_hi_z0  = 760;                             // bottom of the upper guard
dbox_y0      = base_plate_rear;
dbox_y1      = base_plate_rear + driver_box_d;
// top cap skirt depth. Must clear the top edge rib of the moving plate at
// its highest position: carriage_z_max + plate_h/2.
cap_skirt    = min(20, backbone_z1 - (carriage_z_max + plate_h/2) - 6);

// ---------------------------------------------------------------------------
//  side cover, one per side, printed in panel_segments pieces
//  side = +1 (right) or -1 (left)
// ---------------------------------------------------------------------------
//  NOTE: there is a return flange on the REAR edge only. A front flange
//  would reach inboard across the cable chain corridor, so the front edge is
//  left plain and the panel is retained by the rear flange, the M3 bosses
//  and the top cap.
module side_cover(side = 1) {
    seg = (backbone_h) / panel_segments;
    color(col_panel)
    for (i = [0 : panel_segments - 1]) {
        z0 = backbone_z0 + i*seg;
        h  = seg - panel_gap;
        translate([0, 0, z0]) difference() {
            union() {
                // main skin. The -panel_thk term matters: cube() always grows
                // in +X, so without it the left hand cover lands 3 mm inboard
                // of the right hand one and clips the cable chain bracket.
                translate([side*pan_x - (side < 0 ? panel_thk : 0), 0, 0])
                    cube([panel_thk, pan_front, h]);
                // zebra na zewnatrz - rosna w OBRYS, nie do srodka, bo
                // do srodka jest lancuch i wozki
                for (fy = [pan_front*(1 - flute_band_frac)/2
                           : flute_pitch
                           : pan_front*(1 + flute_band_frac)/2 - flute_w])
                    // left side: -flute_d only. The extra -panel_thk it used
                    // to have left the left-hand flutes floating 3 mm off the
                    // skin - found by viz/export.py's body count 2026-09-25.
                    translate([side*(pan_x + panel_thk) - (side < 0 ? flute_d : 0),
                               fy, 6])
                        cube([flute_d, flute_w, h - 12]);
                // Rear return, and it is now the REAR PANEL as well. Two
                // things changed here:
                //   Y  -panel_thk..0, not 0..panel_thk. It used to sit 3 mm
                //      INSIDE the profile over the full 838 mm - a real clash
                //      that no test looked for, because panels were only ever
                //      checked against the moving parts, never the frame.
                //   X  reaches the centreline instead of stopping after 26 mm,
                //      so the two covers meet and close the back of the column.
                //      Nothing moves behind Y = 0, so this costs nothing.
                // Each piece is then an L: 189 x 106 footprint, 210 tall -
                // stands up on the Kobra S1 bed with room to spare.
                translate([side < 0 ? -pan_x - panel_thk : 0, -panel_thk, 0])
                    cube([pan_x + panel_thk, panel_thk, h]);
                // zebra na plecach - to najwieksza plaska plaszczyzna
                // kolumny, wiec bez nich reszta wygladala na doklejona
                for (fx = [pan_x*(1 - flute_band_frac)/2
                           : flute_pitch
                           : pan_x*(1 + flute_band_frac)/2 - flute_w])
                    translate([side < 0 ? -fx - flute_w : fx,
                               -panel_thk - flute_d, 6])
                        cube([flute_w, flute_d, h - 12]);
                // M3 bosses landing in the OUTER side slot of each column
                // profile - the panel screws into a hammer nut, nothing is
                // drilled into the profile.
                // NO side bosses. A boss has to bridge 39 mm from the
                // skin to the profile's outer face, and on the left that
                // corridor is exactly where the cable chain runs - it swept
                // straight through them (chain_vs_enclosure). Moving them in
                // Y did not help: the chain covers both slot axes.
                //
                // So the panel is not held from the side at all. Each piece
                // is an L, and the L's rear leg lies flat on the profile's
                // REAR 40 mm face, which has its own centred slot. One bolt
                // per profile per segment, straight through into a hammer
                // nut. Fewer features, nothing bridging a moving corridor,
                // and the panel is clamped flat instead of standing off.
            }
            // panel bolts, through the rear leg into the profile's rear slot
            for (bz = [h*0.25, h*0.75])
                translate([side*column_profile_x, -panel_thk - 1, bz])
                    rotate([-90, 0, 0]) cylinder(d = 3.4, h = panel_thk + 2);
            // ventilation louvres
            translate([side*(pan_x + panel_thk/2), pan_front*0.55, h/2])
                rotate([0, 90, 0]) vent_row(5, 60, vent_w, vent_pitch, panel_thk + 4);
            // Notches for the two bearing brackets' feet. Both feet fold
            // BACKWARD to clear the NEMA23 bolt holes, which puts them at
            // Y -11..29 - right where the new rear panel runs. Caught as
            // enclosure_vs_bearings at the bottom, then again at the top once
            // the bottom was fixed. Cheaper to notch a cosmetic skin than to
            // fold a structural bracket back into the motor bolts.
            // Derived from the feet, so moving a bearing moves the notch.
            // Glebokosc wyciecia liczy sie od LICA ZEBRA, nie od lica panelu -
            // zebra stoja 3 mm dalej i pierwsze z nich wchodzilo w stope
            // BF12 (enclosure_vs_bearings, 6 x 2 x 6 mm).
            for (gz = bearing_foot_z)
                translate([-(bk12_width/2 + 6), -panel_thk - flute_d - 1,
                           gz - z0 - 4])
                    cube([bk12_width + 12, panel_thk + flute_d + 2,
                          screw_pad_thk + 8]);
        }
    }
}

// ---------------------------------------------------------------------------
//  lower screw / coupling guard  -  THE SAFETY COVER
//  Encloses the flexible coupling, the BK12 and the exposed lower screw.
// ---------------------------------------------------------------------------
module screw_guard_lower() {
    color(col_panel)
    difference() {
        union() {
            // front wall
            translate([-guard_x, guard_front - panel_thk, backbone_z0])
                cube([2*guard_x, panel_thk, guard_lo_z1 - backbone_z0]);
            // side walls
            for (s = [-1, 1])
                translate([s*guard_x - (s > 0 ? panel_thk : 0), y_backbone_front,
                           backbone_z0])
                    cube([panel_thk, guard_front - y_backbone_front,
                          guard_lo_z1 - backbone_z0]);
            // Top lip. The cutout is RECTANGULAR, not round: it has to clear
            // the square BK12 body and its mounting pad, both of which stand
            // outside any circle big enough to pass the ball nut flange.
            difference() {
                translate([-guard_x, y_backbone_front, guard_lo_z1 - panel_thk])
                    cube([2*guard_x, guard_front - y_backbone_front, panel_thk]);
                translate([-bearing_win_x, y_backbone_front - 1,
                           guard_lo_z1 - panel_thk - 1])
                    cube([2*bearing_win_x, bearing_win_y, panel_thk + 2]);
            }
            // fixing bosses onto the base plate, in the front corners and
            // 1 mm into both walls - at (guard_x - 10, guard_front - 12) they
            // stood 3.5 and 5.5 mm off the walls, printed loose
            for (s = [-1, 1])
                translate([s*(guard_x - panel_thk - panel_boss_d/2 + 1),
                           guard_front - panel_thk - panel_boss_d/2 + 1, backbone_z0])
                    m3_boss();
        }
        // ventilation, the motor sits right below this volume
        translate([0, guard_front, 45]) rotate([90, 0, 0])
            vent_row(4, 70, vent_w, vent_pitch, panel_thk + 4);
    }
}

// ---------------------------------------------------------------------------
//  upper screw guard, around the BF12 and the top of the screw
// ---------------------------------------------------------------------------
module screw_guard_upper() {
    color(col_panel)
    union() {
        translate([-guard_x, guard_front - panel_thk, guard_hi_z0])
            cube([2*guard_x, panel_thk, backbone_z1 - guard_hi_z0]);
        for (s = [-1, 1])
            translate([s*guard_x - (s > 0 ? panel_thk : 0), y_backbone_front,
                       guard_hi_z0])
                cube([panel_thk, guard_front - y_backbone_front,
                      backbone_z1 - guard_hi_z0]);
        difference() {
            translate([-guard_x, y_backbone_front, guard_hi_z0])
                cube([2*guard_x, guard_front - y_backbone_front, panel_thk]);
            translate([-bearing_win_x, y_backbone_front - 1, guard_hi_z0 - 1])
                cube([2*bearing_win_x, bearing_win_y, panel_thk + 2]);
        }
    }
}

// ---------------------------------------------------------------------------
//  top cap - closes the top of the column, sheds dust off the rails
// ---------------------------------------------------------------------------
module top_cap() {
    w = 2*(pan_x + panel_thk);
    color(col_panel)
    difference() {
        union() {
            translate([-w/2, cap_rear, backbone_z1]) cube([w, cap_front - cap_rear, 8]);
            // skirt
            for (s = [-1, 1])
                translate([s*(w/2 - panel_thk) - (s > 0 ? 0 : panel_thk),
                           cap_rear, backbone_z1 - cap_skirt])
                    cube([panel_thk, cap_front - cap_rear, cap_skirt]);
            translate([-w/2, cap_front - panel_thk, backbone_z1 - cap_skirt])
                cube([w, panel_thk, cap_skirt]);
            // rear skirt too - the cap now has a back edge to close
            translate([-w/2, cap_rear, backbone_z1 - cap_skirt])
                cube([w, panel_thk, cap_skirt]);
        }
        // cable pass-through for the chain's fixed anchor
        translate([chain_x, chain_fixed_y + 6, backbone_z1 - 1])
            slot(50, 26, 12);
        for (s = [-1, 1])
            translate([s*(w/2 - 14), pan_front - 20, backbone_z1 - 1])
                cylinder(d = 3.4, h = 12);
    }
}

// ---------------------------------------------------------------------------
//  motor / driver enclosure, behind the backbone, sitting on the base plate.
//  Houses the TMC5160, the 24 V wiring and the limit switch terminations.
//  Vented on three sides. Open top = removable lid.
// ---------------------------------------------------------------------------
module driver_box() {
    w = driver_box_w;
    color(col_panel)
    difference() {
        union() {
            // rear wall
            translate([-w/2, dbox_y0, backbone_z0])
                cube([w, panel_thk, driver_box_h]);
            for (fx = [-w*flute_band_frac/2 : flute_pitch : w*flute_band_frac/2 - flute_w])
                translate([fx, dbox_y0 - flute_d, backbone_z0 + 8])
                    cube([flute_w, flute_d, driver_box_h - 16]);
            // side walls
            for (s = [-1, 1])
                translate([s*w/2 - (s > 0 ? panel_thk : 0), dbox_y0, backbone_z0])
                    cube([panel_thk, driver_box_d, driver_box_h]);
            // front wall
            translate([-w/2, dbox_y1 - panel_thk, backbone_z0])
                cube([w, panel_thk, driver_box_h]);
            // lid
            translate([-w/2, dbox_y0, backbone_z0 + driver_box_h])
                cube([w, driver_box_d, panel_thk]);
            // M3 bosses at the corners of the lid
            for (sx = [-1, 1], sy = [0, 1])
                translate([sx*(w/2 - 12), dbox_y0 + 12 + sy*(driver_box_d - 24),
                           backbone_z0 + driver_box_h - panel_boss_h])
                    m3_boss();
        }
        // vents - rear wall
        translate([0, dbox_y0 + panel_thk/2, backbone_z0 + driver_box_h/2])
            rotate([90, 0, 0]) rotate([0, 0, 90])
                for (i = [-2 : 2])
                    translate([0, i*22, 0]) slot(90, vent_w, panel_thk + 4);
        // vents - both side walls
        for (s = [-1, 1])
            translate([s*(w/2 - panel_thk/2), dbox_y0 + driver_box_d/2,
                       backbone_z0 + driver_box_h/2])
                rotate([0, 90, 0]) vent_row(5, 60, vent_w, vent_pitch, panel_thk + 4);
        // 22 mm emergency stop hole in the rear wall, right hand side
        translate([w/2 - 60, dbox_y0 - 1, backbone_z0 + driver_box_h - 45])
            rotate([-90, 0, 0]) cylinder(d = estop_hole_d, h = panel_thk + 2);
        // cable gland / chain entry, left hand side
        translate([-w/2 + 60, dbox_y0 + driver_box_d/2, backbone_z0 + 30])
            rotate([0, 90, 0]) slot(40, 22, w + 4);
    }
}

// ---------------------------------------------------------------------------
//  optional skirt around the part of the motor that drops through the base
//  plate into the mobile base. Keeps swarf and cable off the motor.
// ---------------------------------------------------------------------------
module motor_skirt() {
    s = motor_body + 16;
    color(col_panel)
    translate([0, screw_axis_y, (brake_z - 6)/2])
        difference() {
            cube([s, s, -brake_z + 6], center = true);
            cube([s - 2*panel_thk, s - 2*panel_thk, -brake_z + 12], center = true);
        }
}

// ---------------------------------------------------------------------------
//  everything printed, in one call
// ---------------------------------------------------------------------------
module enclosure_all() {
    side_cover(1);
    side_cover(-1);
    screw_guard_lower();
    screw_guard_upper();
    top_cap();
    driver_box();
}
