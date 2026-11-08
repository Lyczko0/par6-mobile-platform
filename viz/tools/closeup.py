"""Close-up of a few parts, everything else hidden - through bridge_exec.py:

    python viz/tools/bridge_exec.py viz/tools/closeup.py NAME='"uchwyt"' KEEP='["uchwyty_wieszaki"]'

Shows only the parts named in KEEP (manifest names), looks at TARGET (mm,
model coordinates) from EYE_OFFSET, saves viz/shots/<NAME>.png, then turns
every part back on. Never saves the document.
"""
import json
import os

import adsk.core
import adsk.fusion

NAME = "closeup"
KEEP = []
TARGET = [0, 125, 135]          # mm
EYE_OFFSET = [-300, -220, -80]  # mm
EXTENT = 300                    # mm, ortho view width
W, H = 1600, 1000


def run(_):
    app = adsk.core.Application.get()
    root = adsk.fusion.Design.cast(app.activeProduct).rootComponent
    # part level wherever it sits: under "Podwozie" -> story group, or straight
    # under "Wózek Z" / "Koła" (scene script, 2026-10-07)
    with open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "mesh", "manifest.json"), encoding="utf-8") as f:
        names = {p["name"] for p in json.load(f)["parts"]}
    parts = [o for o in root.allOccurrences if o.component.name in names]
    try:
        for p in parts:
            p.isLightBulbOn = p.component.name in KEEP
        vp = app.activeViewport
        cam = vp.camera
        t = [v / 10 for v in TARGET]
        cam.target = adsk.core.Point3D.create(*t)
        cam.eye = adsk.core.Point3D.create(*[t[i] + EYE_OFFSET[i] / 10 for i in range(3)])
        cam.upVector = adsk.core.Vector3D.create(0, 0, 1)
        cam.isFitView = False
        cam.viewExtents = EXTENT / 10
        vp.camera = cam
        out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "shots", f"{NAME}.png")
        vp.saveAsImageFile(out, W, H)
        print(out)
    finally:
        for p in parts:
            p.isLightBulbOn = True
