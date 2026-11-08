"""Build the Instagram scene in Fusion from viz/mesh/manifest.json.

The meshes come from the OpenSCAD model through viz/export.py. Never fix
geometry here - the next export overwrites it (viz/PLAN_FUSION.md).

Resumable: each run imports parts for ~15 s and returns, because the bridge
gives up after 30 s. Run it again until it prints DONE:

    python viz/tools/bridge_exec.py viz/Mobile_Manipulator_Scene/Mobile_Manipulator_Scene.py

Then the joints: python viz/tools/bridge_exec.py viz/tools/joints.py - a
rebuilt part loses its joints with its old component.

It never saves the document - saving pushes it to Autodesk's cloud, and that
is the owner's call.
"""
import json
import os
import time

import adsk.core
import adsk.fusion

ATTR_GROUP, ATTR_NAME = "mm_viz", "scene"
BUDGET_S = 15
# Parts whose geometry changed: deleted first, then re-imported by the normal
# pass. bridge_exec.py ... REBUILD='["kolumna_rama"]'. Once the owner has
# animated the scene, ask before using it - it breaks his keyframes.
REBUILD = []

# What moves as one (viz/tools/joints.py joints these): root -> assembly ->
# part. Everything else stands on the chassis: root -> CHASSIS -> story group
# -> part. Moving parts go straight under their assembly - a second
# "4 Kolumna" inside "Wózek Z" would clash, Fusion component names are unique.
CHASSIS = "Podwozie"
MOVING = {
    "Wózek Z": ["kolumna_wozki", "kolumna_plyta_ruchoma", "kolumna_wspornik_nakretki",
                "kolumna_nakretka", "kolumna_plyta_ramienia", "ramie_wspornik_katownik",
                "ramie_wspornik_zebra", "ramie_base_link", "ramie_shoulder", "ramie_upper_arm",
                "ramie_elbow", "ramie_lower_arm", "ramie_wrist", "ramie_gripper"],
    "Koła": ["kola_opony", "kola_piasty"],
}


def scene_design(app):
    """The open scene document, or a new Direct-modelling one."""
    for doc in app.documents:
        d = adsk.fusion.Design.cast(doc.products.itemByProductType("DesignProductType"))
        if d and d.attributes.itemByName(ATTR_GROUP, ATTR_NAME):
            if app.activeDocument != doc:
                doc.activate()
            return d
    app.documents.add(adsk.core.DocumentTypes.FusionDesignDocumentType)
    d = adsk.fusion.Design.cast(app.activeProduct)
    # parametric designs want a base feature around every mesh import
    d.designType = adsk.fusion.DesignTypes.DirectDesignType
    d.attributes.add(ATTR_GROUP, ATTR_NAME, "v1")
    return d


def find_occ(parent, name):
    for i in range(parent.occurrences.count):
        occ = parent.occurrences.item(i)
        if occ.component.name == name:
            return occ
    return None


def child(parent, name):
    occ = find_occ(parent, name)
    if occ is None:
        occ = parent.occurrences.addNewComponent(adsk.core.Matrix3D.create())
        occ.component.name = name
    return occ.component


def holder(root, p):
    """The component a part lives in."""
    for name, parts in MOVING.items():
        if p["name"] in parts:
            return child(root, name)
    return child(child(root, CHASSIS), p["group"])


def find_look(app, design, look_id):
    look = design.appearances.itemById(look_id)
    if look:
        return look
    for i in range(app.materialLibraries.count):
        look = app.materialLibraries.item(i).appearances.itemById(look_id)
        if look:
            return look
    raise RuntimeError(f"no appearance {look_id} in any library")


def part_bodies(comp):
    """Mesh bodies of a part: in the part itself, or one per body sub-component."""
    bodies = [comp.meshBodies.item(i) for i in range(comp.meshBodies.count)]
    for i in range(comp.occurrences.count):
        sub = comp.occurrences.item(i).component
        bodies += [sub.meshBodies.item(k) for k in range(sub.meshBodies.count)]
    return bodies


def style(body, look):
    """Show the appearance. An imported mesh is drawn in pastel face-group
    colours with every triangle edged - that hid the materials until
    2026-09-25 (it is not component colour cycling; Shift+N does nothing)."""
    if body.appearance is None or body.appearance.id != look.id:
        body.appearance = look
    body.displayOverrides.isSuppressFaceGroupColors = True
    body.displayOverrides.isSuppressTriangleEdges = True


def run(_):
    app = adsk.core.Application.get()
    mesh_dir = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                             "..", "mesh"))
    with open(os.path.join(mesh_dir, "manifest.json"), encoding="utf-8") as f:
        parts = json.load(f)["parts"]
    design = scene_design(app)
    root = design.rootComponent
    unknown = set(REBUILD) - {p["name"] for p in parts}
    if unknown:
        raise RuntimeError(f"REBUILD names not in the manifest: {sorted(unknown)}")
    for p in parts:
        if p["name"] in REBUILD:
            occ = find_occ(holder(root, p), p["name"])
            if occ:
                occ.deleteMe()
                print(f"  do przebudowy: {p['name']}")
    t0 = time.time()
    done = 0
    for p in parts:
        group = holder(root, p)
        occ = find_occ(group, p["name"])
        if not p["scene"]:
            # exported only for the silhouette check; the real column replaces it
            if occ:
                occ.deleteMe()
                print(f"  usunieto proxy {p['name']}")
            done += 1
            continue
        look = find_look(app, design, p["appearance"])
        if occ:
            # already built: bring appearance and display in line with the
            # manifest, so a material change needs no re-import
            for b in part_bodies(occ.component):
                style(b, look)
            done += 1
            continue
        if time.time() - t0 > BUDGET_S:
            break
        comp = child(group, p["name"])
        try:
            files = p["bodies"]
            for i, fn in enumerate(files, 1):
                target = child(comp, f"{p['name']} {i}") if len(files) > 1 else comp
                bodies = target.meshBodies.add(os.path.join(mesh_dir, fn),
                                               adsk.fusion.MeshUnits.MillimeterMeshUnit)
                for k in range(bodies.count):
                    style(bodies.item(k), look)
        except Exception:
            # no half-built part left behind - the next run would skip it as done
            find_occ(group, p["name"]).deleteMe()
            raise
        done += 1
        print(f"  {p['group']} / {p['name']}: {len(files)} bryl, {time.time() - t0:.1f} s")
    if done == len(parts):
        app.activeViewport.fit()
        print(f"DONE {done}/{len(parts)}")
    else:
        print(f"{done}/{len(parts)} - uruchom ponownie")
