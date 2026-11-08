// ############################################################################
//  parameters.scad  -  Z-LIFT / vertical axis module
//  Single source of truth for every dimension in the assembly.
//
//  UNITS: MILLIMETRES everywhere. No exceptions.
//
//  COORDINATE SYSTEM
//    X = 0 at the machine centre line.  +X = robot RIGHT,  -X = robot LEFT
//    Y = 0 at the REAR face of the vertical backbone plate.  +Y = FORWARD
//        (the arm hangs off the +Y side, the electronics live at -Y)
//    Z = 0 at the BOTTOM face of the base interface plate,
//        i.e. the top deck of the future mobile base.
//
//  Anything tagged [VERIFY] is taken from a supplier datasheet or from
//  memory of a common part and MUST be measured on the real component
//  before cutting metal.
//
//  NOTE ON FILE STRUCTURE
//    main.scad includes this file first, then re-declares the display
//    toggles at the end of its own include block. In OpenSCAD the LAST
//    assignment in a scope wins, so the values in main.scad (or on the
//    command line via -D) always override the defaults below.
// ############################################################################

// ---------------------------------------------------------------------------
// 0.  RENDER QUALITY
// ---------------------------------------------------------------------------
$fa = 5;      // max angle per circle fragment
$fs = 1.0;    // max fragment length in mm (drop to 0.4 for final renders)

// ---------------------------------------------------------------------------
// 1.  DISPLAY DEFAULTS  (overridden by main.scad - keep names in sync)
// ---------------------------------------------------------------------------
show_frame            = true;   // backbone, base plate, risers
show_rails            = true;   // HGR20 rails + HGH20CA blocks
show_carriage         = true;   // moving plate, ribs, ball nut housing
show_motor            = true;   // NEMA23, coupling, BK12/BF12, ball screw
show_enclosure        = true;   // white printed cosmetic panels
show_cable_chain      = true;   // 10 x 20 cable chain placeholder
show_single_arm_mount = true;   // one centred arm interface plate
show_dual_arm_mount   = false;  // two symmetric arm interface plates
show_dimensions       = false;  // dimension annotation overlay
show_context          = false;  // ghost of the future mobile base deck
show_brake            = true;   // placeholder volume for the future brake
show_ribs             = true;   // stiffening ribs on the moving plate
show_belt_drive       = false;  // OPTIONAL alternative to direct coupling
carriage_position_mm  = 300;    // 0 = LOW/floor reach ... z_travel = HIGH
explode               = 0;      // exploded view offset in mm (0 = assembled)
view                  = "iso";  // "iso" | "front" | "side" | "exploded"

// ---------------------------------------------------------------------------
// 2.  LINEAR MOTION - HGR20 RAIL + HGH20CA BLOCK          [VERIFY ALL]
// ---------------------------------------------------------------------------
rail_len          = 800;    // HGR20 length as purchased
rail_w            = 20;     // rail width
rail_h            = 17.5;   // rail height above its mounting face   [OK Lyczko0 2026-10-17]
rail_hole_pitch   = 60;     // counterbore pitch along the rail       [OK Lyczko0 2026-10-17]
rail_hole_first   = 20;     // first hole from the rail end           [OK Lyczko0 2026-10-17]
rail_bolt_d       = 5;      // M5 rail bolts

blk_len           = 77.5;   // HGH20CA overall length                 [OK Lyczko0 2026-10-17]
blk_w             = 44;     // HGH20CA overall width                  [OK Lyczko0 2026-10-17]
blk_h             = 30;     // rail mounting face -> top of block     [OK Lyczko0 2026-10-17]
blk_bolt_x        = 32;     // block bolt pattern across the rail     [OK gauge 2026-10-10]
blk_bolt_z        = 36;     // block bolt pattern along the rail      [OK gauge 2026-10-10]
blk_bolt_d        = 5;      // M5 into the moving plate

// Rail centre-to-centre. Spec range 220..300, default 260.
rail_spacing      = 260;

// Vertical pitch between the two blocks that share one rail.
// IMPORTANT TRADE-OFF: usable travel = rail_len - (blk_pitch + blk_len).
// Every mm added here costs exactly 1 mm of travel but buys anti-pitch
// stiffness for the arm's overhung load.
blk_pitch         = 120;

// ---------------------------------------------------------------------------
// 3.  BALL SCREW - SFU1605 + BK12 / BF12 + NUT           [VERIFY ALL]
// ---------------------------------------------------------------------------
screw_len         = 800;    // overall screw length as purchased
screw_d           = 16;     // SFU1605 nominal diameter
screw_lead        = 5;      // mm of lift per motor revolution
screw_end_d       = 10;     // machined end diameter into BK12/BF12    [OK Lyczko0 2026-10-17]

nut_body_d        = 28;     // SFU1605 single nut body OD              [OK Lyczko0 2026-10-17]
nut_flange_d      = 48;     // nut flange OD                           [OK Lyczko0 2026-10-17]
nut_flange_thk    = 10;     // nut flange thickness                    [OK Lyczko0 2026-10-17]
nut_len           = 42;     // nut overall length                      [OK Lyczko0 2026-10-17]
nut_bolt_pcd      = 38;     // flange bolt circle                      [OK gauge 2026-10-10]
// Flange bolts are NOT every 60 deg. Gauge 2026-10-10 (test_rig/coupons_z):
// 0 and 180 fit, the four at +/-60 sat ~4.7 mm off, each toward the 0-180
// line - 45 deg gives 4.96. No holes at 90/270, where the flange is flatted.
nut_bolt_a        = [0, 45, 135, 180, 225, 315];   // [OK gauge v2 2026-10-10]
nut_bolt_n        = len(nut_bolt_a);
nut_bolt_d        = 6;      // M6 - flange hole: M5 or M6?             [MEASURE]

bk12_axial        = 43;     // BK12 length along the screw axis        [OK Lyczko0 2026-10-17]
bk12_width        = 60;     // BK12 width across (our X)               [OK Lyczko0 2026-10-17]
bk12_body_h       = 43;     // mounting face -> outer face (our Y)     [OK Lyczko0 2026-10-17]
bk12_centre_h     = 25;     // mounting face -> screw axis             [OK Lyczko0 2026-10-17]
bk12_bolt_pitch   = 46;     // 2 x M6 base bolts                       [OK gauge 2026-10-10]
bk12_bolt_d       = 6;

bf12_axial        = 25;     // BF12 length along the screw axis        [OK Lyczko0 2026-10-17]
bf12_width        = 60;
bf12_body_h       = 43;
bf12_centre_h     = 25;     // must match bk12_centre_h for a straight screw
bf12_bolt_pitch   = 46;

coupling_d        = 30;     // flexible jaw/beam coupling OD           [OK Lyczko0 2026-10-17]
coupling_len      = 35;     // coupling overall length                 [OK Lyczko0 2026-10-17]
coupling_z0       = 6;      // coupling bottom, measured up the motor shaft

// ---------------------------------------------------------------------------
// 4.  MOTOR - NEMA23 + OPTIONAL BRAKE                     [VERIFY ALL]
// ---------------------------------------------------------------------------
motor_body        = 57;     // 57 x 57 square body
motor_len         = 56;     // body length (no shaft)
motor_shaft_d     = 8;
motor_shaft_len   = 21;                 // usable shaft above the flange [VERIFY]
motor_bolt_pitch  = 47.14;              // NEMA23 square bolt pattern
motor_bolt_d      = 5;                  // M5 clearance
motor_pilot_d     = 38.1;               // NEMA23 pilot boss OD
motor_pilot_h     = 1.6;                // pilot boss height

// The motor flange bolts straight to the underside of the base plate.
// motor_adapter_thk > 0 inserts an extra plate (e.g. if your motor has a
// short shaft you must REDUCE this, not increase it - see README).
motor_adapter_thk = 0;

// --- INTEGRATED BRAKE -------------------------------------------------------
// The selected motor has the brake built in, IN LINE behind the motor body -
// it is not a separate rear-shaft add-on. It therefore extends the envelope
// that hangs down into the mobile base, one for one.
//
// Seller images suggest the brake adds 25-35 mm behind the 56 mm body, so the
// nominal stack is 86 mm. motor_brake_envelope is the CONSERVATIVE design
// figure used for all clearance work until the part is in hand and measured.
brake_len_nominal    = 30;   // behind the motor body            [VERIFY]
brake_d              = 57;   // integrated brakes usually keep the 57 frame [OK Lyczko0 2026-10-17]
motor_brake_envelope = 95;   // flange face to rear face, design value.
// ZMIERZONE 2026-10-17: 93 mm (Lyczko0, bez walu). 95 zostaje - 2 mm zapasu.
// Przewody silnika i hamulca wychodza z boku i ida w gore.
// PODSTAWA: rodzina 57AI..-2804YS ma korpus 56/76/112 i calosc 95/115/151,
// czyli hamulec dodaje KONSEKWENTNIE 39 mm w trzech wariantach. Nasz silnik
// 57BYG250B ma korpus 56 mm i 1.2 Nm - identyczna klasa jak 57AI56.
// Wczesniejsze 90 mm bylo oszacowaniem ze zdjecia i bylo o 5 mm za male.
motor_brake_mass     = 0.9;  // kg, silnik ~0.65 + hamulec ~0.25    [VERIFY]

// Space the hardware needs BELOW the rear face of the motor+brake.
// motor_wire_clear assumes a SIDE or right-angle cable exit. A rear axial
// exit needs the cable's minimum bend radius instead - see README.
motor_wire_clear  = 8;      // side/right-angle exit             [OK Lyczko0 2026-10-17]
motor_cover_clear = 12;     // 3 mm printed wall + air gap + boss

// ---------------------------------------------------------------------------
// 5.  STRUCTURE - ALUMINIUM PLATES
// ---------------------------------------------------------------------------
// COLUMN BACKBONE: two T-slot profiles on edge, NOT a plate.
//
// The plate version (380 x 840 x 10 + two 50 x 40 x 840 solid risers) needed
// 26 tapped M5 holes drilled into 40 mm solid bar just to mount the rails.
// With profiles the rails bolt down on hammer nuts in the slot, and the 40 mm
// face of a 40x80 carries ONE CENTRED SLOT that lands exactly on the rail's
// hole centreline. Zero drilling, zero tapping.
//
// The profile must be 80 mm deep, not 40. Laid flat it gives a first bending
// mode of only 20 Hz - see backbone_stiffness.py. On edge it gives 36 Hz
// against 50 Hz for the plate, which is acceptable; flat is not.
//
// Depth 80 instead of plate 10 + riser 40 = 50 does NOT push the arm forward:
// base_plate_front is derived from y_carriage_face, so the base plate moves
// back with it and chassis_x_of_screw stays at 120. Checked, not assumed.
column_profile_w  = 40;     // X width of each profile
column_profile_d  = 80;     // Y depth - THIS SETS THE RAIL MOUNTING PLANE
column_profile_slot = 8;    // T-slot width                          [VERIFY]
backbone_h        = 840;    // Z 10 .. 850 (tall enough to carry the top stops)
backbone_z0       = 10;     // sits on top of the base plate

// Horizontal tie plate spanning the two profiles. Two of them: the base plate
// at the bottom, and this one at the top under BF12. Without a tie at each end
// the two profiles are not a frame and the stiffness figure does not hold.
tie_plate_d       = column_profile_d;   // Y - flush with the profiles. It must
                            // NOT reach past y_rail_plane or it sits in the
                            // carriage's swept corridor; the collision suite
                            // catches that as carriage_vs_frame.
tie_plate_thk     = 6;      // 8 -> 6: nosi BF12 promieniowo i spina
                            // profile, sruby przelotowe. <=6 mm to u PCBWay
                            // blacharka, nie CNC.

// --- HOW THE COLUMN IS ACTUALLY FASTENED --------------------------------
// Designed 2026-08-19. Until then the profiles floated: the tie plate ran
// straight THROUGH them and the gussets stood 21 mm clear of anything.
//
// The 40x80 has two M8 core bores in each end face, one per 40x40 module,
// at Y = 20 and Y = 60 - the same two axes the side slots sit on. The bores
// come pre-drilled at 6.8 mm, which IS the tapping drill for M8 (8 - 1.25
// pitch), so the ends tap by hand in 6063-T5. That is the whole joint: no
// bracket, no machining, nothing bought.
column_end_bolt_d = 8;                  // M8 into the profile end bores
column_end_bolt_y = [20, 60];           // the two 40x40 module axes
column_end_cs_d   = 16.4;               // M8 countersunk head OD    [VERIFY]
column_end_cs_ang = 90;                 // included angle            [VERIFY]

// The tie plate cannot span the profiles - it sits at Z 779, which is
// mid-post, not on top of them. So it spans BETWEEN them and picks up the
// inner 80 mm faces through two tabs bent UP (up, not down: down would hang
// into the carriage's top-of-travel corridor). Hammer nuts in the existing
// slots, so again nothing is drilled in the profile.
tie_tab_h         = 30;                 // bent tab height above the shelf
// M6, not M8. M8 hammer nuts for slot 8 exist but are not the stock item at
// every seller, and there is nothing here to justify the risk: the four bolts
// hold BF12's radial load and stop the posts converging, and the sideways case
// deflects 0.007 mm. M6 in 8.8 shears at 4.7 kN each. M6 is also already on
// the BOM at 7.1, so it adds no line.
tie_bolt_d        = 6;
tie_bolt_y        = [20, 60];           // = the profile's side slot axes
tie_bolt_z        = 15;                 // up the tab from the shelf top

// The screw sits this far BEHIND the rail plane, between the two profiles.
// Nothing is in its way at X = 0: the profiles stand at +/- rail_spacing/2.
//
// 20, not 5. At 5 the motor bore broke out through the front edge of the
// chassis column plate by 1 mm - an old open item. Setting the screw back
// moves the bore back with it and costs only a slightly deeper nut housing,
// which is far cheaper than growing a 10 mm plate to 330 mm.
screw_axis_setback = 20;

// Base interface plate
base_plate_w      = 420;
base_plate_d      = 300;
base_plate_thk    = 10;
base_plate_front_gap = 5;   // clearance from the plate front edge to the
                            // moving plate's rear face. Set the front edge
                            // BEHIND the moving plate so the carriage can
                            // travel all the way down past it.

// Slotted holes to the future mobile base. Defaults match the 250 mm bolt
// pitch of the existing Mobile_Manipulator_V1 chassis column plate.
// Down to the chassis. 275, not 250: the main beams are 40x80 standing 80 mm
// tall, so their TOP face is 40 mm wide with ONE centred slot - a hammer nut
// can only sit on the beam centreline. At 250 the bolts landed 12.5 mm beside
// the slot, on solid extrusion, with nothing to thread into. This pitch MUST
// equal the chassis 2 x main_beam_y; check_interface.py compares them.
base_bolt_pitch_x = 275;

// In Y the bolts cannot be moved out of the column's band - the beam slot runs
// straight under the profile. So they are placed between the column's own
// countersinks instead: the M8 heads occupy Y 11.8..28.2 and 51.8..68.2, and
// these two slots sit wholly behind them. 180 mm couple against a 22.5 N*m
// overturning moment is 125 N a side.
base_bolt_y       = [-10, -190];
base_slot_len     = 20;     // total slot length (fore/aft adjustment)
base_slot_d       = 7;      // M6 clearance
base_motor_bore_d = 45;     // clearance for the coupling + NEMA23 pilot boss

// Cable pass-through, base -> column. Must land in the gap BETWEEN the chassis
// main beams: this plate's X is the chassis Y, and the beams occupy 117.5..157.5
// on both sides. Trim: catalogue edge protector, no printed part.  [VERIFY] the
// bundle really fits 70 x 26 once the 12 AWG pair is terminated.
cable_slot_x      = -75;
cable_slot_len    = 70;
cable_slot_w      = 26;
cable_beam_inner  = 117.5;  // = chassis main_beam_y - profile_main_w/2

// Side gussets DELETED 2026-08-19. They sat at X = +/-175 with the backbone
// outer face at +/-150 - 21 mm of air between them and any other part. The
// literal 175 was correct for the 380-wide plate backbone and nobody moved it
// when the profiles arrived. They were in no BOM and no mass model either, so
// deleting them removes nothing real.
//
// They are not replaced. The base joint is 4 x M8 into the profile end bores
// on a 40 mm lever, and the moment that would open it is 320 N*m per bolt pair
// of preload against 11.3 N*m applied - a factor of 28. The plate itself is
// carried directly under each profile by the chassis beam below it, so there
// is no long unsupported span to bend.
// ponytail: no moment brace at the column foot. Ceiling: backbone_stiffness.py
// puts the RIGID-foot first mode at 27.5 Hz (2026-10-05, arm lever and column
// mass included), so a gusset can never reach the old 30 Hz trigger - it only
// buys back foot compliance (26.7 Hz with 2 cm of profile's worth of it).
// Upgrade: tap-test the built column, arm extended. Under ~23 Hz the foot is
// soft - add a bent-foot gusset on the profile's outer face (60 mm of base
// plate outboard of it). Under 20 Hz - a diagonal brace from the column top
// back to the frame.

// ---------------------------------------------------------------------------
// 6.  MOVING CARRIAGE PLATE
// ---------------------------------------------------------------------------
plate_w           = 440;
plate_h           = 220;
plate_thk         = 10;     // aluminium

rib_thk           = 10;     // stiffening ribs on the REAR of the plate
rib_depth         = 22;     // how far they stand off the rear face
rib_h             = 20;     // height of the horizontal edge ribs
rib_x             = 80;     // +/- X of the vertical ribs (clears nut housing)
// The horizontal edge ribs live in the only clear corridor behind the plate:
//   inboard limit  - clear of the ball nut housing (nut_hsg_w/2 = 48)
//   outboard limit - clear of the rails and the HGH20CA blocks (from 108)
// Anywhere else they would sweep straight through fixed hardware.
rib_gap_x         = 54;     // +/- X where the horizontal ribs start
rib_span          = 105;    // +/- X where the horizontal ribs end

// Ball nut housing - a machined block bolted to the rear of the moving plate
// Ball nut BRACKET, not a machined block. One 6 mm laser blank with three
// bends: a shelf carrying the nut, two side flanges bent up, and a rear leg
// bolting to the moving plate. Replaced a 96 x 56 x 80 milled block
// 2026-08-18 - that block was 1.16 kg of CNC work for a joint
// that carries 115 N on an 80 mm overhang.
// Checked: as a channel it deflects 0.004 mm at 2.1 MPa, against 185 MPa
// yield for 5754-H22. Even a flat 6 mm shelf would hold (0.162 mm, 16 MPa);
// the flanges are free because the blank is bent anyway.
nut_hsg_w         = 96;     // X - still the KEEP-OUT envelope for the tests
nut_hsg_h         = 56;     // Z
nut_bracket_thk   = 6;      // one sheet thickness throughout
nut_bracket_flange_h = 25;  // side flanges bent up from the shelf
nut_bracket_leg_t = 6;      // rear leg against the moving plate
nut_hsg_rear_gap  = 6;      // clearance from the backbone front face

// ---------------------------------------------------------------------------
// 7.  ARM INTERFACE  -  GENERIC. DO NOT ASSUME A PAR6 PATTERN.
//     Measure your arm base and change these four numbers.
// ---------------------------------------------------------------------------
arm_iface_w       = 140;
arm_iface_h       = 140;
arm_iface_thk     = 12;     // aluminium. Never 3D print this part.
arm_bolt_pitch_x  = 100;    // [CONFIGURABLE - MEASURE YOUR ARM]
arm_bolt_pitch_y  = 100;    // [CONFIGURABLE - MEASURE YOUR ARM]
arm_bolt_d        = 6.6;    // M6 clearance
arm_centre_bore   = 60;     // cable pass-through under the arm base
dual_arm_offset_x = 145;    // +/- X for the future two-arm layout

// ---------------------------------------------------------------------------
// 8.  LIMITS, STOPS, SENSING, CABLE CHAIN
// ---------------------------------------------------------------------------
soft_limit_margin = 10;     // extra clearance kept by the software limits
hard_stop_gap     = 5;      // hard stop engages this far past the soft limit

// The hard stops catch the horizontal EDGE RIBS of the moving plate, not the
// rail blocks. The plate is taller than the block group, so its bottom rib
// hangs ~11 mm below the lowest block and would reach any block-level stop
// first. Stopping on the rib gives a far bigger contact patch anyway.
// LOWER pads sit on the base plate at +/- stop_lo_x and catch the bottom
// edge rib of the moving plate.
// UPPER pads sit on the rail risers just above the end of the rail and catch
// the top end faces of the upper pair of HGH20CA blocks - there is nothing
// on the moving plate that far out to catch up there.
stop_pad_h        = 12;     // aluminium pad; add a 3 mm PU bumper on top
stop_pad_w        = 30;     // X, lower pads
stop_pad_d        = 24;     // Y, from the rail mounting plane forward
stop_pad_y        = column_profile_d;   // = y_rail_plane, pads sit flat on the profile face
stop_lo_x         = 80;     // +/- X of the lower pads, under the bottom rib

sw_body           = [20, 10, 6];   // generic micro limit switch envelope
sw_bracket_thk    = 3;
trigger_tab_x     = 172;    // +/- X of the trigger tab on the moving plate
trigger_tab_slot  = 20;     // vertical adjustment slot length

chain_w           = 20;     // cable chain outer width (along X)
chain_thk         = 26;     // cable chain outer thickness (along Y)
chain_x           = -175;   // LEFT side. Limit switches live on the RIGHT.
chain_fixed_y     = 24;     // fixed run, hugging the backbone
chain_moving_y    = 66;     // moving run, just behind the moving plate
chain_fixed_z     = 800;    // fixed anchor near the top of the backbone
chain_bracket_z   = -30;    // moving anchor, relative to the plate centre.
                            // Just under the bracket's lower M5 (Z -18); at
                            // -80 the chain could not reach the low limit
chain_floor_clear = 40;     // clearance from the BOTTOM of the hanging loop
                            // to the top of the base plate, at the low limit

estop_hole_d      = 22.5;   // standard 22 mm E-stop mounting hole
strain_relief_n   = 3;      // number of zip-tie slots on the anchor block

// ---------------------------------------------------------------------------
// 9.  ENCLOSURE (cosmetic, 3D printed, NON-STRUCTURAL)
// ---------------------------------------------------------------------------
panel_thk         = 3;
// Zebra pionowe na licach oslon. 6 x 3 co 24 mm, nie 9 x 4.5 co 21 - to
// drugie kosztowalo +36 % filamentu, to pierwsze +14 % (osiem paneli
// kolumny). Zebro dziala sztywnoscia przez d^2, a materialem przez d,
// wiec glebiej i rzadziej bije gesto i plytko. Pionowo, bo tak sie drukuje
// bez podpor i tak wyglada szafa sterownicza.
flute_w           = 6;
flute_d           = 3;
flute_pitch       = 24;
// Zebra sa DETALEM, nie faktura. Na calej plaszczyznie robily z robota
// grzejnik; w pasmie czytaja sie jak celowy element. Pasmo jest ulamkiem
// szerokosci lica i zawsze wysrodkowane.
flute_band_frac   = 0.42;
panel_gap         = 2;      // visible seam between printed segments
panel_segments    = 4;      // side covers are printed in this many pieces
panel_boss_d      = 7;      // M3 heat-set insert boss OD
panel_boss_h      = 8;
panel_insert_d    = 4.2;    // M3 heat-set insert pilot
vent_w            = 4;
vent_len          = 40;
vent_pitch        = 10;

driver_box_d      = 95;     // electronics bay depth, behind the column
driver_box_h      = 150;
driver_box_w      = 300;
driver_pcb        = [70, 50, 22];   // TMC5160 module envelope placeholder

// ---------------------------------------------------------------------------
// 10. CONTEXT (not part of this design - reference only)
// ---------------------------------------------------------------------------
// Constraints imported from Mobile_Manipulator_V1_Chassis.py so the clearance
// falls out of the model instead of living in a comment. Update these if the
// chassis changes.
base_deck_from_floor   = 240; // = gora belek glownych. Plyta montazowa
                              // kolumny usunieta 2026-08-18 - patrz
                              // mobile_base/base_parameters.scad
// ZSYNCHRONIZOWANE z ../mobile_base/base_parameters.scad po wyborze realnego
// pakietu 36V 12.8Ah (obudowa 210 x 90 x 70) lezacego W POPRZEK robota.
// Ten plik nosi KOPIE parametrow podwozia - jak tam sie zmienia, tu trzeba
// przepisac. Rozjazd tych dwoch zestawow juz raz dal falszywy alarm.
battery_top_from_floor = 185;  // battery_top_z  = spod 115 + pakiet 70 (nad osiami, 2026-10-07)
battery_len            = 90;   // battery_l      krotszy bok, wzdluz chassis X
battery_wid            = 190;  // battery_w      dluzszy bok, w poprzek - MAX przy zakupie
battery_hgt            = 70;   // battery_h
battery_bot_from_floor = 115;  // battery_z      = strzemie uchwytu kola 108 + 7
tray_top_from_floor    = 115;  // tray_top_z     wierzch kolyski = spod pakietu
battery_centre_x       = -40;  // battery_x
chassis_profile_y      = 137.5; // main_beam_y   osie belek glownych 40x80
chassis_profile_w      = 40;    // profile_main_w
chassis_cross_x        = [-240, -120, 0, 170, 240];  // cross_x
// 2026-09-16: te kopie rozjechaly sie z podwoziem w TRZECH miejscach naraz -
// bateria (-20 / 120x110 zamiast -55 / 210x70), taca (49 zamiast 50 po
// zmianie na 5 mm) i rozstaw belek (125 zamiast 137.5). Testy komory silnika
// przechodzily na geometrii, ktorej nie ma. Od teraz sprawdza je
// control/check_interface.py w obu kierunkach - nazwa po prawej to zmienna
// w mobile_base/base_parameters.scad.
chassis_frame_z0       = 160; // frame_bottom_z
chassis_frame_z1       = 240; // frame_top_z
chassis_plate_size     = 300; // = column_plate_l in mobile_base/base_parameters.scad.
                              // WAS 295 - a stale copy. Keep these two in step.
chassis_plate_thk      = 10;  // column_plate_thickness; the motor bore passes it
motor_clearance_target = 20;  // practical clearance we want under the motor
motor_cover_radial     = 6;   // cover wall + gap, sideways

// ---------------------------------------------------------------------------
// 11. COLOURS
// ---------------------------------------------------------------------------
col_alu    = [0.72, 0.74, 0.76];
col_alu_d  = [0.60, 0.62, 0.65];
col_rail   = [0.80, 0.81, 0.83];
col_block  = [0.10, 0.55, 0.28];   // green carriage blocks
col_screw  = [0.86, 0.87, 0.89];
col_motor  = [0.14, 0.14, 0.16];
col_panel  = [0.97, 0.97, 0.96];   // white printed covers
col_warn   = [0.90, 0.35, 0.10];
col_elec   = [0.15, 0.35, 0.55];
col_chain  = [0.20, 0.20, 0.22];

// viz/export.py exports the drive one colour at a time (OpenSCAD 2021 drops
// colours on export). "" draws everything - what every other caller wants.
// Same helper as mobile_base/base_parameters.scad; the two never share an include.
viz_only = "";
function viz(tag) = viz_only == "" || viz_only == tag;
show_brake_margin = true;   // translucent margin block under the brake - not a part

// ###########################################################################
// ###  DERIVED GEOMETRY - do not edit below, edit the parameters above    ###
// ###########################################################################

// --- Y (depth) chain -------------------------------------------------------
y_backbone_front = 0;                                  // profiles start at Y=0
y_rail_plane     = column_profile_d;                   // 80  rail mounting face
backbone_w       = rail_spacing + column_profile_w;    // 300  outer span
y_rail_front     = y_rail_plane + rail_h;              // 67.5
y_carriage_face  = y_rail_plane + blk_h;               // 80  = plate rear face
y_plate_front    = y_carriage_face + plate_thk;        // 90
y_arm_face       = y_plate_front + arm_iface_thk;      // 102

// The screw runs between the profiles, set back from the rail plane. The nut
// housing rear is then derived from the FLANGE, not from a backbone face -
// with profiles there is no plate at X = 0 to clear.
// Bearing bracket: 6 mm bent sheet, not a 10 mm milled pad. At the design
// load (253 N = the moving assembly at 2.2 g) the web sees 19.7 MPa against
// 127 MPa yield - a factor of 6.5. The same part printed would see 19.7
// against a 3 MPa creep allowable, so this one stays metal; print_vs_metal.py
// has the method.
screw_pad_thk    = 6;
bearing_foot_d   = 40;   // foot bent back under the web, 2 x M6 down
column_profile_x = rail_spacing / 2;                   // +/- X of each profile
column_face_out  = column_profile_x + column_profile_w/2;   // 150 outer face
column_face_in   = column_profile_x - column_profile_w/2;   // 110 inner face

// Tie plate spans the GAP, not the posts. Its tabs land on the inner faces.
tie_plate_w      = 2 * column_face_in;                 // 220 tab face to tab face
tie_shelf_w      = tie_plate_w - 2 * tie_plate_thk;    // 208 flat part

screw_axis_y     = y_rail_plane - screw_axis_setback;  // 75

nut_hsg_y0       = screw_axis_y - nut_flange_d/2 - nut_hsg_rear_gap;  // 45
nut_hsg_depth    = y_carriage_face - nut_hsg_y0;                      // 65

base_plate_front = y_carriage_face - base_plate_front_gap;   // 75
base_plate_rear  = base_plate_front - base_plate_d;          // -225
base_plate_cy    = (base_plate_front + base_plate_rear) / 2; // -75

// --- Z (vertical) chain ----------------------------------------------------
motor_face_z     = -motor_adapter_thk;                 // 0  = base plate bottom
motor_body_z     = motor_face_z - motor_len;           // -56
// The brake is integrated and in line, so the envelope is measured from the
// FLANGE FACE, not stacked behind the body.
brake_z          = motor_face_z - (show_brake ? motor_brake_envelope : motor_len);
motor_stack_bot  = brake_z;                            // lowest hardware
motor_install_bot = motor_stack_bot - motor_wire_clear - motor_cover_clear;
shaft_top_z      = motor_face_z + motor_shaft_len;     // 21

coupling_bot_z   = motor_face_z + coupling_z0;         // 6
coupling_top_z   = coupling_bot_z + coupling_len;      // 41

screw_bot_z      = coupling_top_z - 15;                // 26  (15 mm grip)
screw_top_z      = screw_bot_z + screw_len;            // 826

bk12_z0          = coupling_top_z + 8;                 // 49  bottom face
bk12_z1          = bk12_z0 + bk12_axial;               // 92
bf12_z1          = screw_top_z - 16;                   // 810 top face
bf12_z0          = bf12_z1 - bf12_axial;               // 785

// Machined end lengths, derived so the reduced diameter spans each bearing
// and the O16 thread starts just clear of it.
screw_end_lo     = (bk12_z1 + 2) - screw_bot_z;        // 68
screw_end_hi     = screw_top_z - (bf12_z0 - 2);        // 43

// The bearing brackets are BENT 6 mm sheet, so a web is only flat from t + r
// above its foot. The BF12's bolts sit 12.5 mm above its seat: with the foot
// on the tie shelf they fell inside the bend - the model had no bend radius
// and hid it (2026-09-25). So the BF12 foot goes UNDER the shelf and the web
// comes up through a slot in it: flat from the BF12's seat up, and neither
// the BF12 nor the tie plate moves, so the travel is untouched.
bend_r_in        = screw_pad_thk;   // inner bend radius, 1t      [VERIFY] PCBWay, 6 mm 5754
bk12_pad_drop    = bk12_z0 - backbone_z0;              // 39  foot on the base plate
bf12_pad_drop    = tie_plate_thk + screw_pad_thk;      // 12  foot under the tie shelf
pad_web_y0       = screw_axis_y - bk12_centre_h - screw_pad_thk;   // 29  web rear face
tie_slot_clear   = 1;               // round the BF12 web where it passes the shelf
// NEMA23 bolt heads on top of the base plate, [d, h]. The rear pair sits right
// under the BK12 bracket's bend: an M5 socket head (8.5 x 5) runs into it, so
// all four are countersunk DIN 7991 - flush with the plate.       [VERIFY]
motor_bolt_head  = [10.4, 0];
// A hole closer than 1.5t to a bend comes out oval. Both brackets.
assert(bk12_axial/2 - (bk12_bolt_d + 0.5)/2
       >= screw_pad_thk + bend_r_in + 1.5*screw_pad_thk - bk12_pad_drop,
       "sruby BK12 wypadaja w gieciu wspornika");
assert(bf12_axial/2 - (bk12_bolt_d + 0.5)/2
       >= screw_pad_thk + bend_r_in + 1.5*screw_pad_thk - bf12_pad_drop,
       "sruby BF12 wypadaja w gieciu wspornika");

rail_z0          = 20;                                 // rail bottom
rail_z1          = rail_z0 + rail_len;                 // 820
backbone_z1      = backbone_z0 + backbone_h;           // 850

// --- travel limits ---------------------------------------------------------
// carriage_z is the VERTICAL CENTRE of the moving plate. The nut housing and
// the two block pairs are centred on it.
blk_span_half    = blk_pitch/2 + blk_len/2;            // 98.75

// low limit, whichever of these three is worst:
lim_lo_rail  = rail_z0 + blk_span_half + soft_limit_margin; // block runs off the rail end
lim_lo_bk12  = bk12_z1 + soft_limit_margin + nut_hsg_h/2;  // nut housing into BK12
lim_lo_stop  = backbone_z0 + stop_pad_h + hard_stop_gap + plate_h/2;  // rib onto the stop pad
carriage_z_min = max(lim_lo_rail, lim_lo_bk12, lim_lo_stop);

// high limit:
lim_hi_rail  = rail_z1 - blk_span_half - soft_limit_margin;
lim_hi_bf12  = bf12_z0 - soft_limit_margin - nut_hsg_h/2;
carriage_z_max = min(lim_hi_rail, lim_hi_bf12);

z_travel     = carriage_z_max - carriage_z_min;

// Hard stop contact faces.
// Lower: pad top face, hard_stop_gap below the plate's bottom rib at the low
//        soft limit (that relationship defines lim_lo_stop above).
// Upper: pad bottom face, sitting just clear of the end of the rail. The
//        block's top face is soft_limit_margin below the rail end at the high
//        soft limit, so the effective upper overtravel is that plus 1 mm.
stop_lo_z1   = backbone_z0 + stop_pad_h;
stop_hi_z0   = rail_z1 + 1;
stop_hi_gap  = stop_hi_z0 - (carriage_z_max + blk_span_half);

// limit switch trip heights. The flag on the moving plate is 48 mm tall
// (+/- 24 about the plate centre) and cams a roller lever, so it trips a few
// mm inside the soft limit and then simply slides past the lever.
sw_lo_z      = carriage_z_min - 24 + 2;
sw_hi_z      = carriage_z_max + 24 - 2;

// --- cable chain kinematics ------------------------------------------------
// Fixed anchor at the TOP, loop hangs BELOW, moving anchor on the carriage.
// Chain length is derived so the loop bottoms out chain_floor_clear above
// the base plate when the carriage is at its lowest position.
chain_bend_r = (chain_moving_y - chain_fixed_y) / 2;
chain_bend_lo = backbone_z0 + chain_floor_clear + chain_bend_r + chain_thk/2;
chain_len = chain_fixed_z + (carriage_z_min + chain_bracket_z)
            + PI*chain_bend_r - 2*chain_bend_lo;

function chain_moving_z(cz) = cz + chain_bracket_z;
function chain_bend_z(cz)   = (chain_fixed_z + chain_moving_z(cz)
                               - chain_len + PI*chain_bend_r) / 2;
// With the carriage down the moving anchor must stand at or above the bend:
// below it the moving run has negative length and the chain cannot reach.
// It stood 27 mm below until 2026-10-03 and nothing noticed - the run was
// drawn as a negative-height cube, i.e. not at all.
assert(chain_moving_z(carriage_z_min) >= chain_bend_z(carriage_z_min),
       str("cable chain: moving anchor ",
           chain_bend_z(carriage_z_min) - chain_moving_z(carriage_z_min),
           " mm below the bend at the low limit"));

// --- misc derived ----------------------------------------------------------
rail_x        = rail_spacing / 2;
arm_moment_arm = y_arm_face - y_rail_plane;    // overhang from the rail plane
lowest_arm_face_z = carriage_z_min - arm_iface_h/2;
lowest_arm_from_floor = base_deck_from_floor + lowest_arm_face_z;

// --- mapping onto the mobile base ------------------------------------------
// The lift bolts down through the chassis column plate, so the two bolt
// patterns must coincide. That fixes the transform:
//     chassis_X = lift_Y - base_plate_cy      (lift +Y = robot front)
//     chassis_Z = lift_Z + base_deck_from_floor
// The screw axis is therefore NOT over the middle of the chassis plate - it
// sits base_plate_cy forward of it, because the lift's base plate extends
// rearward for anti-tip stability while the backbone sits near its front.
chassis_x_of_screw = screw_axis_y - base_plate_cy;          // +120

motor_bay_x0 = chassis_x_of_screw - motor_body/2 - motor_cover_radial;
motor_bay_x1 = chassis_x_of_screw + motor_body/2 + motor_cover_radial;

// How far the battery has to move aft for the motor bay to clear it sideways,
// which is the alternative to finding the depth vertically.
battery_front_x      = battery_centre_x + battery_len/2;
battery_rear_x       = battery_centre_x - battery_len/2;
battery_shift_needed = battery_front_x - (motor_bay_x0 - motor_clearance_target);

// Does the battery still sit under the motor bay in plan view? If it has been
// moved aside, the surface that limits the motor is the battery TRAY, not the
// top of the pack - and the depth budget roughly doubles.
battery_in_bay  = (battery_front_x > motor_bay_x0) && (battery_rear_x < motor_bay_x1);
motor_limit_z   = battery_in_bay ? battery_top_from_floor : tray_top_from_floor;
motor_clearance = (base_deck_from_floor + motor_install_bot) - motor_limit_z;

// Distance from the motor bore to the front edge of the chassis column plate.
// Negative means the bore breaks out through the edge.
plate_edge_margin = chassis_plate_size/2
                    - (chassis_x_of_screw + motor_body/2 + 2.5);

function clampz(v) = min(max(v, 0), z_travel);
function carriage_z(pos) = carriage_z_min + clampz(pos);

// ###########################################################################
// ###  SANITY CHECKS                                                      ###
// ###########################################################################
// These abort the render on a physically impossible configuration.
assert(z_travel > 0, "z_travel is negative - the screw/rail/BK12 stack does not fit");
assert(nut_hsg_depth >= nut_flange_d + 8,
       "nut housing too shallow for the nut flange - increase column_profile_d");
assert(nut_hsg_w >= nut_flange_d + 8, "nut housing too narrow for the nut flange");
assert(plate_h >= 2*blk_span_half,
       "moving plate is shorter than the block group - reduce blk_pitch");
// The column's countersunk heads and the chassis slots share the same X band
// (both sit on the beam centreline), so they can only be separated in Y. If
// either pattern moves, this is what stops them being drilled into each other.
// --- printed panel geometry -----------------------------------------------------
// Inner face of a side cover. Was backbone_w/2, which was fine while the
// backbone was a 380 mm plate. With two 300 mm-span profiles that value fell
// INSIDE the carriage blocks - caught as enclosure_vs_blocks. Derive it from
// whatever actually sticks out furthest.
// 2026-08-19: the cable chain was the widest thing on the column and was NOT
// in this max(). It runs at X -175 +/- 10, so it hung 29 mm outside its own
// cover - visible, and something to catch a sleeve on. Now the skin clears it.
pan_x        = max(backbone_w/2,
                   rail_x + blk_w/2 + 4,
                   abs(chain_x) + chain_w/2 + 4);
pan_front    = y_carriage_face - 4;             // stay clear of the moving plate
pan_rear     = base_plate_rear + 10;
// The boss has to bridge from the skin to the profile's outer face, and that
// gap is now 39 mm rather than 6. Derived, so widening the skin cannot leave
// the bosses hanging in space.
pan_boss_h   = pan_x - (rail_x + column_profile_w/2);
// Top cap depth. It used to run back to pan_rear (-185) because that is where
// the DRIVER BOX ends - but the driver box sits on the base plate at the
// BOTTOM of the column. At the top the only thing behind the posts is the
// chain's fixed anchor at Y 24. A 291 mm deep slab on a 384 mm wide column
// read as a table top; this is the depth something up there actually needs.
// 4 mm okapu dookola, nie 17 z tylu i 0 z przodu - tamto dawalo widoczny
// uskok na szczycie kolumny i wygladalo na niedokonczone.
cap_over     = 4;
cap_rear     = -(panel_thk + cap_over);
cap_front    = pan_front + cap_over;
// Global Z of each bearing bracket's foot. The lower one stands on the base
// plate, the upper one hangs under the tie plate shelf (bf12_pad_drop).
bearing_foot_z = [backbone_z0, bf12_z0 - bf12_pad_drop];

bolt_gap_min = min([for (by = base_bolt_y, cy = column_end_bolt_y)
                    abs(by - cy) - column_end_cs_d/2 - base_slot_len/2]);
assert(bolt_gap_min > 0,
       str("otwor podwozia nachodzi na wpust kolumny o ", -bolt_gap_min, " mm"));

// The tie plate must stop at the profile inner faces. It used to be
// backbone_w wide and ran straight through both posts.
assert(tie_plate_w <= 2 * column_face_in + 0.01,
       str("plyta spinajaca ", tie_plate_w, " nie miesci sie w przeswicie ",
           2 * column_face_in));

// The tabs bend UP, so they must not reach past the top of the profile.
assert(bf12_z0 + tie_tab_h <= backbone_z0 + backbone_h,
       "zagiete uchwyty plyty spinajacej wystaja ponad profil");

assert(abs(cable_slot_x) + cable_slot_len/2 < cable_beam_inner,
       str("przepust kablowy siega ", abs(cable_slot_x) + cable_slot_len/2,
           " a belka zaczyna sie na ", cable_beam_inner));

assert(rail_spacing >= 220 && rail_spacing <= 300,
       "rail_spacing outside the 220..300 design envelope");
assert(backbone_z1 >= stop_hi_z0 + stop_pad_h,
       "backbone is too short to carry the upper hard stops - raise backbone_h");
assert(stop_lo_x + stop_pad_w/2 < backbone_w/2,
       "lower stop pads collide with the side covers - reduce stop_lo_x");

// Non-fatal warnings.
module print_report() {
    echo("======================================================");
    echo("  Z-LIFT DERIVED GEOMETRY  (all mm)");
    echo("======================================================");
    echo(str("  usable Z travel        : ", z_travel));
    echo(str("  carriage centre range  : ", carriage_z_min, " .. ", carriage_z_max));
    echo(str("  overall height (Z)     : ", backbone_z1));
    echo(str("  screw axis Y           : ", screw_axis_y));
    echo(str("  rail mounting plane Y  : ", y_rail_plane));
    echo(str("  arm mounting face Y    : ", y_arm_face));
    echo(str("  arm overhang from rails: ", arm_moment_arm));
    echo(str("  nut housing depth      : ", nut_hsg_depth,
             "  (flange needs ", nut_flange_d, ")"));
    echo(str("  lowest arm face above deck : ", lowest_arm_face_z));
    echo(str("  lowest arm face above floor: ", lowest_arm_from_floor,
             "  (assumes deck at ", base_deck_from_floor, ")"));
    echo("--- motor + integrated brake vs the mobile base -------");
    echo(str("  motor+brake envelope       : ", motor_brake_envelope,
             " (body ", motor_len, " + brake ", brake_len_nominal,
             " nominal = ", motor_len + brake_len_nominal, ")"));
    echo(str("  lowest hardware, lift Z    : ", motor_stack_bot));
    echo(str("  lowest hardware from floor : ", base_deck_from_floor + motor_stack_bot));
    echo(str("  + wires ", motor_wire_clear, " + cover ", motor_cover_clear,
             "        : ", base_deck_from_floor + motor_install_bot, " from floor"));
    echo(str("  limiting surface below     : ",
             battery_in_bay ? "battery top" : "battery tray (pack moved aside)",
             " at ", motor_limit_z, " from floor"));
    echo(str("  CLEARANCE, bare envelope   : ",
             (base_deck_from_floor + motor_stack_bot) - motor_limit_z));
    echo(str("  CLEARANCE, installed       : ", motor_clearance,
             "   (target ", motor_clearance_target, ")"));
    echo(str("  depth budget below deck    : ", base_deck_from_floor - motor_limit_z,
             "   needed ", -motor_install_bot + motor_clearance_target));
    echo(str("  full turns per 100 mm  : ", 100/screw_lead));
    echo("------------------------------------------------------");

    if (z_travel < 550)
        echo("WARNING: travel below the 550 mm design target. Reduce blk_pitch or use a longer rail.");
    if (z_travel > 650)
        echo("WARNING: travel above the 650 mm design target. Check the screw thread length is real.");
    if (carriage_z_min == lim_lo_bk12)
        echo("NOTE: low limit is set by the BK12 top face. Shortening bk12_axial buys floor reach.");
    if (carriage_z_min == lim_lo_stop)
        echo("NOTE: low limit is set by the lower hard stop pad under the plate's bottom rib.");
    if (carriage_z_min == lim_lo_rail)
        echo("NOTE: low limit is set by the rail end.");
    if (dual_arm_offset_x + arm_iface_w/2 > plate_w/2)
        echo("WARNING: dual arm plates overhang the moving plate. Reduce dual_arm_offset_x.");
    if (chain_x + chain_w/2 > -rail_x - column_profile_w/2)
        echo("WARNING: cable chain overlaps the left column profile in X.");
    if (motor_clearance < motor_clearance_target)
        echo(str("WARNING: motor+brake does NOT clear by ", motor_clearance_target,
                 " mm. Deficit = ", motor_clearance_target - motor_clearance,
                 " mm. Move the battery aft (battery_centre_x), or raise the lift."));
    else
        echo(str("OK: motor+brake clears the base by ", motor_clearance,
                 " mm installed (target ", motor_clearance_target, ")."));
    echo("--- where the motor lands on the mobile base ----------");
    echo(str("  transform: chassis_X = lift_Y - (", base_plate_cy, ")"));
    echo(str("  screw/motor axis at chassis X = ", chassis_x_of_screw, ", Y = 0"));
    echo(str("  motor bay footprint chassis X = ", motor_bay_x0, " .. ", motor_bay_x1));
    echo(str("  battery front face  chassis X = ", battery_front_x));
    if (battery_in_bay)
        echo(str("  -> move the battery AFT by ", battery_shift_needed,
                 " mm (set battery_centre_x = ", battery_centre_x - battery_shift_needed,
                 ") to clear the motor bay sideways"));
    else
        echo(str("  -> battery is clear of the motor bay by ",
                 motor_bay_x0 - battery_front_x, " mm in X"));
    echo(str("  chassis column plate needs a >= ", motor_body + 5,
             " mm square (or D", ceil(sqrt(2)*motor_body) + 5,
             ") bore. Margin to the plate's front edge = ", plate_edge_margin, " mm"));
    if (plate_edge_margin < 10)
        echo("WARNING: the motor bore breaks out of the chassis column plate's front edge. Extend that plate forward, or bolt the lift's base plate straight onto the frame profiles.");
    echo("  Nothing here is certified. Validate loads and the brake yourself.");
    echo("======================================================");
}

// ###########################################################################
// ###  INTERFACE REPORT                                                   ###
// ###  Wypisuje KAZDA wartosc, ktora mobile_base trzyma u siebie jako      ###
// ###  kopie. Skrypt check_interface.py porownuje to z jego literalami.    ###
// ###  Powod: 2026-08-18 znalazlem CZTERY rozjechane kopie recznie.        ###
// ###  Piata znajdzie ten skrypt, nie ja w trakcie zamawiania.             ###
// ###########################################################################
module interface_report() {
    echo(str("IFACE base_deck_height=",   base_deck_from_floor));
    echo(str("IFACE arm_mount_x=",        y_arm_face - base_plate_cy));
    echo(str("IFACE col_plate_x=",        y_plate_front - base_plate_cy));
    echo(str("IFACE column_motor_dx=",    screw_axis_y - base_plate_cy));
    echo(str("IFACE col_plate_w=",        plate_w));
    echo(str("IFACE col_plate_h=",        plate_h));
    echo(str("IFACE col_carriage_low=",   base_deck_from_floor + carriage_z_min));
    echo(str("IFACE col_carriage_high=",  base_deck_from_floor + carriage_z_max));
    echo(str("IFACE arm_mount_z_low=",    base_deck_from_floor + lowest_arm_face_z));
    echo(str("IFACE arm_mount_z_high=",   base_deck_from_floor + carriage_z_max
                                          - arm_iface_h/2));
    echo(str("IFACE column_motor_env=",   motor_brake_envelope));
    echo(str("IFACE column_motor_inst=",  motor_brake_envelope + motor_wire_clear
                                          + motor_cover_clear));
    echo(str("IFACE column_bolt_pitch=",  base_bolt_pitch_x));
    // Panel silhouette - the chassis draws a proxy of the column and it used
    // to guess these. A guessed proxy is how the hero render showed two bare
    // posts for a week while the real column had covers.
    echo(str("IFACE col_pan_x=",          pan_x));
    echo(str("IFACE col_pan_front=",      pan_front));
    echo(str("IFACE col_cap_rear=",       cap_rear));
    echo(str("IFACE col_cap_front=",      cap_front));
    echo(str("IFACE col_panel_thk=",      panel_thk));
    echo(str("IFACE col_panel_seg=",      panel_segments));
    echo(str("IFACE col_panel_gap=",      panel_gap));
    echo(str("IFACE col_flute_w=",        flute_w));
    echo(str("IFACE col_flute_d=",        flute_d));
    echo(str("IFACE col_flute_pitch=",    flute_pitch));
    echo(str("IFACE col_flute_band=",     flute_band_frac));
    echo(str("IFACE col_dbox_y0=",        dbox_y0));
    echo(str("IFACE col_dbox_d=",         driver_box_d));
    echo(str("IFACE col_dbox_w=",         driver_box_w));
    echo(str("IFACE col_dbox_h=",         driver_box_h));
}
