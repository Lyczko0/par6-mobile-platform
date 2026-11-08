"""Save the Fusion viewport to viz/shots/<NAME>.png - run through bridge_exec.py:

    python viz/tools/bridge_exec.py viz/tools/shot.py NAME='"bez_oslon"' HIDE='["1 Osłony"]'

Like every viewport image call it waits while a Fusion dialog is open - see
bridge_exec.py (the add-in's /screenshot was wrongly blamed for that).

The viewport goes to plain shaded. The pastel face-group colours that hid the
appearances are switched off per body by the scene script, not here. HIDE
lists groups or parts (any level) hidden for the shot and shown again after.
"""
import os

import adsk.core
import adsk.fusion

NAME = "iso"
VIEW = "home"          # "home" (Fusion's iso) | "current"
HIDE = []
SIZE = (1600, 1000)


def run(_):
    app = adsk.core.Application.get()
    root = adsk.fusion.Design.cast(app.activeProduct).rootComponent
    vp = app.activeViewport
    vp.visualStyle = adsk.core.VisualStyles.ShadedVisualStyle
    hidden = [o for o in root.allOccurrences if o.component.name in HIDE and o.isLightBulbOn]
    missing = set(HIDE) - {o.component.name for o in root.allOccurrences}
    if missing:
        raise RuntimeError(f"no such group: {sorted(missing)}")
    try:
        for o in hidden:
            o.isLightBulbOn = False
        if VIEW == "home":
            vp.goHome()
            vp.fit()
        out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shots")
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, f"{NAME}.png")
        print(path if vp.saveAsImageFile(path, *SIZE) else "saveAsImageFile failed")
    finally:
        for o in hidden:
            o.isLightBulbOn = True
