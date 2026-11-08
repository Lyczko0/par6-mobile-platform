#!/usr/bin/env python3
"""Export the robot for the Fusion scene - from the OpenSCAD model, never drawn
by hand in Fusion (viz/PLAN_FUSION.md, decision 1).

    python viz/export.py               # every part, then the checks
    python viz/export.py kola balast   # only these parts, then the checks
    python viz/export.py --check       # checks only

One OpenSCAD export per part AND per colour (OpenSCAD 2021 drops colours, so a
two-colour module is exported once per colour through `viz_only`), split into
connected bodies -> viz/mesh/<part>__<n>.stl + viz/mesh/manifest.json, which
viz/Mobile_Manipulator_Scene reads.

VISUALISATION ONLY. These meshes are not production files - the no-STL rule
is about parts to be cut, and these must never be sent to one.

Checks, each able to fail:
  * the OpenSCAD log has no ERROR / assert / unknown module or variable - an
    unknown name renders EMPTY and would pass silently;
  * body count per part == pinned count: a changed count means bodies welded
    together or fell apart, and the animation would move the wrong things;
  * silhouette of the scene == silhouette of main_base.scad from two cameras,
    AND it must fail with one visible part dropped (negative control, run
    every time) - otherwise the check is blind.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import trimesh
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MESH = os.path.join(HERE, "mesh")
MAIN = os.path.join(ROOT, "mobile_base", "main_base.scad").replace("\\", "/")
PAR6 = os.path.join(ROOT, "par6_ref", "meshes").replace("\\", "/") + "/"
ZMAIN = os.path.join(ROOT, "z_lift", "main.scad").replace("\\", "/")
OPENSCAD = os.environ.get("OPENSCAD", r"C:\Program Files\OpenSCAD\openscad.exe")

# Appearance ids from Fusion's stock library - looked up by id because the UI
# is Polish and names are localised (project memory fusion-bridge-access).
# What the part is MADE of, not the model's diagnostic colour: OpenSCAD paints
# the anti-tip warning-orange and the carriage blocks green so they stand out;
# the owner wants the real look (2026-09-25).
ALU_SATIN, ALU_BLAST = "Prism-028", "Prism-624"
WHITE_MATTE, WHITE_ABS = "Prism-127", "Prism-374"
BLACK_MATTE, GREY_MATTE = "Prism-113", "Prism-116"
RUBBER, STEEL_RAW, DARK_METAL = "Prism-130", "Prism-084", "Prism-009"
BLUE_GLOSS = "Prism-114"      # battery wrap
STEEL_SATIN, STEEL_POLISHED, BLACK_OXIDE = "Prism-073", "Prism-072", "Prism-626"
BLACK_GLOSS, FR4 = "Prism-089", "Prism-3001"

PAR6_LINKS = ["base_link", "shoulder", "upper_arm", "elbow",
              "lower_arm", "wrist", "gripper"]

# name, scene group, appearance, bodies (None = keep as one mesh), OpenSCAD.
# Flags are plain assignments: they come after the include, so they win.
PARTS = [
    # 2026-10-07: frame, drive mounts, battery cradles, column frame and
    # carriage exported part by part - the owner takes the scene apart in
    # Fusion to look for construction problems, and CGAL welds touching parts
    ("rama_belki", "8 Rama", ALU_SATIN, 2, 'viz_only = "beam"; show_cnc = false; base_frame("A");'),
    ("rama_poprzeczki", "8 Rama", ALU_SATIN, 5, 'viz_only = "cross"; show_cnc = false; base_frame("A");'),
    ("plyty_koncowe", "8 Rama", WHITE_ABS, 2, "end_plate(half_l); end_plate(-half_l);"),
    ("kola_opony", "7 Napęd", RUBBER, 2,
     'viz_only = "tire"; show_casters = false; show_cnc = false; variant_support("A");'),
    ("kola_piasty", "7 Napęd", ALU_SATIN, 2,
     'viz_only = "hub"; show_casters = false; show_cnc = false; variant_support("A");'),
    ("uchwyty_gniazda", "7 Napęd", ALU_BLAST, 2, 'viz_only = "seat"; drive_mount(1); drive_mount(-1);'),
    ("uchwyty_strzemiona", "7 Napęd", STEEL_SATIN, 2, 'viz_only = "strap"; drive_mount(1); drive_mount(-1);'),
    ("uchwyty_wieszaki", "7 Napęd", ALU_BLAST, 2, 'viz_only = "hanger"; drive_mount(1); drive_mount(-1);'),
    # 3 = front omni wheel + rear caster + rear caster mount. The mount floats:
    # 6.8 mm above the caster (2026-09-25) and it reaches no frame member
    # (2026-10-03) - a placeholder until the compliant mounts are designed,
    # BOM_V1.md section 11. The omni has no mount drawn at all, same reason.
    ("castery", "7 Napęd", DARK_METAL, 3, 'show_drive = false; variant_support("A");'),
    ("antitip", "7 Napęd", DARK_METAL, 2, "antitip_side_pair();"),
    ("bateria", "5 Elektronika i pakiet", BLUE_GLOSS, 1, "battery_pack();"),
    ("kolyski_pakietu", "5 Elektronika i pakiet", ALU_BLAST, 2, 'viz_only = "cradle"; battery_cradle();'),
    ("pasy_pakietu", "5 Elektronika i pakiet", BLACK_MATTE, 2, 'viz_only = "batt_strap"; battery_cradle();'),
    ("plyta_elektroniki", "5 Elektronika i pakiet", WHITE_ABS, 1, "electronics_plate();"),
    ("elektronika", "5 Elektronika i pakiet", BLACK_MATTE, 3, "electronics_boxes();"),
    ("balast", "6 Balast", STEEL_RAW, 2, "ballast_bars();"),
    # 1. Was 5 until 2026-10-03: shell + 4 insert bosses floating 4-25 mm off
    # the wall in A, B and both sides. Now M4 tubes through the shell (A, B)
    # and plain holes into side_brackets (sides).
    ("oslona_A_przod", "1 Osłony", WHITE_MATTE, 1, 'viz_only = "white"; cover_A_front();'),
    ("oslona_A_zderzak", "1 Osłony", BLACK_MATTE, 1, 'viz_only = "accent"; cover_A_front();'),
    ("oslona_B_tyl", "1 Osłony", WHITE_MATTE, 1, "cover_B_rear();"),
    ("oslona_bok_lewa", "1 Osłony", WHITE_MATTE, 1, "cover_side(1);"),
    ("oslona_bok_prawa", "1 Osłony", WHITE_MATTE, 1, "cover_side(-1);"),
    # 6 printed brackets under the beams, each its own part. 8 drawn on
    # 2026-10-03 exported as 6: the front pair overlapped by 2 mm.
    ("oslona_wsporniki", "1 Osłony", GREY_MATTE, 6, "side_brackets();"),
    ("oslona_E_listwy", "1 Osłony", BLACK_MATTE, 4, "cover_E_low();"),
    ("oslona_F_nadkola", "1 Osłony", BLACK_MATTE, 2, "cover_F_arch();"),
    ("oslona_G_gora", "1 Osłony", WHITE_MATTE, 1, 'viz_only = "white"; cover_G_top();'),
    ("oslona_G_kolnierze", "1 Osłony", BLACK_MATTE, 2, 'viz_only = "accent"; cover_G_top();'),
    ("oslona_I_elektronika", "1 Osłony", WHITE_MATTE, 1, "cover_I_elec();"),
    # 2 by design: the notches for the G grommets cut the rim on both sides
    ("oslona_J_kolnierz", "1 Osłony", WHITE_MATTE, 2, "cover_J_collar();"),
    # 2 = backbone (profiles, rails, tie plate welded by CGAL) + moving plate,
    # which floats by the height of the carriages the proxy does not draw
    ("kolumna_konstrukcja", "4 Kolumna", ALU_SATIN, 2, "column_structure_proxy(carriage_z);"),
    # 6 = four printed segments + cap + driver box
    ("kolumna_skorupa", "2 Skorupa kolumny", WHITE_MATTE, 6, "column_shell_proxy();"),
    ("ramie_wspornik_katownik", "3 Ramię", ALU_BLAST, 1, 'par6_only = "bracket_angle"; arms_proxy(carriage_z);'),
    ("ramie_wspornik_zebra", "3 Ramię", ALU_BLAST, 2, 'par6_only = "bracket_ribs"; arms_proxy(carriage_z);'),
] + [
    (f"ramie_{n}", "3 Ramię", GREY_MATTE, None, f'par6_only = "{n}"; arms_proxy(carriage_z);')
    for n in PAR6_LINKS
]

# The real column from z_lift. Its own include - z_lift and mobile_base clash
# on variable names - and to_base(), the lift -> base transform of
# z_lift/components.scad (in_chassis). Checked 2026-09-25: rails, profiles and
# moving plate land on the proxy to 0 mm, plate centre at 377 in both.
ZPARTS = [
    # 1 since 2026-09-25: both strain reliefs used to float (3 bodies) - the
    # lower one now sits on the base plate, the upper one is on the chain
    ("kolumna_plyta_bazowa", "4 Kolumna", ALU_SATIN, 1, 'viz_only = "zbase"; frame_group();'),
    ("kolumna_profile", "4 Kolumna", ALU_SATIN, 2, 'viz_only = "zprofile"; frame_group();'),
    ("kolumna_spinka", "4 Kolumna", ALU_SATIN, 1, 'viz_only = "ztie"; frame_group();'),
    ("kolumna_dodatki", "4 Kolumna", DARK_METAL, 2, 'viz_only = "zextras"; frame_group();'),
    ("kolumna_prowadnice", "4 Kolumna", STEEL_SATIN, 2, "rail_group();"),
    ("kolumna_wozki", "4 Kolumna", STEEL_SATIN, 4, "block_group(cz);"),
    ("kolumna_plyta_ruchoma", "4 Kolumna", ALU_BLAST, 1, 'viz_only = "zplate"; carriage_group(cz);'),
    ("kolumna_wspornik_nakretki", "4 Kolumna", ALU_BLAST, 1, 'viz_only = "znuthsg"; carriage_group(cz);'),
    ("kolumna_nakretka", "4 Kolumna", STEEL_POLISHED, 1, 'viz_only = "zballnut"; carriage_group(cz);'),
    # 12 mm plate between the moving plate and the PAR6 bracket; it rode along
    # untagged in every carriage_group() export until 2026-10-07
    ("kolumna_plyta_ramienia", "4 Kolumna", ALU_BLAST, 1, 'viz_only = "zarmif"; carriage_group(cz);'),
    ("kolumna_sruba", "4 Kolumna", STEEL_POLISHED, 1, 'viz_only = "screw"; drive_group();'),
    ("kolumna_sprzeglo", "4 Kolumna", ALU_BLAST, 1, 'viz_only = "coupling"; drive_group();'),
    ("kolumna_silnik", "4 Kolumna", BLACK_GLOSS, 1, 'viz_only = "motor"; drive_group();'),
    ("kolumna_hamulec", "4 Kolumna", BLACK_MATTE, 1, 'viz_only = "brake"; drive_group();'),
    # 2 = each bearing with its bracket. Was 4 until 2026-09-25: the L-bracket
    # had no bend, so its foot met its web on an edge only.
    ("kolumna_lozyska", "4 Kolumna", BLACK_OXIDE, 2, 'viz_only = "bearings"; drive_group();'),
    ("kolumna_sterownik", "4 Kolumna", FR4, 1, 'viz_only = "driver"; drive_group();'),
    # 6 = 4 stop pads + 2 switches. Was 8 until 2026-10-03: the roller
    # levers met their switch on one edge and exported loose.
    ("kolumna_krancowki", "4 Kolumna", DARK_METAL, 6, "safety_group(cz);"),
    # 1. Was 2 until 2026-10-03: the moving anchor stood 27 mm below the
    # bend - the chain could not reach the low limit (assert in parameters).
    ("kolumna_lancuch", "4 Kolumna", BLACK_MATTE, 1, "cable_chain(cz);"),
    # 4 printed segments each, by design
    ("skorupa_bok_prawy", "2 Skorupa kolumny", WHITE_MATTE, 4, "side_cover(1);"),
    ("skorupa_bok_lewy", "2 Skorupa kolumny", WHITE_MATTE, 4, "side_cover(-1);"),
    # 1. Was 3 until 2026-10-03: two bosses stood 3.5 mm off the walls.
    ("skorupa_oslona_sruby_dol", "2 Skorupa kolumny", WHITE_MATTE, 1, "screw_guard_lower();"),
    ("skorupa_oslona_sruby_gora", "2 Skorupa kolumny", WHITE_MATTE, 1, "screw_guard_upper();"),
    ("skorupa_czapka", "2 Skorupa kolumny", WHITE_MATTE, 1, "top_cap();"),
    ("skorupa_skrzynka_sterownika", "2 Skorupa kolumny", WHITE_MATTE, 1, "driver_box();"),
]
ZLIFT = {p[0] for p in ZPARTS}
PARTS += ZPARTS
# Exported for the silhouette check against main_base.scad, but the real
# column replaces them in the Fusion scene.
PROXY = {"kolumna_konstrukcja", "kolumna_skorupa"}

# per source: parts the negative control drops (big, visible from both cameras)
CONTROL_DROP = {"base": {"kolumna_skorupa"},
                "zlift": {"skorupa_bok_prawy", "skorupa_bok_lewy"}}
# ponytail: silhouettes only - a part hidden behind others in both views can go
# missing unnoticed; the Fusion screenshot review (plan step 6) covers that.
CAMERAS = ["0,0,620,68,0,215,4300", "0,0,560,78,0,0,3900"]   # hero, rear
SIL_TOL = 0.01          # fraction of silhouette pixels allowed to differ
BG = np.array([255, 255, 229])   # OpenSCAD preview background


def scad_header():
    return (f"include <{MAIN}>\n"
            "render_assembly = false;\n"
            f'par6_mesh_dir = "{PAR6}";\n'
            "$fa = 4; $fs = 1;\n")


def zlift_header():
    # carriage LOW: mobile_base hangs the arm at col_carriage_low (377 = 240 + 137)
    return (f"include <{ZMAIN}>\n"
            "render_assembly = false;\n"
            "$fa = 4; $fs = 1;\n"
            "carriage_position_mm = 0;\n"
            "show_brake_margin = false;\n"
            "module to_base() translate([-base_plate_cy, 0, base_deck_from_floor])"
            " rotate([0, 0, -90]) children();\n")


def run_openscad(args, log_name):
    r = subprocess.run([OPENSCAD] + args, capture_output=True, text=True)
    log = r.stdout + r.stderr
    bad = [l for l in log.splitlines()
           if l.startswith("ERROR") or "Assert" in l or "Ignoring unknown" in l]
    if bad:
        raise RuntimeError(f"{log_name}: " + " | ".join(bad[:3]))
    return log


def export_part(part, tmp):
    name, _, _, want, body = part
    src = os.path.join(tmp, name + ".scad")
    raw = os.path.join(tmp, name + ".stl")
    with open(src, "w", encoding="utf-8") as f:
        if name in ZLIFT:
            # flags stay at file level: inside to_base() { } they would be
            # locals, and viz() reads the global - every drive part came out
            # as the whole drive (7 bodies each) until this split
            *flags, call = [s.strip() for s in body.split(";") if s.strip()]
            f.write(zlift_header() + "".join(s + ";\n" for s in flags)
                    + "to_base() " + call + ";\n")
        else:
            f.write(scad_header() + body + "\n")
    run_openscad(["-o", raw, src], name)
    if not os.path.exists(raw):
        raise RuntimeError(f"{name}: OpenSCAD wrote nothing - empty geometry")

    for old in os.listdir(MESH):
        if old.startswith(name + "__"):
            os.remove(os.path.join(MESH, old))
    mesh = trimesh.load(raw, force="mesh")
    if want is None:
        pieces = [mesh]
    else:
        pieces = mesh.split(only_watertight=False)
        # stable numbering: by centroid, X then Y then Z
        pieces.sort(key=lambda m: tuple(np.round(m.bounds.mean(axis=0), 1)))
    files = []
    for i, m in enumerate(pieces, 1):
        fn = f"{name}__{i}.stl"
        m.export(os.path.join(MESH, fn))
        files.append(fn)
    return name, files


# Arm joints for viz/tools/joints.py, from the chain that places the meshes:
# par6_arm.scad draws each link right after its joint's rotate, so the link
# frame's Z is the joint axis. par6_mesh() is swapped for three markers in one
# link's frame - 2 mm cube on the origin, 1.5 mm on +X, 1 mm on +Z - nothing
# about the arm or its pose is copied here.
ARM_JOINTS = [("J1", "shoulder", "base_link"), ("J2", "upper_arm", "shoulder"),
              ("J3", "elbow", "upper_arm"), ("J4", "lower_arm", "elbow"),
              ("J5", "wrist", "lower_arm"), ("J6", "gripper", "wrist")]
MARK = 20


def link_frame(link, tmp):
    src, out = (os.path.join(tmp, f"frame_{link}.{e}") for e in ("scad", "stl"))
    with open(src, "w", encoding="utf-8") as f:
        f.write(scad_header() + f'par6_only = "{link}";\n'
                "module par6_mesh(name) { if (name == par6_only) {\n"
                f"    cube(2, center = true); translate([{MARK}, 0, 0]) cube(1.5, center = true);\n"
                f"    translate([0, 0, {MARK}]) cube(1, center = true); }} }}\n"
                "arms_proxy(carriage_z);\n"
                'echo(str("ZTRAVEL=", col_carriage_high - col_carriage_low));\n')
    log = run_openscad(["-o", out, src], f"frame_{link}")
    marks = trimesh.load(out, force="mesh").split(only_watertight=False)
    if len(marks) != 3:
        raise RuntimeError(f"frame_{link}: {len(marks)} znacznikow zamiast 3 - par6_mesh() nie podmieniony")
    o, x, z = (m.bounds.mean(axis=0) for m in sorted(marks, key=lambda m: -m.volume))
    frame = np.eye(4)
    frame[:3, 0], frame[:3, 2], frame[:3, 3] = (x - o) / MARK, (z - o) / MARK, o
    frame[:3, 1] = np.cross(frame[:3, 2], frame[:3, 0])
    return frame, float(re.search(r"ZTRAVEL=([-\d.]+)", log).group(1))


def kinematics(tmp):
    """Joint axes + Z travel for the manifest, and failures: the raw link STL
    moved by its marker frame must land on the scene mesh - and must miss it
    when the frame is off by 2 mm, or the check is blind."""
    links = [c for _, c, _ in ARM_JOINTS]
    with ThreadPoolExecutor(3) as pool:
        frames = dict(zip(links, pool.map(lambda n: link_frame(n, tmp), links)))
    failures = []
    for n, (frame, _) in frames.items():
        raw = trimesh.load(os.path.join(ROOT, "par6_ref", "meshes", n + ".STL"), force="mesh")
        raw.apply_scale(1000)
        scene = trimesh.load(os.path.join(MESH, f"ramie_{n}__1.stl"), force="mesh")
        for shift in (0, 2):
            t = frame.copy()
            t[0, 3] += shift
            err = np.abs(raw.copy().apply_transform(t).bounds - scene.bounds).max()
            if (err > 0.05) != bool(shift):
                failures.append(f"os {n}: rama znacznikow {'nie trafia w siatke' if not shift else 'kontrola slepa'}"
                                f" ({err:.3f} mm)")
    return {"z_travel": frames[links[0]][1],
            "arm": [{"name": j, "link": f"ramie_{c}", "parent": f"ramie_{p}",
                     "origin": frames[c][0][:3, 3].round(3).tolist(),
                     "axis": frames[c][0][:3, 2].round(6).tolist()} for j, c, p in ARM_JOINTS]}, failures


def silhouette(img):
    a = np.asarray(Image.open(img).convert("RGB")).astype(int)
    return np.abs(a - BG).max(axis=2) > 12


def render(args, out):
    run_openscad(["-o", out, "--preview", "--imgsize=1500,1400"] + args, out)
    return silhouette(out)


def scene_mismatch(entries, tmp, cam, tag):
    src = os.path.join(tmp, f"scene_{tag}.scad")
    with open(src, "w", encoding="utf-8") as f:
        for e in entries:
            for b in e["bodies"]:
                f.write(f'import("{os.path.join(MESH, b)}");\n'.replace("\\", "/"))
    return render([f"--camera={cam}", src], os.path.join(tmp, f"scene_{tag}.png"))


# The mass budget copies the covers' mass and centroid from these meshes
# (mobile_base/base_masses.scad, 2026-10-03 - before that one band of 1.6-3.0
# kg stood for all of it). A copy is a second model, so if a cover changes
# and the literals do not, fail here. Low end PETG 1.27 at 55 % (slicer, 2
# walls, flat - test_rig/coupons.scad, 2026-10-04), high end solid PETG.
MASSES = os.path.join(ROOT, "mobile_base", "base_masses.scad")
COVER_GROUPS = {
    "cover": lambda e: e["group"] == "1 Osłony" and e["name"] != "oslona_wsporniki",
    "col_shell": lambda e: e["group"] == "2 Skorupa kolumny",
}


def cover_mass_check(manifest, masses=MASSES):
    with open(masses, encoding="utf-8") as f:
        src = f.read()
    failures = []
    for key, pick in COVER_GROUPS.items():
        vol, moment = 0.0, np.zeros(3)
        for e in manifest["parts"]:
            if e["scene"] and pick(e):
                for b in e["bodies"]:
                    m = trimesh.load(os.path.join(MESH, b), force="mesh")
                    c = m.center_mass if m.is_watertight else m.bounds.mean(axis=0)
                    vol += abs(m.volume)
                    moment += abs(m.volume) * np.asarray(c)
        com = moment / vol
        want = (vol * 1.27e-6 * 0.55, vol * 1.27e-6)
        kg = [float(x) for x in re.search(
            rf"\b{key}_kg\s*=\s*\[([\d.]+),\s*([\d.]+)\]", src).groups()]
        lit = [float(x) for x in re.search(
            rf"\b{key}_com\s*=\s*\[([-\d.]+),\s*([-\d.]+),\s*([-\d.]+)\]", src).groups()]
        print(f"  masa {key}: {vol / 1e6:.2f} dm3 -> {want[0]:.2f}..{want[1]:.2f} kg, "
              f"srodek {np.round(com).astype(int).tolist()}")
        if (max(abs(a - b) for a, b in zip(kg, want)) > 0.05
                or max(abs(a - b) for a, b in zip(lit, com)) > 10):
            failures.append(f"base_masses.scad {key}_kg {kg} / {key}_com {lit}, a siatki daja "
                            f"{want[0]:.2f}..{want[1]:.2f} kg w {np.round(com).astype(int).tolist()}")
    return failures


def check(manifest, tmp):
    failures = cover_mass_check(manifest)
    for e in manifest["parts"]:
        n, want = len(e["bodies"]), e["expected"]
        if want is not None and n != want:
            failures.append(f"{e['name']}: {n} bryl, oczekiwano {want}")
    zref = os.path.join(tmp, "zlift_ref.scad")
    with open(zref, "w", encoding="utf-8") as f:
        f.write(zlift_header() + "to_base() lift_assembly(cz);\n")
    refs = {"base": ["-D", "show_column=false", MAIN], "zlift": [zref]}
    for src, ref in refs.items():
        mine = [e for e in manifest["parts"] if e["src"] == src]
        kept = [e for e in mine if e["name"] not in CONTROL_DROP[src]]
        for k, cam in enumerate(CAMERAS):
            model = render([f"--camera={cam}"] + ref, os.path.join(tmp, f"{src}_model_{k}.png"))
            for entries, tag in ((mine, "pelna"), (kept, "kontrola")):
                scene = scene_mismatch(entries, tmp, cam, f"{src}_{tag}_{k}")
                frac = (model ^ scene).sum() / model.sum()
                print(f"  sylwetka {src} kamera {k} {tag}: {frac:.2%} rozne")
                if tag == "pelna" and frac > SIL_TOL:
                    failures.append(f"{src} kamera {k}: scena rozni sie od modelu o {frac:.2%}")
                if tag == "kontrola" and frac <= SIL_TOL:
                    failures.append(f"{src} kamera {k}: kontrola negatywna nie wykryla braku "
                                    f"{sorted(CONTROL_DROP[src])} ({frac:.2%}) - test jest slepy")
    return failures


def main():
    args = sys.argv[1:]
    only_check = args == ["--check"]
    names = [p[0] for p in PARTS]
    unknown = [a for a in args if a not in names and not only_check]
    if unknown:
        sys.exit(f"nieznane czesci: {unknown}")
    todo = [] if only_check else [p for p in PARTS if not args or p[0] in args]

    os.makedirs(MESH, exist_ok=True)
    path = os.path.join(MESH, "manifest.json")
    bodies = {}         # only the file lists survive between runs; the rest is PARTS
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            bodies = {e["name"]: e["bodies"] for e in json.load(f)["parts"]}

    with tempfile.TemporaryDirectory() as tmp:
        with ThreadPoolExecutor(max(1, (os.cpu_count() or 2) // 2)) as pool:
            for name, files in pool.map(lambda p: export_part(p, tmp), todo):
                print(f"  {name}: {len(files)} bryl")
                bodies[name] = files
        missing = [n for n in names if n not in bodies]
        if missing:
            sys.exit(f"brak w manifescie (wyeksportuj): {missing}")
        kin, failures = kinematics(tmp)
        manifest = {"note": "WIZUALIZACJA - nie do produkcji. Generuje viz/export.py.",
                    "parts": [{"name": n, "group": g, "appearance": a, "expected": w,
                               "src": "zlift" if n in ZLIFT else "base",
                               "scene": n not in PROXY,
                               "bodies": bodies[n]} for n, g, a, w, _ in PARTS],
                    "kinematics": kin}
        with open(path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)

        failures += check(manifest, tmp)
    if failures:
        print("FAIL")
        for f in failures:
            print("  -", f)
        sys.exit(1)
    print("OK - scena zgodna z modelem")


if __name__ == "__main__":
    main()
