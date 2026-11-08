#Author-
#Description-Mobile_Manipulator_V1_Chassis - rama z profili aluminiowych pod mobilnego manipulatora
#
# Uklad wspolrzednych:
#   origin = podloga (Z=0), srodek footprintu podwozia
#   +X = przod robota, +Y = lewa strona, +Z = gora
#
# Stos pionowy (wszystko wyprowadzone z parametrow):
#   45  ..  49   taca baterii (blacha 4 mm, podwieszona pod ramami)
#   49  .. 159   bateria 320 x 120 x 110
#  160  .. 240   profile glowne 40x80 (80 mm w pionie)
#  200  .. 240   poprzeczki 40x40 (licowane z gora profili)
#  240  .. 250   plyta CNC pod kolumne 295 x 295 x 10
#
# Spod profili = 160 mm, bo tyle ma wysokosci calkowitej caster Ø125.
# Plyta montazowa castera wkreca sie wprost w dolny rowek profilu 40x80.

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
V = {}
_warn = []


# ----------------------------------------------------------------------------
# Parametry
# ----------------------------------------------------------------------------
PARAMS = [
    # ---------- wymagane przez specyfikacje ----------
    ('base_width',            '540',                  'Max szerokosc podwozia'),
    ('base_length',           '600',                  'Dlugosc podwozia'),
    ('ground_clearance',      '45',                   'Min przeswit - dotyczy tacy baterii'),
    ('main_profile_width',    '40',                   'Profil glowny 40x80 - szerokosc'),
    ('main_profile_height',   '80',                   'Profil glowny 40x80 - wysokosc (pionowo)'),
    ('main_profile_length',   '600',                  'Profil glowny 40x80 - dlugosc'),
    ('cross_profile_size',    '40',                   'Poprzeczka 40x40'),
    ('wheel_diameter',        '216',                  'Hub-motor 8.5 cala'),
    ('wheel_radius',          'wheel_diameter / 2',   'Promien kola = wysokosc osi'),
    ('column_plate_size',     '295',                  'Plyta CNC pod kolumne'),
    ('column_hole_pitch',     '250',                  'Raster otworow montazowych'),
    ('column_hole_diameter',  '8',                    'Otwory montazowe kolumny'),
    ('battery_length',        '320',                  'Bateria - placeholder'),
    ('battery_width',         '120',                  'Bateria - placeholder'),
    ('battery_height',        '110',                  'Bateria - placeholder'),

    # ---------- geometria ramy ----------
    ('rail_y_offset',         '125',
     'Os profilu glownego. 125 => lico zewn. 145, wewn. 105, oparcie plyty 42.5 mm na profil'),
    ('rail_inner_y',          'rail_y_offset - main_profile_width / 2',  'Lico wewnetrzne profilu'),
    ('rail_outer_y',          'rail_y_offset + main_profile_width / 2',  'Lico zewnetrzne profilu'),
    ('cross_profile_length',  '2 * rail_inner_y',     'Poprzeczka miedzy licami profili glownych'),
    ('cross_end_x',           'base_length / 2 - cross_profile_size / 2', 'Poprzeczka przednia/tylna'),

    # ---------- castery (definiuja wysokosc ramy) ----------
    ('caster_diameter',       '125',                  'Kolo bierne 125-150 mm'),
    ('caster_width',          '40',                   'PLACEHOLDER - szerokosc kola biernego'),
    ('caster_mount_height',   '160',
     'PLACEHOLDER - wysokosc calkowita castera od podlogi do lica plyty montazowej'),
    ('caster_plate_size',     '100',                  'PLACEHOLDER - plyta montazowa castera'),
    ('caster_plate_thickness', '8',                   'PLACEHOLDER - plyta montazowa castera'),
    ('caster_fork_length',    '60',                   'PLACEHOLDER - widelec'),
    ('caster_fork_width',     '70',                   'PLACEHOLDER - widelec'),
    ('caster_fork_height',
     'caster_mount_height - caster_plate_thickness - caster_diameter / 2',
     'Wysokosc widelca wynika z pozostalych wymiarow castera'),
    ('caster_x_forward',      'base_length / 2 - caster_diameter / 2 - 10',
     'Castery przy przednich narozach, kolo 10 mm w obrysie'),

    # ---------- pietra ramy ----------
    ('frame_bottom_z',        'caster_mount_height',
     'Spod profili glownych siada na plytach montazowych casterow'),
    ('frame_top_z',           'frame_bottom_z + main_profile_height', 'Gora profili glownych'),
    ('column_plate_thickness', '10',                  'Plyta CNC 8-10 mm'),
    ('column_plate_top_z',    'frame_top_z + column_plate_thickness', 'Gora plyty CNC'),

    # ---------- taca baterii ----------
    ('tray_thickness',        '4',                    'Blacha aluminiowa 3-5 mm'),
    ('tray_bottom_z',         'ground_clearance',     'Najnizszy punkt maszyny'),
    ('tray_top_z',            'tray_bottom_z + tray_thickness', 'Lico gorne tacy'),
    ('tray_length',           'battery_length + 20',  'Taca z zapasem na pasy'),
    ('tray_width',            '2 * rail_inner_y',     'Taca miedzy licami profili glownych'),
    ('tray_flange_top_z',     'frame_bottom_z + 40',
     'Kolnierze tacy siegaja 40 mm w gore lica wewnetrznego profilu'),
    ('battery_top_z',         'tray_top_z + battery_height', 'Wierzch ogniw'),

    # ---------- hub-motory: PLACEHOLDER, ZMIERZYC PO DOSTAWIE ----------
    ('wheel_width',           '70',                   'PLACEHOLDER - szerokosc opony'),
    ('wheel_hub_diameter',    '160',                  'PLACEHOLDER - srednica korpusu silnika'),
    ('wheel_hub_width',       '60',                   'PLACEHOLDER - szerokosc korpusu silnika'),
    ('drive_axle_x_behind',   '180',                  'Os napedowa w tylnej tercji ramy'),
    ('torque_arm_thickness',  '10',                   'PLACEHOLDER - grubosc plyty momentowej'),
    ('torque_arm_length',     '180',                  'PLACEHOLDER - dlugosc plyty momentowej'),
    ('torque_arm_bottom_z',   'wheel_radius - 60',    'PLACEHOLDER - plyta siega ponizej osi'),
    ('torque_arm_height',     'frame_top_z - torque_arm_bottom_z', 'Od ponizej osi do gory ramy'),
    ('axle_bore_diameter',    '14',                   'PLACEHOLDER - otwor pod os hub-motora'),
    ('wheel_running_gap',     '3',                    'Luz miedzy plyta momentowa a opona'),
    ('wheel_inner_y',
     'rail_outer_y + torque_arm_thickness + wheel_running_gap', 'Lico wewnetrzne opony'),
    ('wheel_center_y',        'wheel_inner_y + wheel_width / 2', 'Plaszczyzna srodkowa kola'),
    ('chassis_total_width',   '2 * (wheel_inner_y + wheel_width)', 'Calkowita szerokosc z kolami'),

    # ---------- geometria referencyjna ----------
    ('ref_sheet_thickness',   '1',                    'Grubosc plaszczyzn referencyjnych'),
    ('threshold_low',         '20',                   'Prog niski'),
    ('threshold_high',        '30',                   'Prog wysoki'),
    ('threshold_depth',       '200',                  'Glebokosc progu'),
    ('threshold_length',      '1000',                 'Dlugosc progu'),
    ('threshold_low_x',       '650',                  'Pozycja progu niskiego'),
    ('threshold_high_x',      '900',                  'Pozycja progu wysokiego'),
    ('door_width',            '600',                  'Referencyjny otwor drzwiowy'),
    ('door_height',           '2000',                 'Referencyjny otwor drzwiowy'),
    ('door_frame_thickness',  '100',                  'Osciez'),
    ('door_distance',         '1200',                 'Odleglosc drzwi przed robotem'),
]

COLORS = {
    'main_profile':  (60, 60, 65),      # profile 40x80 - ciemnoszary
    'cross_profile': (140, 140, 145),   # poprzeczki 40x40 - sredni szary
    'tray':          (60, 60, 65),      # taca baterii - ciemnoszary
    'cnc':           (240, 130, 20),    # plyta CNC - pomaranczowy
    'wheel':         (25, 25, 25),      # kola - czarne
    'placeholder':   (200, 40, 40),     # plyty momentowe i wsporniki - czerwone
    'reference':     (60, 120, 220),    # geometria referencyjna - niebieski
    'battery':       (70, 95, 130),     # placeholder baterii (poza schematem, dla czytelnosci)
}
APPEARANCES = {}


# ----------------------------------------------------------------------------
# Helpery
# ----------------------------------------------------------------------------
def _mm(expr):
    if isinstance(expr, (int, float)):
        return float(expr)
    return float(eval(expr, {'__builtins__': {}}, V))


def _cm(expr):
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
    if key in APPEARANCES:
        return APPEARANCES[key]
    rgb = COLORS[key]
    result = None
    try:
        name = 'CHS_' + key
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


def _finish(comp, profile, name, height, z0, color, symmetric=False):
    feats = comp.features.extrudeFeatures
    ei = feats.createInput(profile, adsk.fusion.FeatureOperations.NewBodyFeatureOperation)
    if symmetric:
        ei.setSymmetricExtent(_vi(height), True)
    else:
        ei.setDistanceExtent(False, _vi(height))
        if str(z0) != '0':
            ei.startExtent = adsk.fusion.OffsetStartDefinition.create(_vi(z0))
    body = feats.add(ei).bodies.item(0)
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
    return _finish(comp, sk.profiles.item(0), name, hz, z0, color)


def _cylinder(comp, name, dia, length, color=None):
    """Walec o osi wzdluz Y, wysrodkowany w lokalnym origin komponentu."""
    sk = comp.sketches.add(comp.xZConstructionPlane)
    sk.name = name + '_sk'
    circ = sk.sketchCurves.sketchCircles.addByCenterRadius(
        adsk.core.Point3D.create(0, 0, 0), _cm(dia) / 2.0)
    _dim_circle(sk, circ, dia)
    return _finish(comp, sk.profiles.item(0), name, length, '0', color, symmetric=True)


def _ring(comp, name, outer_dia, inner_dia, length, color=None):
    """Pierscien (opona) o osi wzdluz Y, wysrodkowany w lokalnym origin."""
    sk = comp.sketches.add(comp.xZConstructionPlane)
    sk.name = name + '_sk'
    o = adsk.core.Point3D.create(0, 0, 0)
    c1 = sk.sketchCurves.sketchCircles.addByCenterRadius(o, _cm(outer_dia) / 2.0)
    c2 = sk.sketchCurves.sketchCircles.addByCenterRadius(o, _cm(inner_dia) / 2.0)
    _dim_circle(sk, c1, outer_dia)
    _dim_circle(sk, c2, inner_dia)
    return _finish(comp, _profile_with_loops(sk, 2), name, length, '0', color, symmetric=True)


def _plate_xz(comp, name, lx, hz, cz, thickness, hole_dia=None, color=None):
    """Plyta pionowa w plaszczyznie XZ, wyciagana symetrycznie wzgledem lokalnego origin.
    Szkic na XZ ma lokalne Y = globalne -Z, stad minusy przy wspolrzednej pionowej.
    Opcjonalny otwor lezy dokladnie w lokalnym origin (osi kola)."""
    sk = comp.sketches.add(comp.xZConstructionPlane)
    sk.name = name + '_sk'
    ctr = adsk.core.Point3D.create(0, -_cm(cz), 0)
    corner = adsk.core.Point3D.create(_cm(lx) / 2.0, -_cm(cz) + _cm(hz) / 2.0, 0)
    rect = sk.sketchCurves.sketchLines.addCenterPointRectangle(ctr, corner)
    _dim_rect(sk, rect, lx, hz)
    loops = 1
    if hole_dia:
        circ = sk.sketchCurves.sketchCircles.addByCenterRadius(
            adsk.core.Point3D.create(0, 0, 0), _cm(hole_dia) / 2.0)
        _dim_circle(sk, circ, hole_dia)
        loops = 2
    return _finish(comp, _profile_with_loops(sk, loops), name, thickness, '0', color,
                   symmetric=True)


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
    return _finish(comp, _profile_with_loops(sk, 5), name, thickness, z0, color)


# ----------------------------------------------------------------------------
# 01_Main_Frame — dwa profile 40x80, 80 mm w pionie
# ----------------------------------------------------------------------------
def build_main_frame():
    occ = _new_comp(_root, '01_Main_Frame')
    comp = occ.component
    for side, sign in (('L', ''), ('R', '-')):
        _box(comp, 'Main_Profile_40x80_' + side,
             'main_profile_length', 'main_profile_width', 'main_profile_height',
             cy=sign + 'rail_y_offset', z0='frame_bottom_z', color='main_profile')
    try:
        occ.isGrounded = True
    except:
        pass
    return comp


# ----------------------------------------------------------------------------
# 02_Cross_Members — trzy poprzeczki 40x40 licowane z gora profili glownych
# ----------------------------------------------------------------------------
def build_cross_members():
    comp = _new_comp(_root, '02_Cross_Members').component
    z0 = 'frame_top_z - cross_profile_size'
    for name, cx in (('Front', 'cross_end_x'), ('Column', '0'), ('Rear', '-cross_end_x')):
        _box(comp, 'Cross_Profile_40x40_' + name,
             'cross_profile_size', 'cross_profile_length', 'cross_profile_size',
             cx=cx, z0=z0, color='cross_profile')
    return comp


# ----------------------------------------------------------------------------
# 03_Battery_Tray — blacha 4 mm podwieszona pod ramami + placeholder ogniw
# ----------------------------------------------------------------------------
def build_battery_tray():
    comp = _new_comp(_root, '03_Battery_Tray').component
    _box(comp, 'Battery_Tray_Sheet', 'tray_length', 'tray_width', 'tray_thickness',
         z0='tray_bottom_z', color='tray')
    flange_cy = '(rail_inner_y - tray_thickness / 2)'
    for side, sign in (('L', ''), ('R', '-')):
        _box(comp, 'Battery_Tray_Flange_' + side,
             'tray_length', 'tray_thickness', 'tray_flange_top_z - tray_top_z',
             cy=sign + flange_cy, z0='tray_top_z', color='tray')
    _box(comp, 'Battery_Placeholder', 'battery_length', 'battery_width', 'battery_height',
         z0='tray_top_z', color='battery')
    return comp


# ----------------------------------------------------------------------------
# 04_Column_CNC_Plate — 295 x 295 x 10, 4 x Ø8 w rastrze 250 x 250
# ----------------------------------------------------------------------------
def build_column_plate():
    comp = _new_comp(_root, '04_Column_CNC_Plate').component
    _plate_with_holes(comp, 'Column_Mount_Plate_CNC', 'column_plate_size',
                      'column_plate_thickness', 'column_hole_pitch', 'column_hole_diameter',
                      z0='frame_top_z', color='cnc')
    return comp


# ----------------------------------------------------------------------------
# 05_Hub_Motor_Placeholders — kola 8.5" + plyty momentowe (do przeprojektowania)
# ----------------------------------------------------------------------------
def build_hub_motors():
    comp = _new_comp(_root, '05_Hub_Motor_Placeholders').component
    for side, sign in (('L', ''), ('R', '-')):
        wheel = _new_comp(comp, 'PLACEHOLDER_Hub_Wheel_' + side,
                          tx='-drive_axle_x_behind', ty=sign + 'wheel_center_y',
                          tz='wheel_radius').component
        _ring(wheel, 'Tire_8_5_inch', 'wheel_diameter', 'wheel_hub_diameter',
              'wheel_width', color='wheel')
        _cylinder(wheel, 'Hub_Motor_Body', 'wheel_hub_diameter', 'wheel_hub_width',
                  color='wheel')

        arm = _new_comp(comp, 'PLACEHOLDER_Torque_Arm_' + side,
                        tx='-drive_axle_x_behind',
                        ty=sign + '(rail_outer_y + torque_arm_thickness / 2)',
                        tz='wheel_radius').component
        _plate_xz(arm, 'Torque_Arm_Plate', 'torque_arm_length', 'torque_arm_height',
                  '(torque_arm_bottom_z + torque_arm_height / 2) - wheel_radius',
                  'torque_arm_thickness', hole_dia='axle_bore_diameter', color='placeholder')
    return comp


# ----------------------------------------------------------------------------
# 06_Caster_Placeholders — kola bierne Ø125 przy przednich narozach
# ----------------------------------------------------------------------------
def build_casters():
    comp = _new_comp(_root, '06_Caster_Placeholders').component
    for side, sign in (('L', ''), ('R', '-')):
        c = _new_comp(comp, 'PLACEHOLDER_Caster_' + side,
                      tx='caster_x_forward', ty=sign + 'rail_y_offset',
                      tz='caster_diameter / 2').component
        _cylinder(c, 'Caster_Wheel', 'caster_diameter', 'caster_width', color='wheel')
        _box(c, 'Caster_Fork', 'caster_fork_length', 'caster_fork_width',
             'caster_fork_height', color='placeholder')
        _box(c, 'Caster_Mount_Plate', 'caster_plate_size', 'caster_plate_size',
             'caster_plate_thickness', z0='caster_fork_height', color='placeholder')
    return comp


# ----------------------------------------------------------------------------
# 07_Reference_Geometry
# ----------------------------------------------------------------------------
def build_reference():
    occ = _new_comp(_root, '07_Reference_Geometry')
    comp = occ.component

    _box(comp, 'REF_Floor_Plane_Footprint', 'base_length', 'base_width', 'ref_sheet_thickness',
         z0='-ref_sheet_thickness', color='reference')
    _box(comp, 'REF_Ground_Clearance_45mm', 'base_length', 'base_width', 'ref_sheet_thickness',
         z0='ground_clearance - ref_sheet_thickness', color='reference')

    _box(comp, 'REF_Threshold_20mm', 'threshold_depth', 'threshold_length', 'threshold_low',
         cx='threshold_low_x', color='reference')
    _box(comp, 'REF_Threshold_30mm', 'threshold_depth', 'threshold_length', 'threshold_high',
         cx='threshold_high_x', color='reference')

    jamb = 'door_width / 2 + door_frame_thickness / 2'
    for side, sign in (('L', ''), ('R', '-')):
        _box(comp, 'REF_Door_Jamb_' + side,
             'door_frame_thickness', 'door_frame_thickness', 'door_height',
             cx='door_distance', cy=sign + '(' + jamb + ')', color='reference')
    _box(comp, 'REF_Door_Header', 'door_frame_thickness',
         'door_width + 2 * door_frame_thickness', 'door_frame_thickness',
         cx='door_distance', z0='door_height', color='reference')

    try:
        comp.opacity = 0.3
    except:
        _warn.append('Nie udalo sie ustawic przezroczystosci geometrii referencyjnej.')
    return comp


# ----------------------------------------------------------------------------
# Kontrola konstrukcji
# ----------------------------------------------------------------------------
def check_layout():
    if V['chassis_total_width'] > V['base_width']:
        _warn.append('Szerokosc z kolami {:.0f} mm przekracza base_width {:.0f} mm.'
                     .format(V['chassis_total_width'], V['base_width']))

    bearing = V['column_plate_size'] / 2 - V['rail_inner_y']
    if bearing < 15:
        _warn.append('Plyta CNC opiera sie tylko {:.1f} mm na kazdym profilu - '
                     'zmniejsz rail_y_offset.'.format(bearing))

    if V['battery_top_z'] > V['frame_top_z'] - V['cross_profile_size']:
        _warn.append('Bateria siega {:.0f} mm, spod poprzeczek jest na {:.0f} mm - kolizja.'
                     .format(V['battery_top_z'], V['frame_top_z'] - V['cross_profile_size']))

    if V['battery_width'] > V['tray_width']:
        _warn.append('Bateria szersza niz rozstaw profili glownych.')

    if V['tray_bottom_z'] < V['ground_clearance']:
        _warn.append('Taca baterii ponizej wymaganego przeswitu.')

    stack = V['caster_diameter'] / 2 + V['caster_fork_height'] + V['caster_plate_thickness']
    if abs(stack - V['frame_bottom_z']) > 0.1:
        _warn.append('Stos castera {:.1f} mm != spod ramy {:.0f} mm.'
                     .format(stack, V['frame_bottom_z']))

    if V['wheel_diameter'] > V['frame_top_z']:
        _warn.append('Kola {:.0f} mm wystaja ponad gore ramy {:.0f} mm - potrzebne bledniki.'
                     .format(V['wheel_diameter'], V['frame_top_z']))

    front = V['caster_x_forward'] + V['caster_diameter'] / 2
    rear = V['drive_axle_x_behind'] + V['wheel_radius']
    if max(front, rear) > V['base_length'] / 2:
        _warn.append('Kola wystaja poza obrys 600 mm: przod {:.0f}, tyl {:.0f} (limit {:.0f}).'
                     .format(front, rear, V['base_length'] / 2))

    if V['base_width'] > V['door_width'] - 40:
        _warn.append('Malo luzu w drzwiach: {:.0f} mm na {:.0f} mm otworu.'
                     .format(V['base_width'], V['door_width']))


# ----------------------------------------------------------------------------
# Sterowanie
# ----------------------------------------------------------------------------
def setup(new_document=True):
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
        _root.name = 'Mobile_Manipulator_V1_Chassis'
    except:
        _warn.append('Nazwa roota ustawi sie po zapisaniu dokumentu.')

    _add_params()


def build_all():
    build_main_frame()
    build_cross_members()
    build_battery_tray()
    build_column_plate()
    build_hub_motors()
    build_casters()
    build_reference()


def report():
    check_layout()
    try:
        _app.activeViewport.fit()
    except:
        pass

    msg = ('Mobile_Manipulator_V1_Chassis utworzone.\n\n'
           'STOS PIONOWY (mm):\n'
           '  taca baterii        {tray_bottom_z:5.0f} .. {tray_top_z:.0f}\n'
           '  bateria             {tray_top_z:5.0f} .. {battery_top_z:.0f}\n'
           '  profile 40x80       {frame_bottom_z:5.0f} .. {frame_top_z:.0f}\n'
           '  poprzeczki 40x40    {cross_bottom:5.0f} .. {frame_top_z:.0f}\n'
           '  plyta CNC           {frame_top_z:5.0f} .. {column_plate_top_z:.0f}\n'
           '  kola                    0 .. {wheel_diameter:.0f}\n\n'
           'SZEROKOSCI (mm):\n'
           '  rozstaw kol         {track:5.0f}\n'
           '  calkowita z kolami  {chassis_total_width:5.0f}  (limit {base_width:.0f})\n'
           '  oparcie plyty CNC   {bearing:5.1f}  na kazdym profilu\n'
           '  przeswit pod rama   {frame_bottom_z:5.0f}  (pod taca {ground_clearance:.0f})\n'
           .format(cross_bottom=V['frame_top_z'] - V['cross_profile_size'],
                   track=2 * V['wheel_center_y'],
                   bearing=V['column_plate_size'] / 2 - V['rail_inner_y'], **V))
    if _warn:
        msg += '\nDO SPRAWDZENIA ({}):\n- '.format(len(_warn)) + '\n- '.join(_warn)
    else:
        msg += '\nKontrola konstrukcji bez zastrzezen.'
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
            _ui.messageBox(msg, 'Mobile_Manipulator_V1_Chassis')
    except:
        err = 'Blad podczas budowy podwozia:\n{}'.format(traceback.format_exc())
        print(err)
        if _ui and SHOW_MESSAGE_BOX:
            _ui.messageBox(err, 'Mobile_Manipulator_V1_Chassis')
