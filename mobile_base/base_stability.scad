// ############################################################################
//  base_stability.scad  -  uproszczony test stabilnosci
//
//  CO TO LICZY
//    * polygon podparcia dla wybranego wariantu
//    * rzut srodka masy na podloge
//    * margines stabilnosci = najmniejsza odleglosc rzutu CoM od krawedzi
//      polygonu (dodatnia = w srodku)
//    * DOPUSZCZALNA strefe srodka masy: polygon zwezony o wymagany margines
//
//  CZEGO NIE LICZY
//    Nic dynamicznego. Zadnego hamowania, przyspieszania, sil bocznych w
//    skrecie, podatnosci opon ani drgan. To jest test statyczny na plaskiej
//    podlodze i tyle.
//
//  ZASADA: BRAK DANYCH -> TO VERIFY, NIE ZGADYWANIE
//    Dopoki mass_data_known = false, marginesy liczbowe NIE sa podawane.
//    Podawana jest za to dopuszczalna strefa CoM, ktora jest czysta
//    geometria polygonu i nie zalezy od zadnej masy. To jest uczciwy wynik
//    juz teraz i od razu mowi, gdzie CoM MUSI sie zmiescic.
// ############################################################################

include <base_variants.scad>

// ---------------------------------------------------------------------------
//  geometria polygonu
// ---------------------------------------------------------------------------

// odlegloc ze znakiem punktu p od krawedzi a->b. Dodatnia = po lewej
// stronie krawedzi, czyli wewnatrz polygonu zapisanego CCW.
function edge_dist(a, b, p) =
    ((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])) / norm(b - a);

// margines = najmniejsza z odleglosci do wszystkich krawedzi
function poly_margin(pts, p) =
    min([for (i = [0 : len(pts) - 1])
            edge_dist(pts[i], pts[(i + 1) % len(pts)], p)]);

function inside_poly(pts, p) = poly_margin(pts, p) > 0;

// skan wzdluz osi: jak daleko moze pojsc CoM zachowujac zadany margines
function max_com_x(pts, m) =
    max(concat([-9999], [for (x = [-400 : 2 : 400])
        if (poly_margin(pts, [x, 0]) >= m) x]));
function min_com_x(pts, m) =
    min(concat([9999], [for (x = [-400 : 2 : 400])
        if (poly_margin(pts, [x, 0]) >= m) x]));
// Y skanujemy w SRODKU dopuszczalnego pasma X, a nie na osi napedu.
// W wariancie C tylna krawedz polygonu lezy dokladnie na osi napedu, wiec
// skan w tamtym miejscu zawsze zwracalby pustke.
function com_band_mid_x(pts, m) =
    (min_com_x(pts, m) + max_com_x(pts, m)) / 2;
function max_com_y(pts, m) =
    max(concat([-9999], [for (y = [-400 : 2 : 400])
        if (poly_margin(pts, [com_band_mid_x(pts, m), y]) >= m) y]));

// ---------------------------------------------------------------------------
//  srodek masy ukladu baza + ramie
//  Zwraca undef gdy brakuje danych - swiadomie, zeby nic sie nie policzylo
//  po cichu na zgadnietych liczbach.
// ---------------------------------------------------------------------------
function arm_x_for_pose(pose) =
    is_undef(arm_reach) ? undef
  : pose == "front" ? arm_mount_x + arm_reach
  : pose == "side"  ? arm_mount_x
  : pose == "max"   ? arm_mount_x + arm_reach
  :                   arm_mount_x;

function arm_y_for_pose(pose) =
    is_undef(arm_reach) ? undef
  : pose == "side" ? arm_reach
  : 0;

function system_com(pose) =
    (!mass_data_known || is_undef(total_robot_mass) || is_undef(arm_mass)
     || is_undef(com_x) || is_undef(arm_reach)) ? undef
  : let (ma = arm_mass + (is_undef(arm_payload) ? 0 : arm_payload),
         mt = total_robot_mass + ma)
    [(total_robot_mass * com_x + ma * arm_x_for_pose(pose)) / mt,
     (total_robot_mass * com_y + ma * arm_y_for_pose(pose)) / mt];

// ---------------------------------------------------------------------------
//  ZAPAS UDZWIGU - ile masy wolno jeszcze powiesic na licu montazu ramienia,
//  zanim margines projektowy padnie. m_arm to CALA masa na tym licu
//  (ramie + narzedzie + obiekt), nie tylko obiekt.
//
//  Skan, nie wzor: wiazaca krawedz polygonu podparcia zmienia sie z poza
//  ramienia, wiec rozwiazanie analityczne wymagaloby rozpatrzenia kazdej
//  krawedzi osobno. 201 podstawien liczy sie natychmiast i nie da sie
//  pomylic co do tego, ktora krawedz wygrala.
// ---------------------------------------------------------------------------
function com_with_arm(pose, m_arm) =
    let (mt = total_robot_mass + m_arm)
    [(total_robot_mass * com_x + m_arm * arm_x_for_pose(pose)) / mt,
     (total_robot_mass * com_y + m_arm * arm_y_for_pose(pose)) / mt];

headroom_scan_max = 20;   // kg, gorny kraniec skanu - nie szukamy wyzej

function payload_headroom(pts, pose, req, hi = headroom_scan_max, n = 200) =
    let (ok = [for (i = [0 : n])
               let (m = i * hi / n)
               if (poly_margin(pts, com_with_arm(pose, m)) >= req) m])
    len(ok) == 0 ? 0 : max(ok);

// ---------------------------------------------------------------------------
//  RYSOWANIE
// ---------------------------------------------------------------------------
module draw_poly(pts, h = 1.2, c = col_poly, alpha = 0.85) {
    color(c, alpha) linear_extrude(h) polygon(pts);
}

// polygon podparcia + strefa dopuszczalna CoM
module draw_support(v) {
    p  = support_poly(v);
    pe = support_poly(v, true);

    // obrys polygonu
    color(col_poly, 0.9)
        linear_extrude(1.5)
            difference() { polygon(p); offset(delta = -6) polygon(p); }

    // strefa dopuszczalna CoM = polygon zwezony o wymagany margines
    color([0.15, 0.75, 0.35], 0.30)
        linear_extrude(0.8) offset(delta = -stability_margin_req) polygon(p);

    // polygon awaryjny wariantu C
    if (v == "C")
        color(col_warn, 0.5)
            linear_extrude(0.6)
                difference() { polygon(pe); polygon(p); }

    // punkty kontaktu
    for (q = contacts(v))
        color(q[2] == 0 ? [0.1, 0.1, 0.1]
            : q[2] == 1 ? [0.35, 0.35, 0.4] : col_warn)
            translate([q[0], q[1], 0]) cylinder(d = q[2] == 0 ? 34 : 24, h = 3);
}

// znacznik rzutu srodka masy
module com_marker(p, c = [0.9, 0.1, 0.1]) {
    if (!is_undef(p)) {
        color(c) {
            translate([p[0], p[1], 0]) cylinder(d = 26, h = 6);
            translate([p[0], p[1], 0]) cylinder(d = 6, h = 260);
        }
    }
}

// os obrotu naped roznicowego + promien zamiatania
module draw_turning(v) {
    color([0.5, 0.5, 0.55], 0.25)
        linear_extrude(0.4)
            difference() {
                circle(r = turning_radius());
                circle(r = turning_radius() - 4);
            }
    color([0.2, 0.2, 0.25])
        translate([drive_axle_x, 0, 0]) cylinder(d = 12, h = 8);
}

// ---------------------------------------------------------------------------
//  ROZKLAD I KIERUNEK SIL
//  Strzalki pokazuja KIERUNKI, nie wartosci. Wartosci wymagaja mas, ktorych
//  jeszcze nie ma - patrz TO VERIFY w raporcie.
// ---------------------------------------------------------------------------
module arrow(from, dir, len = 90, d = 7, c = [0.85, 0.2, 0.1]) {
    color(c)
    translate(from) {
        // trzon wzdluz zadanego kierunku
        rotate(dir == "up"    ? [0, 0, 0]
             : dir == "down"  ? [180, 0, 0]
             : dir == "fwd"   ? [0, 90, 0] : [0, -90, 0]) {
            cylinder(d = d, h = len - 18);
            translate([0, 0, len - 18]) cylinder(d1 = d * 2.2, d2 = 0, h = 18);
        }
    }
}

module draw_forces(v) {
    for (q = contacts(v)) {
        if (q[2] == 2) {
            // anti-tip: brak reakcji w normalnej jezdzie
            color([0.5, 0.5, 0.5, 0.5])
                translate([q[0], q[1], antitip_gap / 2])
                    cube([50, 50, antitip_gap], center = true);
        } else {
            // Reakcja normalna. Strzalka jest odsunieta na zewnatrz kola,
            // inaczej chowa sie w bryle opony i nic nie widac.
            off = q[2] == 0 ? sign(q[1]) * (wheel_width / 2 + 30)
                            : sign(q[1]) * (caster_width / 2 + 25);
            arrow([q[0], q[1] + off, 0], "up", q[2] == 0 ? 250 : 150, 8,
                  q[2] == 0 ? [0.85, 0.2, 0.1] : [0.2, 0.45, 0.8]);
            // sila napedowa - tylko kola napedowe, kierunek jazdy
            if (q[2] == 0)
                arrow([q[0] + 20, q[1] + off, 12], "fwd", 130, 9,
                      [0.15, 0.6, 0.25]);
        }
    }
    // ciezar w rzucie srodka masy (albo w srodku pasma gdy brak danych)
    cm = system_com(arm_pose);
    cx = is_undef(cm) ? com_band_mid_x(support_poly(v), stability_margin_req)
                      : cm[0];
    cy = is_undef(cm) ? 0 : cm[1];
    arrow([cx, cy, 320], "down", 150, 11, [0.1, 0.1, 0.1]);
}

// ---------------------------------------------------------------------------
//  RAPORT
// ---------------------------------------------------------------------------
module stability_report(v) {
    p  = support_poly(v);
    pe = support_poly(v, true);

    echo("======================================================");
    echo(str("  STABILNOSC - wariant ", v));
    echo("======================================================");
    echo(str("  polygon podparcia, wierzcholki : ", [for (q = p) [round(q[0]), round(q[1])]]));
    echo(str("    (wazny przy kazdym ustawieniu casterow: kolo ", caster_swivel_off,
             " mm od osi skretu)"));
    echo(str("  promien zamiatania             : ", round(turning_radius()), " mm"));
    echo(str("  wymagany margines projektowy   : ", stability_margin_req, " mm"));
    echo("------------------------------------------------------");
    echo("  DOPUSZCZALNA STREFA SRODKA MASY (czysta geometria,");
    echo("  nie wymaga zadnych mas - obowiazuje juz teraz):");
    echo(str("    CoM X w osi symetrii: od ", min_com_x(p, stability_margin_req),
             " do ", max_com_x(p, stability_margin_req)));
    echo(str("    CoM Y na osi napedu : +/- ", max_com_y(p, stability_margin_req)));
    if (v == "C")
        echo(str("    po opadnieciu na anti-tip do tylu az do X = ",
                 min_com_x(pe, stability_margin_req)));
    echo(str("    lico montazu ramienia jest na X = ", arm_mount_x, " -> ",
             arm_mount_x > max_com_x(p, stability_margin_req)
             ? "POZA strefa. Samo ramie nie moze byc dominujaca masa."
             : "w strefie."));
    echo("------------------------------------------------------");
    echo("  TRAKCJA (granica ciala sztywnego, patrz komentarz w kodzie)");
    let (xm = com_band_mid_x(p, stability_margin_req),
         f0 = drive_load_fraction(v, xm))
        echo(str("    przy CoM X=", xm, " (srodek dopuszczalnego pasma): ",
                 f0 == -1 ? "NIEWYZNACZALNY - 4 sztywne narozniki"
               : f0 == -2 ? "CoM za osia napedu - opad na anti-tip"
               : str(round(f0 * 100), " % ciezaru na kolach napedowych")));
    echo("------------------------------------------------------");

    if (!mass_data_known) {
        echo("  MARGINES STABILNOSCI : TO VERIFY");
        echo("  Powod: brak mas i zasiegu ramienia. Nie zgaduje.");
        echo("  Potrzebne: total_robot_mass, arm_mass, arm_payload,");
        echo("             arm_reach, com_x, com_y, com_z.");
        echo("  Ustaw mass_data_known = true po pomiarach.");
    } else {
        for (pose = ["front", "side", "max"]) {
            c = system_com(pose);
            if (is_undef(c))
                echo(str("  poza ", pose, " : TO VERIFY - niepelne dane"));
            else
                echo(str("  poza ", pose, " : CoM [", round(c[0]), ", ",
                         round(c[1]), "]  margines ",
                         round(poly_margin(p, c)), " mm  -> ",
                         poly_margin(p, c) >= stability_margin_req ? "PASS"
                       : poly_margin(p, c) > 0 ? "RISK" : "FAIL"));
        }

        echo("------------------------------------------------------");
        echo("  ZAPAS UDZWIGU (do marginesu projektowego, nie do wywrotki)");
        for (pose = ["front", "side", "max"]) {
            h  = payload_headroom(p, pose, stability_margin_req);
            h0 = payload_headroom(p, pose, 0);
            echo(str("    poza ", pose, " : na licu montazu wolno ",
                     round(10 * h) / 10, " kg (ramie ", arm_mass,
                     " -> na narzedzie i obiekt zostaje ",
                     round(10 * (h - arm_mass)) / 10, " kg)",
                     "   do wywrotki: ",
                     h0 >= headroom_scan_max
                       ? str("> ", headroom_scan_max, " (sufit skanu)")
                       : str(round(h0)), " kg"));
        }
    }
    echo("  Test STATYCZNY na plaskiej podlodze. Bez dynamiki, hamowania,");
    echo("  sil bocznych w skrecie i podatnosci opon.");
    echo("======================================================");
}

// ---------------------------------------------------------------------------
//  PORONANIE WSZYSTKICH TRZECH WARIANTOW
//  Wszystko ponizej to czysta geometria - zadnych mas, zadnego zgadywania.
// ---------------------------------------------------------------------------
module compare_variants() {
    m = stability_margin_req;
    echo("==========================================================");
    echo("  POROWNANIE WARIANTOW PODPARCIA (geometria, bez mas)");
    echo(str("  wymagany margines = ", m, " mm,  os napedu X = ", drive_axle_x));
    echo("==========================================================");
    for (v = ["A", "B", "C"]) {
        p  = support_poly(v);
        c  = contacts(v);
        nc = len([for (q = c) if (q[2] != 2) 1]);
        lo = min_com_x(p, m);
        hi = max_com_x(p, m);
        wy = max_com_y(p, m);
        band = (lo > 9000 || hi < -9000) ? -1 : hi - lo;
        echo(str("  --- wariant ", v, " -----------------------------------"));
        echo(str("    kontakty w normalnej jezdzie : ", nc));
        echo(str("    pole polygonu                : ",
                 round(poly_area(p) / 100) / 100, " dm2"));
        echo(str("    dopuszczalne pasmo CoM w X   : ",
                 band < 0 ? "BRAK - polygon za maly na ten margines"
                          : str(lo, " .. ", hi, "  (szerokosc ", band, " mm)")));
        echo(str("    dopuszczalne CoM w Y         : +/- ",
                 wy < -9000 ? 0 : wy, " mm"));
        echo(str("    statycznie wyznaczalny       : ",
                 nc == 3 ? "TAK" : str("NIE (", nc, " punkty sztywne)")));
    }
    echo("==========================================================");
}

// Wplyw polozenia osi napedowej na pasmo CoM i promien zamiatania.
// To jest glowne pokretlo projektowe bazy, wiec warto je zobaczyc.
module sweep_drive_axle(v) {
    m = stability_margin_req;
    echo(str("  --- wplyw drive_axle_x, wariant ", v, " ---"));
    echo("    axle_x   pasmo CoM X        szer.   R zamiatania");
    for (ax = [-120, -80, -40, 0, 40]) {
        p = support_poly(v, false, ax);
        lo = min_com_x(p, m);
        hi = max_com_x(p, m);
        r  = max(norm([half_l - ax, half_w]), norm([half_l + ax, half_w]));
        echo(str("    ", ax, "     ", lo > 9000 ? "BRAK" : str(lo, " .. ", hi),
                 "        ", lo > 9000 ? 0 : hi - lo, "     ", round(r)));
    }
}
