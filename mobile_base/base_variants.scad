// ############################################################################
//  base_variants.scad  -  trzy warianty podparcia
//
//  A : 2 napedy centralne + 2 duze castery na osi symetrii (przod i tyl)
//      -> polygon w ksztalcie rombu
//  B : 2 napedy centralne + 4 castery narozne (2 z nich sprezynowane)
//      -> polygon szescioboczny, najwiekszy
//  C : 2 napedy centralne + 2 castery glowne z PRZODU
//      + 2 kolka anti-tip z TYLU, nieobciazone w normalnej jezdzie
//      -> polygon czworoboczny w normalnej jezdzie, szescioboczny awaryjnie
//
//  Kazdy wariant zwraca liste punktow kontaktu z podloga i wierzcholki
//  polygonu podparcia w kolejnosci PRZECIWNIE DO WSKAZOWEK ZEGARA (CCW),
//  co jest wymagane przez poly_margin() w base_stability.scad.
//
//  DLACZEGO CASTERY GLOWNE Z PRZODU W WARIANCIE C
//    Kolumna i ramie sa wysuniete do przodu, wiec srodek masy wedruje do
//    przodu. Podparcie glowne musi byc tam, gdzie jest obciazenie. Gdyby
//    castery byly z tylu, a anti-tip z przodu, to najczestszy przypadek
//    pracy (ramie wyciagniete do przodu) opieralby sie na kolkach
//    awaryjnych - czyli uzywalby ich caly czas.
// ############################################################################

include <base_components.scad>

caster_y = caster_track / 2;

// ---------------------------------------------------------------------------
//  PUNKTY KONTAKTU Z PODLOGA
//  [x, y, typ]   typ: 0 = naped, 1 = caster, 2 = anti-tip (bez kontaktu)
// ---------------------------------------------------------------------------
function contacts(v) =
    v == "A" ? [[drive_axle_x,  wheel_y, 0], [drive_axle_x, -wheel_y, 0],
                [omni_x, 0, 1],              [caster_rear_x, 0, 1]]
  : v == "B" ? [[drive_axle_x,  wheel_y, 0], [drive_axle_x, -wheel_y, 0],
                [caster_front_x,  caster_y, 1], [caster_front_x, -caster_y, 1],
                [caster_rear_x,   caster_y, 1], [caster_rear_x,  -caster_y, 1]]
  :            [[drive_axle_x,  wheel_y, 0], [drive_axle_x, -wheel_y, 0],
                [caster_front_x,  caster_y, 1], [caster_front_x, -caster_y, 1],
                [antitip_x,       caster_y, 2], [antitip_x,      -caster_y, 2]];

// ---------------------------------------------------------------------------
//  POLYGON PODPARCIA, wierzcholki CCW
//  emergency = true  -> wlaczamy anti-tip (tylko wariant C to zmienia)
//
//  Kolo castera stoi na okregu o promieniu caster_swivel_off wokol osi
//  skretu, zawsze ZA nia w kierunku jazdy: po jezdzie do przodu przedni
//  stoi na X 170, nie 240. Do 2026-10-03 polygon bral 240 i mass_report
//  mowil PASS 103 mm; przy kazdym ustawieniu kolek zostaje 57.
//  Dlatego kontakt to kolo [x, y, r] (r = 0: kolo napedowe, anti-tip), a
//  polygon to obszar wewnatrz przy KAZDYM ustawieniu casterow - kazda
//  krawedz jest styczna do obu swoich kol od strony wnetrza.
// ---------------------------------------------------------------------------
function support_disks(v, emergency = false, ax = drive_axle_x) =
    let (f = caster_front_pivot, b = caster_rear_pivot, r = caster_swivel_off)
    v == "A" ? [[omni_x, 0, 0], [ax, wheel_y, 0], [b, 0, r], [ax, -wheel_y, 0]]
  : v == "B" ? [[f,  caster_y, r], [ax,  wheel_y, 0],
                [b,  caster_y, r], [b, -caster_y, r],
                [ax, -wheel_y, 0], [f, -caster_y, r]]
  : emergency ? [[f,  caster_y, r], [ax, wheel_y, 0],
                 [antitip_x, caster_y, 0], [antitip_x, -caster_y, 0],
                 [ax, -wheel_y, 0], [f, -caster_y, r]]
              : [[f,  caster_y, r], [ax,  wheel_y, 0],
                 [ax, -wheel_y, 0], [f, -caster_y, r]];

// krawedz a->b styczna do kol a i b od wnetrza: [n, k], wnetrze to n.p >= k
function inner_edge(a, b) =
    let (L = norm([b[0] - a[0], b[1] - a[1]]),
         u = [b[0] - a[0], b[1] - a[1]] / L,
         s = (a[2] - b[2]) / L,
         n = sqrt(1 - s * s) * [-u[1], u[0]] + s * u)
    [n, n * [a[0], a[1]] + a[2]];

function line_cross(l1, l2) =
    let (d = l1[0][0] * l2[0][1] - l1[0][1] * l2[0][0])
    [(l1[1] * l2[0][1] - l1[0][1] * l2[1]) / d,
     (l1[0][0] * l2[1] - l1[1] * l2[0][0]) / d];

function safe_poly(c) =
    let (n = len(c), e = [for (i = [0 : n - 1]) inner_edge(c[i], c[(i + 1) % n])])
    [for (i = [0 : n - 1]) line_cross(e[(i + n - 1) % n], e[i])];

function support_poly(v, emergency = false, ax = drive_axle_x) =
    safe_poly(support_disks(v, emergency, ax));

// OpenSCAD nie ma sum() - rekurencja
function vsum(v, i = 0) = i >= len(v) ? 0 : v[i] + vsum(v, i + 1);

// pole polygonu (shoelace) - miara ile podparcia daje wariant
function poly_area(p) =
    len(p) < 3 ? 0
  : abs(0.5 * vsum([for (i = [0 : len(p) - 1])
        p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1]]));

// ---------------------------------------------------------------------------
//  PROMIEN OBROTU
//  Naped roznicowy obraca sie wokol srodka osi napedowej. Promien zamiatania
//  to odleglosc od tego punktu do najdalszego naroznika obrysu.
// ---------------------------------------------------------------------------
// Najdalszy punkt OBRYSU - zderzak przodu i naroza skorup - nie ramy. Rama
// dawala 410 mm, a siatki oslon 458 (viz/mesh, 2026-10-03).
function turning_radius() =
    let (yc = cover_side_y - cover_corner_r, rc = cover_corner_r + cover_thk)
    max(norm([shell_front_x + bumper_off - drive_axle_x, yc]) + bumper_r,
        norm([cover_front_x + cover_corner_r - drive_axle_x, yc]) + rc,
        norm([cover_rear_x - cover_corner_r - drive_axle_x, yc]) + rc);

// ---------------------------------------------------------------------------
//  UDZIAL OBCIAZENIA NA KOLACH NAPEDOWYCH  (wskaznik trakcji)
//
//  UPROSZCZENIE: cialo sztywne, plaska podloga, podparcie w dwoch liniach
//  poprzecznych - osi napedowej i tej pary casterow, ktora lezy po tej samej
//  stronie srodka masy. Trzecia linia podparcia przenosi wtedy zero.
//  To jest granica sztywnego ciala, a nie realny rozklad - realny zalezy od
//  podatnosci opon i ramy. Wystarcza do porownania wariantow.
//
//  Zwraca ulamek 0..1 albo -1 gdy uklad jest niewyznaczalny.
// ---------------------------------------------------------------------------
function drive_load_fraction(v, cx) =
    v == "B" ? -1                                   // 4 sztywne narozniki
  : v == "A" ? (cx > drive_axle_x
                 ? (omni_x - cx) / (omni_x - drive_axle_x)
                 : (cx - caster_rear_x) / (drive_axle_x - caster_rear_x))
  :            (cx >= drive_axle_x
                 ? (caster_front_x - cx) / (caster_front_x - drive_axle_x)
                 : -2);                             // opad na anti-tip

// ---------------------------------------------------------------------------
//  GEOMETRIA - kola i castery danego wariantu
// ---------------------------------------------------------------------------
module variant_support(v) {
    // kola napedowe - wspolne dla wszystkich wariantow
    if (show_drive)
        for (s = [-1, 1]) {
            translate([drive_axle_x, s * wheel_y, wheel_radius]) hub_wheel(s);
            if (show_cnc) drive_mount(s);
        }

    // Tylny caster odbity: osie skretu na +/-205 (caster_*_pivot), kola na
    // zewnatrz. Do 2026-10-03 tylny stal bez odbicia, os na -275 - 70 mm
    // za obwiednia, ktora sprawdzaja testy oslon, a uchwyt poza rama.
    if (show_casters) {
        if (v == "A") {
            // przod: kolo omni (bez uchwytu - nie istnieje), tyl: caster
            translate([omni_x, 0, 0]) omni_wheel();
            translate([caster_rear_x, 0, 0]) mirror([1, 0, 0]) caster();
            if (show_cnc) caster_mount(caster_rear_pivot, 0);
        } else if (v == "B") {
            for (x = [caster_front_x, caster_rear_x], s = [-1, 1]) {
                translate([x, s * caster_y, 0]) mirror([x < 0 ? 1 : 0, 0, 0]) caster();
                if (show_cnc)
                    caster_mount(x < 0 ? caster_rear_pivot : caster_front_pivot,
                                 s * caster_y);
            }
            // dwa tylne oznaczone jako sprezynowane
            for (s = [-1, 1])
                color(col_warn, 0.5)
                    translate([caster_rear_pivot, s * caster_y,
                               caster_diameter * 0.95])
                        cylinder(d = 34, h = 30);
        } else {
            for (s = [-1, 1]) {
                translate([caster_front_x, s * caster_y, 0]) caster();
                if (show_cnc) caster_mount(caster_front_x - caster_swivel_off,
                                           s * caster_y);
                translate([antitip_x, s * caster_y, 0]) antitip_wheel();
            }
        }
    }
}

// ---------------------------------------------------------------------------
//  RAMA - wspolna dla wariantow, poprzeczki dosuwane do casterow
// ---------------------------------------------------------------------------
module base_frame(v) {
    // belki glowne 40x80, os wzdluz X
    // tagi viz(): w Fusion kazdy profil osobno (2026-10-07, do rozbierania)
    if (viz("beam"))
    for (s = [-1, 1])
        translate([0, s * main_beam_y, frame_bottom_z + profile_main_h / 2])
            alu_profile(base_length, profile_main_w, profile_main_h);

    // poprzeczki 40x40 licowane z gora belek glownych
    cw = 2 * main_beam_y - profile_main_w;
    if (viz("cross"))
    for (x = cross_x)
        translate([x, 0, frame_top_z - profile_cross / 2])
            alu_profile_y(cw, profile_cross, profile_cross);

    if (show_cnc) {
        end_plate( half_l);
        end_plate(-half_l);
        // Gussety narozne USUNIETE 2026-08-18 - zastapione katalogowymi
        // katownikami do rowka 8 zamiast frezowanej czesci.
        // Nie modelujemy ich: to element zlaczny, nie konstrukcyjny.
    }
}

// ---------------------------------------------------------------------------
//  PELNY WARIANT
// ---------------------------------------------------------------------------
module base_variant(v) {
    if (show_frame)       base_frame(v);
    variant_support(v);
    if (show_battery)   { battery_pack(); if (show_cnc) battery_cradle(); }
    if (show_cnc)       electronics_plate();
    if (show_electronics) electronics_boxes();
    if (show_column)      column_keepout();
    if (show_zlift_ghost) zlift_ghost();
    if (show_skirts)      side_skirts();
}

// ---------------------------------------------------------------------------
//  RAPORT PORONAWCZY
// ---------------------------------------------------------------------------
module variant_report(v) {
    c  = contacts(v);
    p  = support_poly(v);
    pe = support_poly(v, true);
    nd = len([for (q = c) if (q[2] == 0) 1]);
    nc = len([for (q = c) if (q[2] == 1) 1]);
    na = len([for (q = c) if (q[2] == 2) 1]);

    echo(str("--- WARIANT ", v, " ------------------------------------"));
    echo(str("  punkty kontaktu w normalnej jezdzie : ", nd + nc,
             "   (naped ", nd, ", caster ", nc, ")"));
    if (na > 0)
        echo(str("  kolka anti-tip bez kontaktu        : ", na,
                 "  luz ", antitip_gap, " mm"));
    echo(str("  wierzcholki polygonu               : ", len(p)));
    echo(str("  pole polygonu                      : ",
             round(poly_area(p) / 100) / 100, " dm2"));
    if (v == "C")
        echo(str("  pole polygonu awaryjnego           : ",
                 round(poly_area(pe) / 100) / 100, " dm2"));
    echo(str("  promien zamiatania                 : ", round(turning_radius()),
             " mm"));
    echo(str("  statycznie wyznaczalny             : ",
             (nd + nc) == 3 ? "TAK" : "NIE - podparcie nadmiarowe"));
}
