#Author-
#Description-Dzwignia pomiarowa momentu na walek 8 mm (NEMA23 57BYG250B) - przyrzad testowy, druk FDM
#
# Uklad wspolrzednych:
#   origin = OS WALKA, z = 0 to SPOD czesci (plaszczyzna stolu drukarki)
#   +X = kierunek ramienia,  +Z = wzdluz walka,  +/-Y = grubosc srodnika
#
# ORIENTACJA DRUKU JEST CZESCIA KONSTRUKCJI, NIE DODATKIEM
#   Czesc lezy na stole dokladnie tak, jak jest zbudowana w tym skrypcie:
#   os otworu piasty PIONOWO. Dwa powody, oba twarde:
#     1. Zacisk trzyma sie naprezeniem obwodowym wokol otworu. Przy osi
#        pionowej to naprezenie biegnie W warstwie. Przy osi poziomej
#        rozrywaloby warstwy - piasta pekla by wzdluz szwu przy pierwszym
#        dokreceniu.
#     2. Zginanie ramienia biegnie wzdluz osi belki, czyli tez w warstwie.
#   Zadnych podpor, otwor piasty wychodzi okragly.
#
# Uruchomienie: Fusion -> Utilities -> Add-Ins -> Scripts -> Run
# Liczby sprawdzone w test_rig/lever_check.py - zmieniasz tu, przelicz tam.

import adsk.core
import adsk.fusion
import traceback

# Ustaw False przy uruchamianiu przez most MCP - messageBox blokuje watek glowny.
SHOW_MESSAGE_BOX = True

# Pierscien probny: 6 mm plaster piasty obok czesci glownej. Drukuje sie
# w kilka minut i mowi, czy otwor 8.2 wychodzi na Twojej drukarce na wymiar.
# Taniej niz przekonac sie o tym po 40 minutach druku calej dzwigni.
MAKE_TEST_RING = True

_app = None
_ui = None
_des = None
_root = None
V = {}
_warn = []


# ----------------------------------------------------------------------------
# Parametry
# ----------------------------------------------------------------------------
# (nazwa, wyrazenie, komentarz)   wyrazenie musi byc czytelne i dla Fusion i dla Pythona
PARAMS = [
    # --- interfejs z silnikiem ---
    ('shaft_d',        '8',    'Srednica walka 57BYG250B [VERIFY - zmierzyc]'),
    ('bore_d',         '8.2',  'Otwor piasty - luz pod skurcz druku, kalibrowac pierscieniem'),
    ('hub_d',          '26',   'Srednica zewnetrzna piasty'),
    ('hub_h',          '22',   'Dlugosc zacisku wzdluz walka [MEASURE - wolna dlugosc walka]'),

    # --- ramie ---
    ('arm_r',          '100',  'Promien otworu pomiarowego - moment = sila x 0.1 m'),
    ('arm_r_mid',      '50',   'Drugi otwor - podwaja sile przy tym samym momencie'),
    ('load_hole_d',    '6',    'Otwory pomiarowe pod hak / linke'),
    ('web_t',          '10',   'Grubosc srodnika = WYSOKOSC DRUKU'),
    ('web_h_root',     '28',   'Wysokosc srodnika u nasady'),
    ('web_h_tip',      '14',   'Wysokosc srodnika na koncu'),
    ('web_root_x',     '13',   'Do tego X srodnik ma stala wysokosc (lico piasty)'),

    # --- zacisk ---
    ('ear_x',          '22',   'Ucho zacisku siega do x = -ear_x'),
    ('ear_x_in',       '6',    'Ucho zaczyna sie przy x = -ear_x_in (wnika w piaste)'),
    ('ear_w',          '20',   'Szerokosc ucha w Y'),
    ('slit_w',         '2',    'Szczelina zacisku'),
    ('bolt_x',         '-15',  'Os sruby zaciskowej'),
    ('bolt_d',         '4.5',  'Otwor przelotowy pod M4'),
    ('grub_d',         '3.4',  'Otwor pod wkret dociskowy M4 - REZERWA, patrz README'),
    ('grub_z',         '16',   'Wysokosc wkreta dociskowego'),

    # --- odciazenie ---
    # Odciazenia sa PODLUZNE, a otwory pomiarowe okragle. To nie estetyka:
    # piec okraglych dziur w rzedzie znaczylo, ze mozna powiesic hak na zlej
    # i pomylic sie o czynnik dwa, nie zauwazajac tego.
    ('light1_x',       '32',   'Odciazenie 1 - srodek'),
    ('light1_d',       '12',   'Odciazenie 1 - szerokosc'),
    ('light1_len',     '6',    'Odciazenie 1 - dlugosc czesci prostej'),
    ('light2_x',       '66',   'Odciazenie 2 - srodek'),
    ('light2_d',       '10',   'Odciazenie 2 - szerokosc'),
    ('light2_len',     '6',    'Odciazenie 2 - dlugosc czesci prostej'),
    ('light3_x',       '88',   'Odciazenie 3 - srodek'),
    ('light3_d',       '8',    'Odciazenie 3 - szerokosc'),
    ('light3_len',     '3',    'Odciazenie 3 - dlugosc czesci prostej'),

    # --- pierscien probny ---
    ('ring_h',         '6',    'Wysokosc pierscienia probnego'),
    ('ring_y',         '60',   'Odsuniecie pierscienia probnego od czesci glownej'),
]


# ----------------------------------------------------------------------------
# Helpery
# ----------------------------------------------------------------------------
def _mm(expr):
    if isinstance(expr, (int, float)):
        return float(expr)
    return float(eval(expr, {'__builtins__': {}}, V))


def _cm(expr):
    """Fusion API pracuje wewnetrznie w cm."""
    return _mm(expr) / 10.0


def _vi(expr):
    return adsk.core.ValueInput.createByString(str(expr))


def _pt(x, y):
    return adsk.core.Point3D.create(_cm(x), _cm(y), 0)


def _pt_world(sk, x, y, z):
    """Punkt szkicu zadany we wspolrzednych GLOBALNYCH.

    Plaszczyzna XZ ma lokalna os Y skierowana wzdluz globalnego -Z. Wpisanie
    do niej wprost (x, z) posylalo otwor sruby na z = -11 zamiast +11, czyli
    pod czesc - ciecie przechodzilo przez powietrze i model wygladal na
    poprawny az do ogledzin. modelToSketchSpace odwraca to przeliczenie sam,
    wiec konwencja plaszczyzny przestaje miec znaczenie.
    """
    return sk.modelToSketchSpace(
        adsk.core.Point3D.create(_cm(x), _cm(y), _cm(z)))


def _slot(sk, cx, length, dia):
    """Zamkniety profil szczeliny: dwie proste i dwa polokregi na koncach.

    Ten sam wzorzec co zakonczenie srodnika - luk przez trzy punkty. Fusion
    nie ma szczeliny jako prymitywu szkicu, a trymowanie przez API jest
    duzo bardziej zawodne niz narysowanie konturu wprost.
    """
    hl, r = _mm(length) / 2.0, _mm(dia) / 2.0
    x0, x1 = _mm(cx) - hl, _mm(cx) + hl
    ln = sk.sketchCurves.sketchLines
    a = sk.sketchCurves.sketchArcs
    p1, p2 = _pt(x0, r), _pt(x1, r)
    p3, p4 = _pt(x1, -r), _pt(x0, -r)
    ln.addByTwoPoints(p1, p2)
    a.addByThreePoints(p2, _pt(x1 + r, 0), p3)
    ln.addByTwoPoints(p3, p4)
    a.addByThreePoints(p4, _pt(x0 - r, 0), p1)


def _add_params():
    for name, expr, comment in PARAMS:
        V[name] = _mm(expr)
        existing = _des.userParameters.itemByName(name)
        if existing:
            existing.expression = expr
            existing.comment = comment
        else:
            _des.userParameters.add(name, _vi(expr), 'mm', comment)


def _all_profiles(sk):
    col = adsk.core.ObjectCollection.create()
    for i in range(sk.profiles.count):
        col.add(sk.profiles.item(i))
    return col


def _extrude(comp, profiles, name, height, z0='0'):
    feats = comp.features.extrudeFeatures
    ei = feats.createInput(profiles, adsk.fusion.FeatureOperations.NewBodyFeatureOperation)
    ei.setDistanceExtent(False, _vi(height))
    if str(z0) != '0':
        ei.startExtent = adsk.fusion.OffsetStartDefinition.create(_vi(z0))
    feat = feats.add(ei)
    body = feat.bodies.item(0)
    body.name = name
    return body


def _cut(comp, profiles, body_name, label=''):
    """Wycina przelotowo, symetrycznie wzgledem plaszczyzny szkicu.

    Symetryczny przelot jest jedynym wariantem, ktory nie zalezy od tego,
    w ktora strone patrzy normalna plaszczyzny. Przy wycinaniu w bok
    (sruba, wkret) zgadywanie kierunku konczy sie otworem w powietrzu.

    Bryla jest szukana PO NAZWIE przy kazdym cieciu z dwoch powodow:
    participantBodies przyjmuje zwykla liste Pythona, a nie ObjectCollection
    (ObjectCollection leci TypeError w warstwie SWIG), i uchwyt do bryly
    z przed poprzedniej operacji potrafi byc juz niewazny.
    """
    body = comp.bRepBodies.itemByName(body_name)
    before = body.volume

    feats = comp.features.extrudeFeatures
    ei = feats.createInput(profiles, adsk.fusion.FeatureOperations.CutFeatureOperation)
    ei.setSymmetricExtent(_vi('200 mm'), True)
    ei.participantBodies = [body]
    feat = feats.add(ei)

    # Ciecie, ktore nic nie usunelo, wyglada w drzewie identycznie jak udane.
    # Tak wlasnie przeszly niezauwazone otwory sruby i wkreta, kiedy szkic na
    # plaszczyznie XZ wyladowal pod czescia. Objetosc jest jedynym swiadkiem.
    after = comp.bRepBodies.itemByName(body_name).volume
    if after >= before - 1e-6:
        _warn.append('Ciecie "%s" nie usunelo materialu - profil minal bryle.'
                     % (label or body_name))
    return feat


def _join(comp, target, tools):
    combines = comp.features.combineFeatures
    col = adsk.core.ObjectCollection.create()
    for b in tools:
        col.add(b)
    ci = combines.createInput(target, col)
    ci.operation = adsk.fusion.FeatureOperations.JoinFeatureOperation
    return combines.add(ci)


# ----------------------------------------------------------------------------
# Budowa
# ----------------------------------------------------------------------------
def build_solid(comp):
    """Trzy bryly zlaczone w jedna: piasta, ucho zacisku, srodnik."""
    xy = comp.xYConstructionPlane

    # --- piasta ---
    sk = comp.sketches.add(xy)
    sk.name = 'piasta_sk'
    sk.sketchCurves.sketchCircles.addByCenterRadius(_pt(0, 0), _cm('hub_d') / 2.0)
    hub = _extrude(comp, sk.profiles.item(0), 'piasta', 'hub_h')

    # --- ucho zacisku ---
    sk = comp.sketches.add(xy)
    sk.name = 'ucho_sk'
    sk.sketchCurves.sketchLines.addTwoPointRectangle(
        _pt('-ear_x', '-ear_w / 2'), _pt('-ear_x_in', 'ear_w / 2'))
    ear = _extrude(comp, sk.profiles.item(0), 'ucho', 'hub_h')

    # --- srodnik: trapez ze scietym, zaokraglonym koncem ---
    sk = comp.sketches.add(xy)
    sk.name = 'srodnik_sk'
    ln = sk.sketchCurves.sketchLines
    p1 = _pt(0, 'web_h_root / 2')
    p2 = _pt('web_root_x', 'web_h_root / 2')
    p3 = _pt('arm_r', 'web_h_tip / 2')
    p4 = _pt('arm_r', '-web_h_tip / 2')
    p5 = _pt('web_root_x', '-web_h_root / 2')
    p6 = _pt(0, '-web_h_root / 2')
    ln.addByTwoPoints(p1, p2)
    ln.addByTwoPoints(p2, p3)
    # koniec to polokrag o srodku dokladnie w otworze pomiarowym - dzieki temu
    # material wokol otworu ma wszedzie te sama grubosc
    sk.sketchCurves.sketchArcs.addByThreePoints(
        p3, _pt('arm_r + web_h_tip / 2', 0), p4)
    ln.addByTwoPoints(p4, p5)
    ln.addByTwoPoints(p5, p6)
    ln.addByTwoPoints(p6, p1)
    web = _extrude(comp, _all_profiles(sk), 'srodnik', 'web_t')

    _join(comp, hub, [ear, web])
    hub.name = 'dzwignia'
    return hub


def build_cuts(comp, body_name):
    xy = comp.xYConstructionPlane
    xz = comp.xZConstructionPlane

    # --- otwor piasty ---
    sk = comp.sketches.add(xy)
    sk.name = 'otwor_piasty_sk'
    sk.sketchCurves.sketchCircles.addByCenterRadius(_pt(0, 0), _cm('bore_d') / 2.0)
    _cut(comp, sk.profiles.item(0), body_name, 'otwor piasty')

    # --- szczelina zacisku: laczy otwor z zewnetrzem, inaczej nic nie sciska ---
    sk = comp.sketches.add(xy)
    sk.name = 'szczelina_sk'
    sk.sketchCurves.sketchLines.addTwoPointRectangle(
        _pt('-ear_x - 1', '-slit_w / 2'), _pt(0, 'slit_w / 2'))
    _cut(comp, sk.profiles.item(0), body_name, 'szczelina zacisku')

    # --- otwory POMIAROWE: jedyne okragle w srodniku ---
    sk = comp.sketches.add(xy)
    sk.name = 'otwory_pomiarowe_sk'
    circ = sk.sketchCurves.sketchCircles
    circ.addByCenterRadius(_pt('arm_r', 0), _cm('load_hole_d') / 2.0)
    circ.addByCenterRadius(_pt('arm_r_mid', 0), _cm('load_hole_d') / 2.0)
    _cut(comp, _all_profiles(sk), body_name, 'otwory pomiarowe')

    # --- odciazenia: podluzne, zeby nie dalo sie ich pomylic z pomiarowymi ---
    sk = comp.sketches.add(xy)
    sk.name = 'odciazenia_sk'
    _slot(sk, 'light1_x', 'light1_len', 'light1_d')
    _slot(sk, 'light2_x', 'light2_len', 'light2_d')
    _slot(sk, 'light3_x', 'light3_len', 'light3_d')
    _cut(comp, _all_profiles(sk), body_name, 'odciazenia')

    # --- sruba zaciskowa i wkret dociskowy (osie wzdluz Y) ---
    sk = comp.sketches.add(xz)
    sk.name = 'sruby_sk'
    circ = sk.sketchCurves.sketchCircles
    circ.addByCenterRadius(
        _pt_world(sk, 'bolt_x', 0, 'hub_h / 2'), _cm('bolt_d') / 2.0)
    circ.addByCenterRadius(
        _pt_world(sk, 0, 0, 'grub_z'), _cm('grub_d') / 2.0)
    _cut(comp, _all_profiles(sk), body_name, 'sruba i wkret')


def build_test_ring(comp):
    """Plaster piasty z uchem i szczelina - do sprawdzenia pasowania otworu."""
    xy = comp.xYConstructionPlane
    y = V['ring_y']

    sk = comp.sketches.add(xy)
    sk.name = 'pierscien_sk'
    sk.sketchCurves.sketchCircles.addByCenterRadius(_pt(0, y), _cm('hub_d') / 2.0)
    ring = _extrude(comp, sk.profiles.item(0), 'pierscien_probny', 'ring_h')

    sk = comp.sketches.add(xy)
    sk.name = 'pierscien_ucho_sk'
    sk.sketchCurves.sketchLines.addTwoPointRectangle(
        _pt('-ear_x', y - V['ear_w'] / 2.0), _pt('-ear_x_in', y + V['ear_w'] / 2.0))
    ear = _extrude(comp, sk.profiles.item(0), 'pierscien_ucho', 'ring_h')
    _join(comp, ring, [ear])
    ring.name = 'pierscien_probny'
    body_name = 'pierscien_probny'

    sk = comp.sketches.add(xy)
    sk.name = 'pierscien_otwor_sk'
    sk.sketchCurves.sketchCircles.addByCenterRadius(_pt(0, y), _cm('bore_d') / 2.0)
    _cut(comp, sk.profiles.item(0), body_name, 'pierscien: otwor')

    sk = comp.sketches.add(xy)
    sk.name = 'pierscien_szczelina_sk'
    sk.sketchCurves.sketchLines.addTwoPointRectangle(
        _pt('-ear_x - 1', y - V['slit_w'] / 2.0), _pt(0, y + V['slit_w'] / 2.0))
    _cut(comp, sk.profiles.item(0), body_name, 'pierscien: szczelina')

    sk = comp.sketches.add(comp.xZConstructionPlane)
    sk.name = 'pierscien_sruba_sk'
    sk.sketchCurves.sketchCircles.addByCenterRadius(
        _pt_world(sk, 'bolt_x', 0, 'ring_h / 2'), _cm('bolt_d') / 2.0)
    _cut(comp, sk.profiles.item(0), body_name, 'pierscien: sruba')
    return ring


def check_layout():
    """Kontrole, ktore latwo przeoczyc przy zmianie parametru."""
    wall = (V['hub_d'] - V['bore_d']) / 2.0
    if wall < 6.0:
        _warn.append('Sciana piasty {:.1f} mm - zacisk bedzie miekki,'
                     ' podnies hub_d.'.format(wall))
    out = V['ear_x'] - abs(V['bolt_x']) - V['bolt_d'] / 2.0
    if out < 3.0:
        _warn.append('Tylko {:.1f} mm materialu za sruba zaciskowa -'
                     ' ucho pekniete przy dokreceniu.'.format(out))
    if abs(V['bolt_x']) - V['bolt_d'] / 2.0 < V['bore_d'] / 2.0:
        _warn.append('Sruba zaciskowa wchodzi w otwor walka.')
    # otwory w srodniku nie moga zachodzic na siebie ani wyjsc poza obrys
    # (srodek, szerokosc, dlugosc calkowita)
    holes = [(V['arm_r'], V['load_hole_d'], V['load_hole_d']),
             (V['arm_r_mid'], V['load_hole_d'], V['load_hole_d']),
             (V['light1_x'], V['light1_d'], V['light1_d'] + V['light1_len']),
             (V['light2_x'], V['light2_d'], V['light2_d'] + V['light2_len']),
             (V['light3_x'], V['light3_d'], V['light3_d'] + V['light3_len'])]
    holes.sort()
    for (x1, _, l1), (x2, _, l2) in zip(holes, holes[1:]):
        if x2 - x1 < (l1 + l2) / 2.0 + 2.0:
            _warn.append('Otwory {:.0f} i {:.0f} mm stykaja sie.'.format(x1, x2))
    for x, d, _l in holes:
        f = min(max((x - V['web_root_x']) / (V['arm_r'] - V['web_root_x']), 0.0), 1.0)
        h = V['web_h_root'] + (V['web_h_tip'] - V['web_h_root']) * f
        if h / 2.0 - d / 2.0 < 3.0:
            _warn.append('Otwor na x={:.0f} zostawia {:.1f} mm scianki.'
                         .format(x, h / 2.0 - d / 2.0))
    if V['grub_z'] - V['grub_d'] / 2.0 < V['web_t']:
        _warn.append('Wkret dociskowy trafia w srodnik - podnies grub_z.')


def setup():
    global _app, _ui, _des, _root
    _app = adsk.core.Application.get()
    _ui = _app.userInterface
    _des = adsk.fusion.Design.cast(_app.activeProduct)
    if not _des:
        raise RuntimeError('Otworz dokument Fusion Design przed uruchomieniem.')
    try:
        _des.fusionUnitsManager.distanceDisplayUnits = \
            adsk.fusion.DistanceUnits.MillimeterDistanceUnits
    except:
        _warn.append('Nie udalo sie ustawic mm - sprawdz Document Settings.')
    _root = _des.rootComponent
    try:
        _root.name = 'Test_Lever_NEMA23'
    except:
        _warn.append('Nazwa roota ustawi sie po zapisaniu dokumentu.')
    _add_params()


def report():
    check_layout()
    try:
        _app.activeViewport.fit()
    except:
        pass
    f_tip = 1.2 / (V['arm_r'] / 1000.0)
    msg = ('Dzwignia pomiarowa gotowa.\n\n'
           'Promien roboczy {:.0f} mm  ->  1.2 N*m = {:.1f} N = {:.2f} kg\n'
           'Drugi otwor {:.0f} mm     ->  1.2 N*m = {:.1f} N = {:.2f} kg\n'
           'Gabaryt {:.0f} x {:.0f} x {:.0f} mm, wysokosc druku {:.0f} mm.\n\n'
           'DRUKOWAC W TEJ ORIENTACJI - os otworu piasty pionowo.\n'
           'Pod leb sruby M4 KONIECZNIE podkladka: bez niej zacisk slizga sie\n'
           'na walku (zapas 0.9x zamiast 2.1x).\n'
           .format(V['arm_r'], f_tip, f_tip / 9.81,
                   V['arm_r_mid'], f_tip * 2, f_tip * 2 / 9.81,
                   V['arm_r'] + V['web_h_tip'] / 2 + V['ear_x'],
                   V['web_h_root'], V['hub_h'], V['hub_h']))
    if _warn:
        msg += '\nDO SPRAWDZENIA ({}):\n- '.format(len(_warn)) + '\n- '.join(_warn)
    else:
        msg += '\nKontrola layoutu bez zastrzezen.'
    return msg


def run(context):
    global _ui
    _ui = None
    try:
        setup()
        body = build_solid(_root)
        build_cuts(_root, body.name)
        if MAKE_TEST_RING:
            build_test_ring(_root)
        msg = report()
        print(msg)
        if SHOW_MESSAGE_BOX:
            _ui.messageBox(msg, 'Test_Lever_NEMA23')
    except:
        err = 'Blad podczas budowy dzwigni:\n{}'.format(traceback.format_exc())
        print(err)
        if _ui and SHOW_MESSAGE_BOX:
            _ui.messageBox(err, 'Test_Lever_NEMA23')
