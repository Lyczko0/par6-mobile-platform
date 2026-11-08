"""Joints of the Fusion scene - through bridge_exec.py, after the scene script
prints DONE, and again after every REBUILD (a rebuilt part takes its joints
with it). The scene must be assembled (explode.py FACTOR=0):

    python viz/tools/bridge_exec.py viz/tools/joints.py

  Jazda   Podwozie on the root origin, slider X, 0..DRIVE_MM
  Oś Z    Wózek Z on Podwozie, slider Z, 0..z_travel (manifest)
  Koła    both wheels on Podwozie about their common axle (from the tyre
          meshes), motion-linked to Jazda: one turn per circumference
  J1..J6  PAR6 links, axes from the manifest - viz/export.py takes them from
          the OpenSCAD chain that placed the meshes. No limits: the arm's are
          not measured.

Then drives each joint, checks that the right things moved the right way and
puts everything back. Deletes and rebuilds only its own joints and
construction geometry; never saves the document.
"""
import json
import math
import os

import adsk.core
import adsk.fusion

CHASSIS, CARRIAGE, WHEELS = "Podwozie", "Wózek Z", "Koła"
DRIVE_MM = 1000
TAG = "kin "            # prefix of the construction points / axes made here
LINK = "Jazda -> Koła"


def mm_point(p):
    return adsk.core.Point3D.create(*(v / 10 for v in p))


def centre(o):
    """World centre of a part's mesh, mm. Not o.boundingBox: that also takes
    in the joint points left in the part, and the component origin."""
    b = o.component.meshBodies.item(0).createForAssemblyContext(o).boundingBox
    return [(getattr(b.minPoint, a) + getattr(b.maxPoint, a)) * 5 for a in "xyz"]


def is_identity(m):
    return max(abs(a - b) for a, b in zip(m.asArray(), adsk.core.Matrix3D.create().asArray())) < 1e-6


def run(_):
    app = adsk.core.Application.get()
    design = adsk.fusion.Design.cast(app.activeProduct)
    root = design.rootComponent
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(here, "mesh", "manifest.json"), encoding="utf-8") as f:
        kin = json.load(f)["kinematics"]
    occ = {o.component.name: o for o in root.allOccurrences}
    arm = kin["arm"]
    missing = {CHASSIS, CARRIAGE, WHEELS, arm[0]["parent"]} | {j["link"] for j in arm}
    missing -= set(occ)
    if missing:
        raise RuntimeError(f"brak w scenie: {sorted(missing)} - zbuduj scene od nowa")

    ours = {"Jazda", "Oś Z", "Koła", LINK} | {j["name"] for j in arm}
    # a joint lives in the lowest component holding both parts - the arm's
    # in "Wózek Z", not in the root
    for comp in design.allComponents:
        for coll in (comp.motionLinks, comp.joints, comp.constructionAxes, comp.constructionPoints):
            for i in reversed(range(coll.count)):
                if coll.item(i).name in ours or coll.item(i).name.startswith(TAG):
                    coll.item(i).deleteMe()
    moved = [o.name for o in root.allOccurrences if not is_identity(o.transform2)]
    if moved:
        raise RuntimeError(f"scena nie zlozona ({len(moved)} czesci) - najpierw explode.py FACTOR=0")

    # Fusion grounds only the FIRST occurrence it makes in a component; the
    # rest stay put when their parent moves - the arm and the ribs stayed down
    # while the carriage rose (2026-10-07). Everything rides its parent except
    # the three assemblies and the arm links past the base: joints move those.
    free = {CHASSIS, CARRIAGE, WHEELS} | {j["link"] for j in arm}
    for o in root.allOccurrences:
        o.isGroundToParent = o.component.name not in free

    def hidden(e, name):
        e.name = TAG + name
        e.isLightBulbOn = False
        return e

    def point_in(o, name, p):
        # component coordinates are the model's: every occurrence is built at
        # identity, and the check above says it still is
        pi = o.component.constructionPoints.createInput()
        pi.setByPoint(mm_point(p))
        pt = hidden(o.component.constructionPoints.add(pi), name)
        return adsk.fusion.JointGeometry.createByPoint(pt.createForAssemblyContext(o))

    # As-built joints need one point only, but Fusion allows them only in a
    # parametric design, and the scene is direct (mesh imports). A plain joint
    # takes a point in each part, both on the same spot - nothing moves.
    def joint(name, moving, fixed, p, d, slide=False):
        # the axis has to belong to one of the two parts - the fixed one
        comp = occ[fixed].component
        ai = comp.constructionAxes.createInput()
        ai.setByLine(adsk.core.InfiniteLine3D.create(mm_point(p), adsk.core.Vector3D.create(*d)))
        ax = hidden(comp.constructionAxes.add(ai), name).createForAssemblyContext(occ[fixed])
        inp = root.joints.createInput(point_in(occ[moving], name, p), point_in(occ[fixed], name, p))
        custom = adsk.fusion.JointDirections.CustomJointDirection
        if slide:
            inp.setAsSliderJointMotion(custom, ax)
        else:
            inp.setAsRevoluteJointMotion(custom, ax)
        j = root.joints.add(inp)
        j.name = name
        return j

    def slide_limits(j, hi_mm):
        lim = j.jointMotion.slideLimits
        lim.isMinimumValueEnabled, lim.minimumValue = True, 0
        lim.isMaximumValueEnabled, lim.maximumValue = True, hi_mm / 10

    # Jazda: the chassis origin on the ground origin, free along X only
    here_pt = occ[CHASSIS].component.originConstructionPoint.createForAssemblyContext(occ[CHASSIS])
    inp = root.joints.createInput(adsk.fusion.JointGeometry.createByPoint(here_pt),
                                  adsk.fusion.JointGeometry.createByPoint(root.originConstructionPoint))
    inp.setAsSliderJointMotion(adsk.fusion.JointDirections.XAxisJointDirection)
    drive = root.joints.add(inp)
    drive.name = "Jazda"
    slide_limits(drive, DRIVE_MM)

    plate = "kolumna_plyta_ruchoma"
    lift = joint("Oś Z", CARRIAGE, CHASSIS, centre(occ[plate]), [0, 0, 1], slide=True)
    slide_limits(lift, kin["z_travel"])

    tyres = [o for o in root.allOccurrences
             if o.component.name.startswith("kola_opony") and o.component.meshBodies.count]
    if len(tyres) != 2:
        raise RuntimeError(f"{len(tyres)} opon zamiast 2")
    a, b = (centre(t) for t in tyres)
    axle = [b[i] - a[i] for i in range(3)]
    span = math.sqrt(sum(v * v for v in axle))
    tb = tyres[0].component.meshBodies.item(0).createForAssemblyContext(tyres[0]).boundingBox
    d_mm = (tb.maxPoint.z - tb.minPoint.z) * 10
    wheels = joint("Koła", WHEELS, CHASSIS, [(a[i] + b[i]) / 2 for i in range(3)],
                   [v / span for v in axle])

    arm_joints = [joint(j["name"], j["link"], j["parent"], j["origin"], j["axis"]) for j in arm]

    li = root.motionLinks.createInput(drive, wheels)
    li.valueOne = adsk.core.ValueInput.createByString(f"{DRIVE_MM} mm")
    li.valueTwo = adsk.core.ValueInput.createByString(f"{360 * DRIVE_MM / (math.pi * d_mm):.4f} deg")
    link = root.motionLinks.add(li)
    link.name = LINK

    # ---- drive each one and look -------------------------------------------
    probe = {"rama": "rama_belki 1", "wozek": plate, "chwytak": "ramie_gripper",
             "podstawa": arm[0]["parent"]}
    home = {k: centre(occ[n]) for k, n in probe.items()}
    report = []

    def moved_by():
        return {k: [round(v - w, 1) for v, w in zip(centre(occ[n]), home[k])]
                for k, n in probe.items()}

    def verdict(label, ok, s, extra=""):
        report.append(f"{label}: " + ", ".join(f"{k} {v}" for k, v in s.items()) + extra
                      + f" -> {'OK' if ok else 'ZLE'}")

    zt = kin["z_travel"]
    lift.jointMotion.slideValue = zt / 10
    s = moved_by()
    verdict(f"Oś Z {zt:.0f} mm", s["rama"] == [0, 0, 0]
            and all(abs(s[k][2] - zt) < 0.5 for k in ("wozek", "chwytak", "podstawa")), s)
    lift.jointMotion.slideValue = 0

    drive.jointMotion.slideValue = 10
    top = occ[WHEELS].transform2.getCell(0, 2)       # X part of where the wheel's +Z went
    if top < 0:                                        # it rolled backwards on a forward move
        link.isReversed = not link.isReversed
        drive.jointMotion.slideValue = 0
        drive.jointMotion.slideValue = 10
        top = occ[WHEELS].transform2.getCell(0, 2)
    s = moved_by()
    turn = math.degrees(wheels.jointMotion.rotationValue)
    want = 360 * 100 / (math.pi * d_mm)
    verdict("Jazda 100 mm", top > 0 and abs(abs(turn) - want) < 0.5
            and all(abs(v[0] - 100) < 0.5 for v in s.values()), s,
            f", kola {abs(turn):.1f} st. (opona {d_mm:.1f} mm -> {want:.1f}), gora kola do przodu")
    drive.jointMotion.slideValue = 0

    arm_joints[0].jointMotion.rotationValue = math.radians(30)
    s = moved_by()
    verdict("J1 30 st.", s["podstawa"] == [0, 0, 0] and max(map(abs, s["chwytak"])) > 10, s)
    arm_joints[0].jointMotion.rotationValue = 0

    back = [o.name for o in root.allOccurrences if not is_identity(o.transform2)]
    report.append("wszystko na miejscu" if not back else f"NIE WROCILO: {back[:5]}")
    print("\n".join(report))
