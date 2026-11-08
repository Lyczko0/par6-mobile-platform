"""Local render of the Fusion scene to viz/renders/<NAME>.png.

    python viz/tools/bridge_exec.py viz/tools/render.py NAME='"hero"'
    python viz/tools/bridge_exec.py viz/tools/render.py NAME='"srodek"' HIDE='["1 Osłony"]'
    python viz/tools/bridge_exec.py viz/tools/render.py STATUS=True

It returns at once; Fusion renders in the background, so poll with
STATUS=True. Groups in HIDE stay hidden while it renders and come back on
the first STATUS call that sees the render finished - so always poll it out.

The camera is a fresh one - the viewport the owner works in is left alone.
startLocalRender refuses a camera with isFitView set, so the distance is
computed here: every corner of the visible bounding box must be in frame.
"""
import math
import os

import adsk.core
import adsk.fusion

NAME = "hero"
EYE = (1.0, -0.85, 0.55)     # eye direction from the target: front-right, above
SIZE = (1080, 1350)          # Instagram portrait, 4:5
FOV = 0.3948                 # rad across the width = a 90 mm lens, Fusion's default
MARGIN = 1.08
QUALITY = 75                 # 25..100; 25 took ~1 min on 2026-09-25
# Environments differ a lot in brightness: at Fusion's default 12 EV the white
# covers came out charcoal in photobooth and Studio6, mid-grey in Studio1
# (2026-09-25). Only the very first render was white - the document's own
# environment, which cannot be read back. So: Studio1, exposure 2 stops down.
ENVIRONMENT = "Studio1"      # render environment id; names are Polish
BACKGROUND = (214, 216, 220) # white covers on near-white read as one blob
EXPOSURE = 10.0              # EV; higher = darker. 12 = Fusion default
HIDE = []
STATUS = False


def vec(*c):
    return adsk.core.Vector3D.create(*c)


def fitted_camera(bb, vp):
    lo, hi = bb.minPoint, bb.maxPoint
    centre = adsk.core.Point3D.create((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
    back = vec(*EYE)                              # target -> eye
    back.normalize()
    fwd = vec(-back.x, -back.y, -back.z)
    right = fwd.crossProduct(vec(0, 0, 1))
    right.normalize()
    up = right.crossProduct(fwd)
    tan_w = math.tan(FOV / 2)
    tan_h = tan_w * SIZE[1] / SIZE[0]
    dist = 0.0
    for x in (lo.x, hi.x):
        for y in (lo.y, hi.y):
            for z in (lo.z, hi.z):
                rel = vec(x - centre.x, y - centre.y, z - centre.z)
                toward = rel.dotProduct(back)
                dist = max(dist, toward + abs(rel.dotProduct(right)) / tan_w,
                           toward + abs(rel.dotProduct(up)) / tan_h)
    dist *= MARGIN
    cam = adsk.core.Camera.create()
    cam.cameraType = adsk.core.CameraTypes.PerspectiveCameraType
    # Fusion puts the angle across the viewport's shorter side and the render
    # keeps the viewport's horizontal field: a 2560x1252 viewport rendered the
    # robot at half size (2026-09-25), the morning's tall viewport did not.
    cam.perspectiveAngle = 2 * math.atan(tan_w * min(vp.width, vp.height) / vp.width)
    cam.target = centre
    cam.eye = adsk.core.Point3D.create(centre.x + back.x * dist, centre.y + back.y * dist,
                                       centre.z + back.z * dist)
    cam.upVector = vec(0, 0, 1)
    return cam


def visible_box(root):
    # the meshes: an occurrence's own box also takes in joint points and axes
    box = None
    for occ in root.allOccurrences:
        if occ.isVisible and occ.component.meshBodies.count:
            b = occ.component.meshBodies.item(0).createForAssemblyContext(occ).boundingBox
            if box is None:
                box = b.copy()
            else:
                box.combine(b)
    return box


def status():
    job = getattr(adsk, "_mm_render", None)
    if job is None:
        print("no render started in this Fusion session")
        return
    future, path, *rest = job
    hidden = rest[0] if rest else []
    states = adsk.fusion.LocalRenderStates
    state = future.renderState
    print("state:", state, "| progress:", round(future.progress, 2),
          "| file:", os.path.exists(path) and os.path.getsize(path))
    if state in (states.FinishedLocalRenderState, states.FailedLocalRenderState):
        for occ in hidden:
            occ.isLightBulbOn = True
        if hidden:
            print("shown again:", [o.component.name for o in hidden])
        adsk._mm_render = None
        print("DONE" if state == states.FinishedLocalRenderState else "FAILED")


def run(_):
    if STATUS:
        status()
        return
    if getattr(adsk, "_mm_render", None) is not None:
        raise RuntimeError("a render is still running - poll STATUS=True first")

    app = adsk.core.Application.get()
    design = adsk.fusion.Design.cast(app.activeProduct)
    root = design.rootComponent
    rm = design.renderManager
    scene = rm.sceneSettings
    env = rm.renderEnvironments.itemById(ENVIRONMENT)
    if env is None:
        raise RuntimeError(f"no render environment {ENVIRONMENT}")
    # backgroundType is read-only; setting the environment or the colour is
    # what switches it. Environment first (it lights the scene), colour after.
    scene.backgroundEnvironment = env
    scene.backgroundSolidColor = adsk.core.Color.create(*BACKGROUND, 255)
    scene.cameraExposure = EXPOSURE

    r = rm.rendering
    r.aspectRatio = adsk.fusion.RenderAspectRatios.CustomRenderAspectRatio
    r.resolution = adsk.fusion.RenderResolutions.CustomRenderResolution
    r.resolutionWidth, r.resolutionHeight = SIZE
    r.renderQuality = QUALITY
    r.isBackgroundTransparent = False

    missing = set(HIDE) - {o.component.name for o in root.allOccurrences}
    if missing:
        raise RuntimeError(f"no such group: {sorted(missing)}")
    hidden = [o for o in root.allOccurrences if o.component.name in HIDE and o.isLightBulbOn]
    for occ in hidden:
        occ.isLightBulbOn = False
    try:
        cam = fitted_camera(visible_box(root), app.activeViewport)
        out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                               "renders")
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, f"{NAME}.png")
        if os.path.exists(path):
            os.remove(path)
        future = r.startLocalRender(path, cam)
    except Exception:
        for occ in hidden:
            occ.isLightBulbOn = True
        raise
    adsk._mm_render = (future, path, hidden)
    print("started", NAME, "- poll STATUS=True")
