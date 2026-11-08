// Test: PAR6 kontra baza i oslony. Obwiednia zamiatania J1 przy ramieniu
// zlozonym (R 140.7 od osi J1) na calej wysokosci kolumny.
include <main_base.scad>
render_assembly = false;
test = "";

module arm_swing(cz) {
    translate([arm_face_x, 0, cz]) par6_swing_folded();
}
module base_solids() {
    base_frame("A");
    electronics_plate(); electronics_boxes();
    battery_pack();
}
if (test == "swing_vs_covers_low")  intersection() { arm_swing(col_carriage_low);  covers_all(); }
if (test == "swing_vs_covers_high") intersection() { arm_swing(col_carriage_high); covers_all(); }
if (test == "swing_vs_base_low")    intersection() { arm_swing(col_carriage_low);  base_solids(); }
if (test == "bracket_vs_covers")
    intersection() { translate([arm_face_x,0,col_carriage_low]) par6_bracket(); covers_all(); }
