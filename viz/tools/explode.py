"""Exploded view of the Fusion scene, and back - run through bridge_exec.py:

    python viz/tools/bridge_exec.py viz/tools/explode.py FACTOR=0.6
    python viz/tools/bridge_exec.py viz/tools/explode.py FACTOR=0      # assemble

Every component that holds a mesh moves away from the robot's centre by
FACTOR x its own offset from it. The scene script builds every occurrence
with an identity transform, so FACTOR=0 - which also puts the assemblies
back - is exactly the state after a build, every joint at zero.
Only moves occurrences - never touches geometry, never saves the document.
"""
import adsk.core
import adsk.fusion

FACTOR = 0.6


def centre(o):
    # the mesh, not o.boundingBox - that also takes in joint points (joints.py)
    b = o.component.meshBodies.item(0).createForAssemblyContext(o).boundingBox
    return [(getattr(b.minPoint, a) + getattr(b.maxPoint, a)) / 2 for a in "xyz"]


def run(_):
    app = adsk.core.Application.get()
    root = adsk.fusion.Design.cast(app.activeProduct).rootComponent
    for o in root.allOccurrences:          # assemblies too: a joint may have moved them
        o.transform2 = adsk.core.Matrix3D.create()
    leaves = [o for o in root.allOccurrences if o.component.meshBodies.count]
    if FACTOR == 0:
        print(f"zlozone: {len(leaves)} komponentow")
        return
    centres = [centre(o) for o in leaves]
    mid = [sum(c[i] for c in centres) / len(centres) for i in range(3)]
    for o, c in zip(leaves, centres):
        m = adsk.core.Matrix3D.create()
        m.translation = adsk.core.Vector3D.create(*[FACTOR * (c[i] - mid[i]) for i in range(3)])
        o.transform2 = m
    print(f"rozsuniete x{FACTOR}: {len(leaves)} komponentow")
