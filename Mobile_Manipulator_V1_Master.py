#Author-
#Description-Mobile_Manipulator_V1_Master - bazowe zlozenie referencyjne mobilnej platformy pod ramie PAR6
#
# Uklad wspolrzednych:
#   origin = podloga (Z=0), srodek footprintu bazy
#   +X = przod robota, +Y = lewa strona, +Z = gora
#
# Model jest referencyjny/layoutowy. Grubosci, wysokosci i offsety Z sa
# sterowane wyrazeniami parametrycznymi. Pozycje X/Y sa liczone z tych samych
# parametrow przy generowaniu - zmiana parametru pozycyjnego wymaga ponownego
# uruchomienia skryptu (rozmiary brył aktualizuja sie od razu w Fusion).

import adsk.core
import adsk.fusion
import traceback

# Wylacz, jesli wymiarowanie szkicow sprawia problemy w Twojej wersji Fusion.
DIMENSION_SKETCHES = True

# Ustaw False przy uruchamianiu przez most MCP - messageBox blokuje watek glowny.
SHOW_MESSAGE_BOX = True

_app = None
_ui = None
_des = None
_root = None
V = {}        # nazwa parametru -> wartosc w mm
_warn = []


# ----------------------------------------------------------------------------
# Parametry
# ----------------------------------------------------------------------------
# (nazwa, wyrazenie, komentarz)   wyrazenie musi byc czytelne i dla Fusion i dla Pythona
PARAMS = [
    # --- wymagane przez specyfikacje ---
    ('base_width',              '540',                          'Max szerokosc platformy z kolami'),
    ('base_length',             '600',                          'Docelowa dlugosc platformy'),
    ('ground_clearance',        '45',                           'Min przeswit pod rama'),
    ('wheel_diameter',          '216',                          'Hub-motor 8.5 cala'),
    ('wheel_radius',            'wheel_diameter / 2',           'Promien kola'),
    ('wheel_width',             '70',                           'PLACEHOLDER - zmierzyc na hoverboardzie'),
    ('wheel_axle_height',       'wheel_radius',                 'Wysokosc osi nad podloga'),
    ('wheel_to_wheel_spacing',  '460',                          'Rozstaw plaszczyzn srodkowych kol'),
    ('caster_diameter',         '125',                          'Kolo bierne'),
    ('column_plate_size',       '295',                          'Plyta montazowa kolumny'),
    ('column_hole_pitch',       '250',                          'Raster otworow kolumny'),
    ('column_hole_diameter',    '8',                            'Otwory montazowe kolumny'),
    ('column_closed_height',    '360',                          'Kolumna zlozona'),
    ('column_stroke',           '440',                          'Skok kolumny'),
    ('column_open_height',      'column_closed_height + column_stroke', 'Kolumna rozlozona'),
    ('battery_length',          '320',                          'Bateria referencyjna 36V'),
    ('battery_width',           '120',                          'Bateria referencyjna 36V'),
    ('battery_height',          '110',                          'Bateria referencyjna 36V'),
    ('base_plate_thickness',    '6',                            'Plyta denna ramy'),
    ('top_plate_thickness',     '8',                            'Plyta gorna pod kolumne'),
    ('profile_width',           '40',                           'Profil aluminiowy - szerokosc'),
    ('profile_height',          '80',                           'Profil aluminiowy - wysokosc'),
    ('par6_mount_height_offset','20',                           'Odstep adapter CNC -> baza PAR6'),

    # --- placeholdery hub-motorow: ZMIERZYC PO DOSTAWIE ---
    ('wheel_hub_diameter',      '160',                          'PLACEHOLDER - srednica piasty/silnika'),
    ('wheel_hub_width',         '60',                           'PLACEHOLDER - szerokosc piasty/silnika'),
    ('wheel_axle_diameter',     '12',                           'PLACEHOLDER - srednica osi'),
    ('wheel_axle_length',       '140',                          'PLACEHOLDER - calkowita dlugosc osi'),
    ('wheel_side_clearance',    '10',                           'Luz miedzy oponą a plyta denna'),
    ('drive_axle_x_behind',     '60',                           'Os napedowa X mm za srodkiem bazy'),

    # --- kola bierne ---
    ('caster_x_forward',        '220',                          'Caster X mm przed srodkiem bazy'),
    ('caster_y_offset',         '150',                          'Caster odsuniecie od osi Y'),
    ('caster_width',            '40',                           'Szerokosc kola biernego'),
    ('caster_fork_width',       '90',                           'Widelec castera'),
    ('caster_fork_height',      '60',                           'Od osi kola do plyty montazowej'),
    ('caster_plate_size',       '100',                          'Plyta montazowa castera'),
    ('caster_plate_thickness',  '8',                            'Plyta montazowa castera'),

    # --- rama ---
    ('base_plate_width',        'wheel_to_wheel_spacing - wheel_width - 2 * wheel_side_clearance',
                                                                'Szerokosc plyty dennej miedzy kolami'),
    ('profile_y_offset',        'base_plate_width / 2 - profile_width / 2', 'Pozycja profili podluznych'),
    ('cross_member_length',     'base_plate_width - 2 * profile_width', 'Dlugosc poprzeczek'),
    ('cross_member_x',          'base_length / 2 - profile_width / 2', 'Pozycja poprzeczek'),

    # --- kolumna ---
    ('column_plate_thickness',  '10',                           'Grubosc plyt kolumny'),
    ('column_seg1_size',        '150',                          'Segment dolny - przekroj'),
    ('column_seg2_size',        '130',                          'Segment srodkowy - przekroj'),
    ('column_seg3_size',        '110',                          'Segment gorny - przekroj'),
    ('column_segment_height',   'column_closed_height - 2 * column_plate_thickness', 'Dlugosc segmentu'),

    # --- adaptery CNC ---
    ('adapter_plate_size',      'column_plate_size + 35',       'Plyta adaptera CNC'),
    ('adapter_thickness',       '10',                           'Grubosc adaptera CNC'),

    # --- bateria ---
    ('battery_x_behind',        '60',                           'Bateria X mm za srodkiem bazy'),

    # --- PAR6 (uproszczony) ---
    ('par6_base_diameter',      '120',                          'Baza ramienia'),
    ('par6_base_height',        '100',                          'Baza ramienia'),
    ('par6_link_size',          '90',                           'Przekroj ogniwa zlozonego'),
    ('par6_folded_height',      '400',                          'Wysokosc ramienia w pozycji zlozonej'),
    ('par6_max_reach',          '600',                          'Maksymalny wysieg do przodu'),
    ('par6_envelope_width',     '400',                          'Szerokosc obrysu roboczego'),
    ('par6_envelope_height',    '800',                          'Wysokosc obrysu roboczego'),
    ('par6_com_x_forward',      '80',                           'Srodek masy ramienia - X'),
    ('par6_com_height',         '250',                          'Srodek masy ramienia - Z nad baza'),

    # --- elektronika ---
    ('buck_column_l',           '120',  'Przetwornica 36-42V -> 24V (kolumna)'),
    ('buck_column_w',           '80',   'Przetwornica 36-42V -> 24V (kolumna)'),
    ('buck_column_h',           '40',   'Przetwornica 36-42V -> 24V (kolumna)'),
    ('buck_par6_l',             '120',  'Przetwornica 36-42V -> 24V (PAR6)'),
    ('buck_par6_w',             '80',   'Przetwornica 36-42V -> 24V (PAR6)'),
    ('buck_par6_h',             '40',   'Przetwornica 36-42V -> 24V (PAR6)'),
    ('power_hub_l',             '160',  'Plytka Power Hub'),
    ('power_hub_w',             '100',  'Plytka Power Hub'),
    ('power_hub_h',             '40',   'Plytka Power Hub'),
    ('contactor_l',             '60',   'Stycznik'),
    ('contactor_w',             '50',   'Stycznik'),
    ('contactor_h',             '70',   'Stycznik'),
    ('fuse_l',                  '60',   'Bezpiecznik glowny'),
    ('fuse_w',                  '40',   'Bezpiecznik glowny'),
    ('fuse_h',                  '50',   'Bezpiecznik glowny'),
    ('estop_l',                 '40',   'Przycisk E-stop'),
    ('estop_w',                 '40',   'Przycisk E-stop'),
    ('estop_h',                 '60',   'Przycisk E-stop'),

    # --- osłony (placeholder) ---
    ('cover_height',            '100',  'Zapas wysokosci osłony nad rama'),

    # --- geometria referencyjna otoczenia ---
    ('door_width',              '600',  'Referencyjny otwor drzwiowy'),
    ('door_height',             '2000', 'Referencyjny otwor drzwiowy'),
    ('door_frame_thickness',    '100',  'Osciez drzwi'),
    ('door_distance',           '1200', 'Odleglosc drzwi przed robotem'),
    ('threshold_low',           '20',   'Prog niski'),
    ('threshold_high',          '30',   'Prog wysoki'),
    ('threshold_depth',         '200',  'Glebokosc progu'),
    ('threshold_length',        '1000', 'Dlugosc progu'),
    ('threshold_low_x',         '650',  'Pozycja progu niskiego'),
    ('threshold_high_x',        '900',  'Pozycja progu wysokiego'),

    # --- pietra konstrukcji (wyprowadzone) ---
    ('frame_deck_z',            'ground_clearance + base_plate_thickness', 'Gora plyty dennej'),
    ('frame_top_z',             'frame_deck_z + profile_height',           'Gora profili ramy'),
    ('column_mount_z',          'frame_top_z + top_plate_thickness',       'Gora plyty pod kolumne'),
    ('column_base_z',           'column_mount_z + adapter_thickness',      'Spod kolumny'),
    ('column_top_z',            'column_base_z + column_closed_height',    'Gora kolumny (zlozona)'),
    ('par6_base_z',             'column_top_z + adapter_thickness + par6_mount_height_offset', 'Spod bazy PAR6'),
]

COLORS = {
    'frame':       (70, 70, 75),
    'wheel':       (25, 25, 25),
    'battery':     (30, 90, 200),
    'column':      (185, 190, 195),
    'par6':        (240, 240, 240),
    'electronics': (30, 160, 70),
    'adapter':     (240, 130, 20),
    'reference':   (150, 150, 150),
    'cover':       (120, 130, 150),
}
APPEARANCES = {}


# ----------------------------------------------------------------------------
# Helpery
# ----------------------------------------------------------------------------
def _mm(expr):
    """Wylicza wyrazenie parametryczne na wartosc w mm."""
    if isinstance(expr, (int, float)):
        return float(expr)
    return float(eval(expr, {'__builtins__': {}}, V))


def _cm(expr):
    """Fusion API pracuje wewnetrznie w cm."""
    return _mm(expr) / 10.0


def _vi(expr):
    return adsk.core.ValueInput.createByString(str(expr))


def _add_params():
    for name, expr, comment in PARAMS:
        V[name] = _mm(expr)
        existing = _des.userParameters.itemByName(name)
        if existing:
            existing.expression = expr
            existing.comment = comment
        else:
            _des.userParameters.add(name, _vi(expr), 'mm', comment)


def _appearance(key):
    """Kopiuje dowolna appearance z biblioteki i nadpisuje jej kolor."""
    if key in APPEARANCES:
        return APPEARANCES[key]
    rgb = COLORS[key]
    result = None
    try:
        name = 'MM_' + key
        found = _des.appearances.itemByName(name)
        if found:
            APPEARANCES[key] = found
            return found
        base = _des.appearances.item(0) if _des.appearances.count > 0 else None
        if base is None:
            for i in range(_app.materialLibraries.count):
                lib = _app.materialLibraries.item(i)
                if lib.appearances.count > 0:
                    base = lib.appearances.item(0)
                    break
        if base is not None:
            result = _des.appearances.addByCopy(base, name)
            for i in range(result.appearanceProperties.count):
                prop = result.appearanceProperties.item(i)
                if prop.objectType == adsk.core.ColorProperty.classType():
                    prop.value = adsk.core.Color.create(rgb[0], rgb[1], rgb[2], 255)
                    break
    except:
        _warn.append('Nie udalo sie utworzyc koloru: ' + key)
        result = None
    APPEARANCES[key] = result
    return result


def _new_comp(parent, name, tx='0', ty='0', tz='0'):
    m = adsk.core.Matrix3D.create()
    m.translation = adsk.core.Vector3D.create(_cm(tx), _cm(ty), _cm(tz))
    occ = parent.occurrences.addNewComponent(m)
    occ.component.name = name
    return occ


def _dim_rect(sk, rect, lx, wy):
    if not DIMENSION_SKETCHES:
        return
    did_h = did_v = False
    for i in range(rect.count):
        ln = rect.item(i)
        s = ln.startSketchPoint.geometry
        e = ln.endSketchPoint.geometry
        horiz = abs(e.x - s.x) >= abs(e.y - s.y)
        tp = adsk.core.Point3D.create((s.x + e.x) / 2.0, (s.y + e.y) / 2.0 - 1.0, 0)
        try:
            if horiz and not did_h:
                d = sk.sketchDimensions.addDistanceDimension(
                    ln.startSketchPoint, ln.endSketchPoint,
                    adsk.fusion.DimensionOrientations.HorizontalDimensionOrientation, tp)
                d.parameter.expression = lx
                did_h = True
            elif (not horiz) and not did_v:
                d = sk.sketchDimensions.addDistanceDimension(
                    ln.startSketchPoint, ln.endSketchPoint,
                    adsk.fusion.DimensionOrientations.VerticalDimensionOrientation, tp)
                d.parameter.expression = wy
                did_v = True
        except:
            _warn.append('Bez wymiaru szkicowego: ' + sk.name)
            return


def _dim_circle(sk, circle, dia):
    if not DIMENSION_SKETCHES:
        return
    try:
        c = circle.centerSketchPoint.geometry
        tp = adsk.core.Point3D.create(c.x + 1.0, c.y + 1.0, 0)
        d = sk.sketchDimensions.addDiameterDimension(circle, tp)
        d.parameter.expression = dia
    except:
        _warn.append('Bez wymiaru srednicy: ' + sk.name)


def _profile_with_loops(sk, loops):
    for i in range(sk.profiles.count):
        p = sk.profiles.item(i)
        if p.profileLoops.count == loops:
            return p
    best = None
    for i in range(sk.profiles.count):
        p = sk.profiles.item(i)
        if best is None or p.profileLoops.count > best.profileLoops.count:
            best = p
    return best


def _extrude(comp, profile, name, height, z0, color):
    feats = comp.features.extrudeFeatures
    ei = feats.createInput(profile, adsk.fusion.FeatureOperations.NewBodyFeatureOperation)
    ei.setDistanceExtent(False, _vi(height))
    if str(z0) != '0':
        ei.startExtent = adsk.fusion.OffsetStartDefinition.create(_vi(z0))
    feat = feats.add(ei)
    body = feat.bodies.item(0)
    body.name = name
    if color:
        ap = _appearance(color)
        if ap:
            body.appearance = ap
    return body


def _box(comp, name, lx, wy, hz, cx='0', cy='0', z0='0', color=None):
    """Prostopadloscian: srodek footprintu w (cx, cy), dol na wysokosci z0."""
    sk = comp.sketches.add(comp.xYConstructionPlane)
    sk.name = name + '_sk'
    ctr = adsk.core.Point3D.create(_cm(cx), _cm(cy), 0)
    corner = adsk.core.Point3D.create(_cm(cx) + _cm(lx) / 2.0, _cm(cy) + _cm(wy) / 2.0, 0)
    rect = sk.sketchCurves.sketchLines.addCenterPointRectangle(ctr, corner)
    _dim_rect(sk, rect, lx, wy)
    return _extrude(comp, sk.profiles.item(0), name, hz, z0, color)


def _cylinder(comp, name, plane, dia, length, z0='0', color=None, symmetric=True):
    """Walec o osi prostopadlej do 'plane', srodek w lokalnym origin plaszczyzny."""
    sk = comp.sketches.add(plane)
    sk.name = name + '_sk'
    circ = sk.sketchCurves.sketchCircles.addByCenterRadius(
        adsk.core.Point3D.create(0, 0, 0), _cm(dia) / 2.0)
    _dim_circle(sk, circ, dia)
    feats = comp.features.extrudeFeatures
    ei = feats.createInput(sk.profiles.item(0), adsk.fusion.FeatureOperations.NewBodyFeatureOperation)
    if symmetric:
        ei.setSymmetricExtent(_vi(length), True)
    else:
        ei.setDistanceExtent(False, _vi(length))
        if str(z0) != '0':
            ei.startExtent = adsk.fusion.OffsetStartDefinition.create(_vi(z0))
    feat = feats.add(ei)
    body = feat.bodies.item(0)
    body.name = name
    if color:
        ap = _appearance(color)
        if ap:
            body.appearance = ap
    return body


def _ring(comp, name, plane, outer_dia, inner_dia, length, color=None):
    """Pierscien (opona) - profil o dwoch petlach, wyciagniety symetrycznie."""
    sk = comp.sketches.add(plane)
    sk.name = name + '_sk'
    o = adsk.core.Point3D.create(0, 0, 0)
    c1 = sk.sketchCurves.sketchCircles.addByCenterRadius(o, _cm(outer_dia) / 2.0)
    c2 = sk.sketchCurves.sketchCircles.addByCenterRadius(o, _cm(inner_dia) / 2.0)
    _dim_circle(sk, c1, outer_dia)
    _dim_circle(sk, c2, inner_dia)
    feats = comp.features.extrudeFeatures
    ei = feats.createInput(_profile_with_loops(sk, 2),
                           adsk.fusion.FeatureOperations.NewBodyFeatureOperation)
    ei.setSymmetricExtent(_vi(length), True)
    feat = feats.add(ei)
    body = feat.bodies.item(0)
    body.name = name
    if color:
        ap = _appearance(color)
        if ap:
            body.appearance = ap
    return body


def _plate_with_holes(comp, name, size, thickness, pitch, hole_dia,
                      cx='0', cy='0', z0='0', color=None):
    """Kwadratowa plyta z 4 otworami w rastrze pitch x pitch."""
    sk = comp.sketches.add(comp.xYConstructionPlane)
    sk.name = name + '_sk'
    ctr = adsk.core.Point3D.create(_cm(cx), _cm(cy), 0)
    corner = adsk.core.Point3D.create(_cm(cx) + _cm(size) / 2.0, _cm(cy) + _cm(size) / 2.0, 0)
    rect = sk.sketchCurves.sketchLines.addCenterPointRectangle(ctr, corner)
    half = _cm(pitch) / 2.0
    first = None
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = sk.sketchCurves.sketchCircles.addByCenterRadius(
                adsk.core.Point3D.create(_cm(cx) + sx * half, _cm(cy) + sy * half, 0),
                _cm(hole_dia) / 2.0)
            if first is None:
                first = c
    _dim_rect(sk, rect, size, size)
    _dim_circle(sk, first, hole_dia)
    return _extrude(comp, _profile_with_loops(sk, 5), name, thickness, z0, color)


def _point(comp, name, x, y, z):
    """Punkt konstrukcyjny. W trybie parametrycznym setByPoint przyjmuje tylko
    SketchPoint - Point3D rzuca 'Environment is not supported'."""
    plane = comp.xYConstructionPlane if _mm(z) == 0 else _plane_at_z(comp, name + '_plane', z)
    sk = comp.sketches.add(plane)
    sk.name = name + '_sk'
    sp = sk.sketchPoints.add(adsk.core.Point3D.create(_cm(x), _cm(y), 0))
    ci = comp.constructionPoints.createInput()
    ci.setByPoint(sp)
    p = comp.constructionPoints.add(ci)
    p.name = name
    return p


def _axis(comp, name, plane, p1, p2):
    """Os konstrukcyjna przez dwa punkty szkicu na zadanej plaszczyznie.
    setByLine(InfiniteLine3D) jest niedostepne w trybie parametrycznym."""
    sk = comp.sketches.add(plane)
    sk.name = name + '_sk'
    a = sk.sketchPoints.add(adsk.core.Point3D.create(_cm(p1[0]), _cm(p1[1]), 0))
    b = sk.sketchPoints.add(adsk.core.Point3D.create(_cm(p2[0]), _cm(p2[1]), 0))
    ci = comp.constructionAxes.createInput()
    ci.setByTwoPoints(a, b)
    ax = comp.constructionAxes.add(ci)
    ax.name = name
    return ax


def _plane_at_z(comp, name, z):
    ci = comp.constructionPlanes.createInput()
    ci.setByOffset(comp.xYConstructionPlane, _vi(z))
    p = comp.constructionPlanes.add(ci)
    p.name = name
    return p


# ----------------------------------------------------------------------------
# 00_Reference_Geometry
# ----------------------------------------------------------------------------
def build_reference():
    comp = _new_comp(_root, '00_Reference_Geometry').component

    # Ground Plane = XY. Obrys maksymalnego footprintu bazy.
    sk = comp.sketches.add(comp.xYConstructionPlane)
    sk.name = 'Max_Footprint_600x540'
    rect = sk.sketchCurves.sketchLines.addCenterPointRectangle(
        adsk.core.Point3D.create(0, 0, 0),
        adsk.core.Point3D.create(_cm('base_length') / 2.0, _cm('base_width') / 2.0, 0))
    _dim_rect(sk, rect, 'base_length', 'base_width')

    # Progi referencyjne przed robotem.
    _box(comp, 'Threshold_20mm', 'threshold_depth', 'threshold_length', 'threshold_low',
         cx='threshold_low_x', color='reference')
    _box(comp, 'Threshold_30mm', 'threshold_depth', 'threshold_length', 'threshold_high',
         cx='threshold_high_x', color='reference')

    # Referencyjny otwor drzwiowy 600 mm.
    jamb_y = 'door_width / 2 + door_frame_thickness / 2'
    _box(comp, 'Door_Jamb_L', 'door_frame_thickness', 'door_frame_thickness', 'door_height',
         cx='door_distance', cy=jamb_y, color='reference')
    _box(comp, 'Door_Jamb_R', 'door_frame_thickness', 'door_frame_thickness', 'door_height',
         cx='door_distance', cy='-(' + jamb_y + ')', color='reference')
    _box(comp, 'Door_Header', 'door_frame_thickness',
         'door_width + 2 * door_frame_thickness', 'door_frame_thickness',
         cx='door_distance', z0='door_height', color='reference')

    # Osie i plaszczyzny do pozniejszego projektowania adapterow.
    pl_axle = _plane_at_z(comp, 'PLANE_Drive_Axle', 'wheel_axle_height')
    _axis(comp, 'AXIS_Drive_Axle', pl_axle,
          ('-drive_axle_x_behind', '-wheel_to_wheel_spacing / 2'),
          ('-drive_axle_x_behind', 'wheel_to_wheel_spacing / 2'))
    pl_caster = _plane_at_z(comp, 'PLANE_Caster_Axle', 'caster_diameter / 2')
    _axis(comp, 'AXIS_Caster_Front', pl_caster,
          ('caster_x_forward', '-caster_y_offset'),
          ('caster_x_forward', 'caster_y_offset'))
    # Szkic na XZ ma lokalne Y = globalne -Z, stad minus (inaczej punkt ladowalby pod podloga).
    _axis(comp, 'AXIS_Column_Center', comp.xZConstructionPlane,
          ('0', '0'), ('0', '-column_top_z'))
    _plane_at_z(comp, 'PLANE_Frame_Top', 'frame_top_z')
    _plane_at_z(comp, 'PLANE_Column_Mount', 'column_mount_z')
    _plane_at_z(comp, 'PLANE_Column_Base', 'column_base_z')
    _plane_at_z(comp, 'PLANE_Column_Top', 'column_top_z')
    _plane_at_z(comp, 'PLANE_PAR6_Mount', 'par6_base_z')
    return comp


# ----------------------------------------------------------------------------
# 01_Hoverboard_Drive
# ----------------------------------------------------------------------------
def _build_wheel(comp):
    """Geometria w lokalnym origin = srodek osi kola, os wzdluz Y."""
    _ring(comp, 'Tire', comp.xZConstructionPlane,
          'wheel_diameter', 'wheel_hub_diameter', 'wheel_width', color='wheel')
    _cylinder(comp, 'Hub_Motor', comp.xZConstructionPlane,
              'wheel_hub_diameter', 'wheel_hub_width', color='frame')
    _cylinder(comp, 'Axle', comp.xZConstructionPlane,
              'wheel_axle_diameter', 'wheel_axle_length', color='frame')


def _build_caster(comp):
    """Geometria w lokalnym origin = srodek osi kola biernego."""
    _cylinder(comp, 'Caster_Wheel', comp.xZConstructionPlane,
              'caster_diameter', 'caster_width', color='wheel')
    _box(comp, 'Caster_Fork', 'caster_width + 20', 'caster_fork_width', 'caster_fork_height',
         color='frame')
    _box(comp, 'Caster_Mount_Plate', 'caster_plate_size', 'caster_plate_size',
         'caster_plate_thickness', z0='caster_fork_height', color='frame')


def build_drive():
    comp = _new_comp(_root, '01_Hoverboard_Drive').component
    half = 'wheel_to_wheel_spacing / 2'

    _build_wheel(_new_comp(comp, 'Hub_Wheel_Left',
                           tx='-drive_axle_x_behind', ty=half,
                           tz='wheel_axle_height').component)
    _build_wheel(_new_comp(comp, 'Hub_Wheel_Right',
                           tx='-drive_axle_x_behind', ty='-(' + half + ')',
                           tz='wheel_axle_height').component)
    _build_caster(_new_comp(comp, 'Caster_Front_Left',
                            tx='caster_x_forward', ty='caster_y_offset',
                            tz='caster_diameter / 2').component)
    _build_caster(_new_comp(comp, 'Caster_Front_Right',
                            tx='caster_x_forward', ty='-caster_y_offset',
                            tz='caster_diameter / 2').component)
    return comp


# ----------------------------------------------------------------------------
# 02_Base_Frame
# ----------------------------------------------------------------------------
def build_frame():
    occ = _new_comp(_root, '02_Base_Frame')
    comp = occ.component

    _box(comp, 'Base_Plate', 'base_length', 'base_plate_width', 'base_plate_thickness',
         z0='ground_clearance', color='frame')
    for side, sign in (('L', ''), ('R', '-')):
        _box(comp, 'Long_Profile_' + side, 'base_length', 'profile_width', 'profile_height',
             cy=sign + 'profile_y_offset', z0='frame_deck_z', color='frame')
    for side, sign in (('Front', ''), ('Rear', '-')):
        _box(comp, 'Cross_Member_' + side, 'profile_width', 'cross_member_length', 'profile_height',
             cx=sign + 'cross_member_x', z0='frame_deck_z', color='frame')
    # Bez poprzeczki centralnej - to miejsce zajmuje bateria.
    _box(comp, 'Column_Mount_Plate', 'column_plate_size', 'column_plate_size',
         'top_plate_thickness', z0='frame_top_z', color='frame')

    try:
        occ.isGrounded = True
    except:
        pass
    return comp


# ----------------------------------------------------------------------------
# 03_Battery
# ----------------------------------------------------------------------------
def build_battery():
    comp = _new_comp(_root, '03_Battery').component
    _box(comp, 'Battery_36V_Reference', 'battery_length', 'battery_width', 'battery_height',
         cx='-battery_x_behind', z0='frame_deck_z', color='battery')
    _point(comp, 'Battery_CoM_Reference',
           '-battery_x_behind', '0', 'frame_deck_z + battery_height / 2')
    return comp


# ----------------------------------------------------------------------------
# 04_Lift_Column
# ----------------------------------------------------------------------------
def build_column():
    comp = _new_comp(_root, '04_Lift_Column').component
    base_z = 'column_base_z'

    fixed_occ = _new_comp(comp, 'Column_Fixed_Base', tz=base_z)
    fixed = fixed_occ.component
    _plate_with_holes(fixed, 'Column_Bottom_Plate', 'column_plate_size',
                      'column_plate_thickness', 'column_hole_pitch', 'column_hole_diameter',
                      color='column')
    _box(fixed, 'Column_Segment_1', 'column_seg1_size', 'column_seg1_size',
         'column_segment_height', z0='column_plate_thickness', color='column')
    p_fixed = _point(fixed, 'JOINT_Column_Base', '0', '0', '0')

    # Dwa stopnie po pol skoku - segmenty zachowuja zachodzenie na calej dlugosci.
    seg2_occ = _new_comp(comp, 'Column_Segment_2', tz=base_z)
    _box(seg2_occ.component, 'Column_Segment_2_Body', 'column_seg2_size', 'column_seg2_size',
         'column_segment_height', z0='column_plate_thickness', color='column')
    p_seg2 = _point(seg2_occ.component, 'JOINT_Segment_2', '0', '0', '0')

    seg3_occ = _new_comp(comp, 'Column_Segment_3', tz=base_z)
    _box(seg3_occ.component, 'Column_Segment_3_Body', 'column_seg3_size', 'column_seg3_size',
         'column_segment_height', z0='column_plate_thickness', color='column')
    p_seg3 = _point(seg3_occ.component, 'JOINT_Segment_3', '0', '0', '0')

    top_occ = _new_comp(comp, 'Column_Top_Plate', tz=base_z)
    top = top_occ.component
    _plate_with_holes(top, 'Column_Top_Plate_Body', 'column_plate_size',
                      'column_plate_thickness', 'column_hole_pitch', 'column_hole_diameter',
                      z0='column_closed_height - column_plate_thickness', color='column')
    p_top = _point(top, 'JOINT_Column_Top', '0', '0', '0')

    half = 'column_stroke / 2'
    _slider(comp, seg2_occ, p_seg2, fixed_occ, p_fixed, 'Column_Slider_Stage_1', half)
    _slider(comp, seg3_occ, p_seg3, seg2_occ, p_seg2, 'Column_Slider_Stage_2', half)
    _rigid(comp, top_occ, p_top, seg3_occ, p_seg3, 'Column_Top_Plate_Rigid')
    return comp


def _joint_input(parent, occ_a, pt_a, occ_b, pt_b):
    return parent.joints.createInput(
        adsk.fusion.JointGeometry.createByPoint(pt_a.createForAssemblyContext(occ_a)),
        adsk.fusion.JointGeometry.createByPoint(pt_b.createForAssemblyContext(occ_b)))


def _slider(parent, moving_occ, moving_pt, fixed_occ, fixed_pt, name, limit='column_stroke'):
    try:
        ji = _joint_input(parent, moving_occ, moving_pt, fixed_occ, fixed_pt)
        ji.setAsSliderJointMotion(adsk.fusion.JointDirections.ZAxisJointDirection)
        joint = parent.joints.add(ji)
        joint.name = name
        lim = joint.jointMotion.slideLimits
        lim.isMinimumValueEnabled = True
        lim.minimumValue = 0.0
        lim.isMaximumValueEnabled = True
        lim.maximumValue = _cm(limit)
        joint.jointMotion.slideValue = 0.0
    except:
        _warn.append('Nie udalo sie utworzyc jointa: ' + name +
                     ' (dodaj recznie Slider 0-{:.0f} mm)'.format(_mm(limit)))


def _rigid(parent, occ_a, pt_a, occ_b, pt_b, name):
    try:
        ji = _joint_input(parent, occ_a, pt_a, occ_b, pt_b)
        ji.setAsRigidJointMotion()
        joint = parent.joints.add(ji)
        joint.name = name
    except:
        _warn.append('Nie udalo sie utworzyc jointa sztywnego: ' + name)


# ----------------------------------------------------------------------------
# 05_PAR6_Reference
# ----------------------------------------------------------------------------
def build_par6():
    comp = _new_comp(_root, '05_PAR6_Reference', tz='par6_base_z').component

    body = _new_comp(comp, 'PAR6_Body_Folded').component
    _cylinder(body, 'PAR6_Base', body.xYConstructionPlane,
              'par6_base_diameter', 'par6_base_height', color='par6', symmetric=False)
    _box(body, 'PAR6_Link_Folded_1', 'par6_link_size', 'par6_link_size',
         'par6_folded_height - par6_base_height - par6_link_size',
         z0='par6_base_height', color='par6')
    _box(body, 'PAR6_Link_Folded_2', 'par6_link_size * 2', 'par6_link_size * 0.8',
         'par6_link_size', cx='par6_link_size / 2',
         z0='par6_folded_height - par6_link_size', color='par6')

    env_occ = _new_comp(comp, 'PAR6_Reach_Envelope')
    env = env_occ.component
    _box(env, 'PAR6_Max_Reach_Envelope', 'par6_max_reach', 'par6_envelope_width',
         'par6_envelope_height', cx='par6_max_reach / 2',
         z0='-par6_envelope_height / 2', color='par6')
    try:
        env.opacity = 0.3
    except:
        pass

    _point(comp, 'PAR6_CoM_Reference', 'par6_com_x_forward', '0', 'par6_com_height')
    return comp


# ----------------------------------------------------------------------------
# 06_Electronics
# ----------------------------------------------------------------------------
# (nazwa, dl, szer, wys, x, y, z0)  - pozycje X/Y edytuj tutaj
ELECTRONICS = [
    ('Buck_36V_to_24V_Column', 'buck_column_l', 'buck_column_w', 'buck_column_h', '-60', '105', 'frame_deck_z'),
    ('Buck_36V_to_24V_PAR6',   'buck_par6_l',   'buck_par6_w',   'buck_par6_h',   '-60', '-105', 'frame_deck_z'),
    ('Power_Hub_Board',        'power_hub_l',   'power_hub_w',   'power_hub_h',   '190', '0',    'frame_deck_z'),
    ('Main_Contactor',         'contactor_l',   'contactor_w',   'contactor_h',   '110', '110',  'frame_deck_z'),
    ('Main_Fuse',              'fuse_l',        'fuse_w',        'fuse_h',        '110', '-110', 'frame_deck_z'),
    ('E_Stop_Button',          'estop_l',       'estop_w',       'estop_h',       '-280', '0',   'frame_top_z'),
]


def build_electronics():
    comp = _new_comp(_root, '06_Electronics').component
    for name, lx, wy, hz, cx, cy, z0 in ELECTRONICS:
        _box(comp, name, lx, wy, hz, cx=cx, cy=cy, z0=z0, color='electronics')
    return comp


# ----------------------------------------------------------------------------
# 07_Covers_Placeholders
# ----------------------------------------------------------------------------
def build_covers():
    comp = _new_comp(_root, '07_Covers_Placeholders').component
    _box(comp, 'Main_Cover_Envelope', 'base_length', 'base_width',
         'frame_top_z + cover_height - ground_clearance',
         z0='ground_clearance', color='cover')
    half = 'wheel_to_wheel_spacing / 2'
    for side, sign in (('L', ''), ('R', '-')):
        _box(comp, 'Wheel_Arch_' + side, 'wheel_diameter + 40', 'wheel_width + 20',
             'wheel_radius + 40', cx='-drive_axle_x_behind', cy=sign + half,
             z0='ground_clearance', color='cover')
    try:
        comp.opacity = 0.35
    except:
        pass
    return comp


# ----------------------------------------------------------------------------
# 08_CNC_Adapters
# ----------------------------------------------------------------------------
def build_adapters():
    comp = _new_comp(_root, '08_CNC_Adapters').component
    _plate_with_holes(comp, 'Base_Column_Adapter', 'adapter_plate_size', 'adapter_thickness',
                      'column_hole_pitch', 'column_hole_diameter',
                      z0='column_mount_z', color='adapter')
    _plate_with_holes(comp, 'Column_PAR6_Adapter', 'adapter_plate_size', 'adapter_thickness',
                      'column_hole_pitch', 'column_hole_diameter',
                      z0='column_top_z', color='adapter')
    return comp


# ----------------------------------------------------------------------------
# Kontrola zaleznosci (liczbowa, nie kosmetyczna)
# ----------------------------------------------------------------------------
def check_layout():
    battery_top = V['frame_deck_z'] + V['battery_height']
    if battery_top > V['frame_top_z']:
        _warn.append(
            'KOLIZJA: bateria siega {:.0f} mm, gora ramy jest na {:.0f} mm '
            '(brakuje {:.0f} mm). Ustaw profile_height >= {:.0f} albo obniz battery_height.'
            .format(battery_top, V['frame_top_z'], battery_top - V['frame_top_z'],
                    V['profile_height'] + battery_top - V['frame_top_z']))

    caster_face = V['caster_diameter'] / 2 + V['caster_fork_height'] + V['caster_plate_thickness']
    if caster_face > V['frame_deck_z']:
        _warn.append(
            'KOLIZJA: plyta montazowa castera wypada na {:.0f} mm, spod ramy jest na {:.0f} mm '
            '(o {:.0f} mm za wysoko). Potrzebna kieszen w ramie, mniejszy caster_diameter '
            'albo nizszy caster_fork_height.'
            .format(caster_face, V['ground_clearance'], caster_face - V['ground_clearance']))

    wheel_outer = V['wheel_to_wheel_spacing'] + V['wheel_width']
    if wheel_outer > V['base_width']:
        _warn.append('Kola wystaja poza base_width: {:.0f} mm > {:.0f} mm.'
                     .format(wheel_outer, V['base_width']))

    axle_outer = V['wheel_to_wheel_spacing'] + V['wheel_axle_length']
    if axle_outer > V['base_width']:
        _warn.append(
            'Osie placeholder daja {:.0f} mm calkowitej szerokosci (base_width {:.0f} mm). '
            'Skroc wheel_axle_length do <= {:.0f} mm po pomiarze hoverboarda.'
            .format(axle_outer, V['base_width'], V['base_width'] - V['wheel_to_wheel_spacing']))

    if V['base_width'] > V['door_width'] - 40:
        _warn.append('Malo luzu w drzwiach: {:.0f} mm na {:.0f} mm otworu.'
                     .format(V['base_width'], V['door_width']))

    if V['base_plate_width'] - 2 * V['profile_width'] < V['battery_width']:
        _warn.append('Bateria nie miesci sie miedzy profilami podluznymi.')


# ----------------------------------------------------------------------------
# run
# ----------------------------------------------------------------------------
def setup(new_document=True):
    """Tworzy dokument, ustawia jednostki i parametry. Wywolac przed build_*()."""
    global _app, _ui, _des, _root
    _app = adsk.core.Application.get()
    _ui = _app.userInterface

    if new_document:
        _app.documents.add(adsk.core.DocumentTypes.FusionDesignDocumentType)
    _des = adsk.fusion.Design.cast(_app.activeProduct)
    _des.designType = adsk.fusion.DesignTypes.ParametricDesignType
    try:
        _des.unitsManager.distanceDisplayUnits = adsk.fusion.DistanceUnits.MillimeterDistanceUnits
    except:
        _warn.append('Nie udalo sie ustawic mm jako jednostek - sprawdz Document Settings.')

    _root = _des.rootComponent
    try:
        _root.name = 'Mobile_Manipulator_V1_Master'
    except:
        _warn.append('Nazwa roota ustawi sie po zapisaniu dokumentu.')

    _add_params()


def build_all():
    build_reference()
    build_drive()
    build_frame()
    build_battery()
    build_column()
    build_par6()
    build_electronics()
    build_covers()
    build_adapters()


def report():
    check_layout()
    try:
        _app.activeViewport.fit()
    except:
        pass

    msg = ('Master assembly "Mobile_Manipulator_V1_Master" zostalo utworzone.\n\n'
           'Wysokosc zlozona (spod bazy PAR6): {:.0f} mm\n'
           'Wysokosc po rozlozeniu kolumny:   {:.0f} mm\n'
           'Kolumna: 2 x Slider 0-{:.0f} mm = skok {:.0f} mm ({:.0f} -> {:.0f} mm)\n'
           .format(V['par6_base_z'], V['par6_base_z'] + V['column_stroke'],
                   V['column_stroke'] / 2, V['column_stroke'],
                   V['column_closed_height'], V['column_open_height']))
    if _warn:
        msg += '\nDO SPRAWDZENIA ({}):\n- '.format(len(_warn)) + '\n- '.join(_warn)
    else:
        msg += '\nBrak wykrytych kolizji w kontroli layoutu.'
    return msg


def run(context):
    global _ui
    _ui = None
    try:
        setup()
        build_all()
        msg = report()
        print(msg)
        if SHOW_MESSAGE_BOX:
            _ui.messageBox(msg, 'Mobile_Manipulator_V1_Master')
    except:
        err = 'Blad podczas budowy zlozenia:\n{}'.format(traceback.format_exc())
        print(err)
        if _ui and SHOW_MESSAGE_BOX:
            _ui.messageBox(err, 'Mobile_Manipulator_V1_Master')
