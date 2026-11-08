#!/usr/bin/env python3
"""Cross-check the z_lift <-> mobile_base interface.

    python control/check_interface.py

mobile_base/base_parameters.scad keeps its own copies of a dozen numbers that
z_lift/parameters.scad DERIVES. That is a deliberate simplification - pulling
z_lift into the chassis include chain still clashes on variable names - but a
copy that drifts is worse than no copy at all, because everything downstream
keeps computing happily on the wrong figure.

On 2026-08-18 eight of these had drifted at once and every single one was found
by hand. This script exists so the ninth is found by a command.

How it works: z_lift's interface_report() echoes every shared value as
"IFACE key=value". This runs it, then greps the chassis file for the same keys
and compares. Exit 1 on any mismatch.
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ZLIFT = ROOT / "z_lift"
CHASSIS = ROOT / "mobile_base" / "base_parameters.scad"

# Values whose chassis copy is allowed to be rounded rather than exact, with
# the tolerance in mm. The carriage limits fall out of a ball-screw stack and
# land on quarter-millimetres; rounding those in the chassis is fine.
TOL = {
    "col_carriage_high": 1.0,
    "arm_mount_z_high": 1.0,
}
DEFAULT_TOL = 0.001

# The OTHER direction. z_lift also carries copies of chassis values - the
# battery it has to clear and the frame members around the motor bay. Those
# went stale in three places at once (battery, tray, beam spacing) and nothing
# noticed, because this script only ever looked one way. Left: literal in
# z_lift/parameters.scad. Right: variable evaluated in base_parameters.scad.
REVERSE = [
    ("battery_centre_x",       "battery_x"),
    ("battery_len",            "battery_l"),
    ("battery_wid",            "battery_w"),
    ("battery_hgt",            "battery_h"),
    ("battery_bot_from_floor", "battery_z"),
    ("battery_top_from_floor", "battery_top_z"),
    ("tray_top_from_floor",    "tray_top_z"),
    ("chassis_profile_y",      "main_beam_y"),
    ("chassis_profile_w",      "profile_main_w"),
    ("chassis_cross_x",        "cross_x"),
]


def find_openscad():
    for c in ("openscad", r"C:/Program Files/OpenSCAD/openscad.com",
              "/c/Program Files/OpenSCAD/openscad.com"):
        if shutil.which(c) or Path(c).exists():
            return c
    sys.exit("nie znalazlem openscad - ustaw OPENSCAD albo dopisz sciezke")


def zlift_values():
    """Run z_lift's interface_report() and collect the IFACE lines."""
    gen = ZLIFT / "_iface_gen.scad"
    gen.write_text("include <parameters.scad>\ninterface_report();\n",
                   encoding="utf-8")
    try:
        # This binary puts ECHO on stdout; others put it on stderr.
        # Exit code 1 here is EXPECTED - the file renders no geometry.
        r = subprocess.run(
            [find_openscad(), "-o", str(ZLIFT / "_iface_gen.stl"),
             "--export-format=asciistl", str(gen)],
            capture_output=True, text=True, cwd=str(ZLIFT))
        out = (r.stdout or "") + (r.stderr or "")
    finally:
        gen.unlink(missing_ok=True)
        (ZLIFT / "_iface_gen.stl").unlink(missing_ok=True)

    vals = {}
    for m in re.finditer(r'IFACE (\w+)=([-\d.]+)', out):
        vals[m.group(1)] = float(m.group(2))
    if not vals:
        sys.exit("z_lift nie wypisal ani jednej linii IFACE - czy "
                 "interface_report() nadal istnieje w parameters.scad?")
    return vals


def _num_or_vec(text):
    text = text.strip()
    if text.startswith("["):
        return tuple(float(v) for v in text.strip("[]").split(",") if v.strip())
    return float(text)


def chassis_evaluated(names):
    """Evaluate chassis variables in OpenSCAD - several are derived, not literal."""
    base = ROOT / "mobile_base"
    gen = base / "_iface_rev_gen.scad"
    lines = ["include <base_parameters.scad>"]
    lines += [f'echo(str("CHASSIS {n}=", {n}));' for n in names]
    body = "\n".join(lines) + "\n"
    gen.write_text(body, encoding="utf-8")
    try:
        r = subprocess.run(
            [find_openscad(), "-o", str(base / "_iface_rev_gen.stl"),
             "--export-format=asciistl", str(gen)],
            capture_output=True, text=True, cwd=str(base))
        out = (r.stdout or "") + (r.stderr or "")
    finally:
        gen.unlink(missing_ok=True)
        (base / "_iface_rev_gen.stl").unlink(missing_ok=True)
    vals = {}
    for m in re.finditer(r'CHASSIS (\w+)=(\[[^\]]*\]|[-\d.e]+)', out):
        vals[m.group(1)] = _num_or_vec(m.group(2))
    return vals


def zlift_literals(names):
    src = (ZLIFT / "parameters.scad").read_text(encoding="utf-8")
    vals = {}
    for n in names:
        m = re.search(rf'^{n}\s*=\s*(\[[^\]]*\]|[-\d.]+)\s*;', src, re.M)
        if m:
            vals[n] = _num_or_vec(m.group(1))
    return vals


def reverse_check():
    """z_lift copies of chassis values. Returns the number of mismatches."""
    zl = zlift_literals([a for a, _ in REVERSE])
    ch = chassis_evaluated([b for _, b in REVERSE])
    print()
    print("=" * 70)
    print("  KOPIE PODWOZIA W z_lift  (kierunek odwrotny)")
    print("=" * 70)
    print(f"  {'z_lift':<24}{'ma':>12}   {'podwozie':<16}{'liczy':>12}   werdykt")
    bad = 0
    for a, b in REVERSE:
        za, cb = zl.get(a), ch.get(b)
        if za is None or cb is None:
            bad += 1
            print(f"  {a:<24}{'BRAK' if za is None else '':>12}   {b:<16}"
                  f"{'BRAK' if cb is None else '':>12}   ?")
            continue
        if isinstance(za, tuple) or isinstance(cb, tuple):
            ok = (isinstance(za, tuple) and isinstance(cb, tuple)
                  and len(za) == len(cb)
                  and all(abs(x - y) <= DEFAULT_TOL for x, y in zip(za, cb)))
            fa, fb = str(list(za)), str(list(cb))
        else:
            ok = abs(za - cb) <= DEFAULT_TOL
            fa, fb = f"{za:.2f}", f"{cb:.2f}"
        bad += 0 if ok else 1
        print(f"  {a:<24}{fa:>12}   {b:<16}{fb:>12}   {'OK' if ok else 'ROZJAZD'}")
    if bad:
        print(f"  {bad} ROZJAZDOW - popraw kopie w z_lift/parameters.scad.")
    else:
        print("  OK - z_lift widzi to samo podwozie, ktore jest w modelu.")
    return bad


def chassis_values(keys):
    """Grep the chassis parameter file for top-level assignments."""
    src = CHASSIS.read_text(encoding="utf-8")
    vals = {}
    for k in keys:
        m = re.search(rf'^{k}\s*=\s*([-\d.]+)\s*;', src, re.M)
        if m:
            vals[k] = float(m.group(1))
    return vals


def main():
    z = zlift_values()
    c = chassis_values(z.keys())

    print("=" * 70)
    print("  INTERFEJS  z_lift  <->  mobile_base")
    print("=" * 70)
    print(f"  {'wartosc':<22}{'z_lift liczy':>14}{'podwozie ma':>14}   werdykt")

    bad, missing = [], []
    for k in sorted(z):
        want = z[k]
        if k not in c:
            missing.append(k)
            print(f"  {k:<22}{want:>14.2f}{'BRAK':>14}   ?")
            continue
        got = c[k]
        tol = TOL.get(k, DEFAULT_TOL)
        ok = abs(want - got) <= tol
        if not ok:
            bad.append((k, want, got))
        print(f"  {k:<22}{want:>14.2f}{got:>14.2f}   "
              f"{'OK' if ok else 'ROZJAZD'}")

    print("  " + "-" * 66)
    if missing:
        print(f"  {len(missing)} wartosci nie ma w podwoziu (moze byc w porzadku,"
              f" jesli nikt ich tam nie uzywa): {', '.join(missing)}")
    if bad:
        print(f"  {len(bad)} ROZJAZDOW:")
        for k, want, got in bad:
            print(f"    {k}: podwozie ma {got}, powinno byc {want}")
        print("  Popraw mobile_base/base_parameters.scad i uruchom ponownie.")
        reverse_check()
        return 1
    print("  OK - kazda kopia zgadza sie z tym, co liczy z_lift.")
    return 1 if reverse_check() else 0


if __name__ == "__main__":
    sys.exit(main())
