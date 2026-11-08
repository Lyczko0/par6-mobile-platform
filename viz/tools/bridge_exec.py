#!/usr/bin/env python3
"""Run a Python file inside the running Fusion via the FusionMCPBridge add-in.

    python viz/tools/bridge_exec.py <script.py> [NAME=python_literal ...]
    python viz/tools/bridge_exec.py --health

NAME=value pairs are appended after the script, so they override its
module-level constants before run() is called.

The add-in listens on 127.0.0.1:7654 and this speaks plain HTTP to it.
Gotchas:
  * a dialog in Fusion stalls requests (504) - close it first. The one shown
    at startup after an unclean exit (recently closed documents) lets --health
    and plain scripts through and blocks only viewport images and renders -
    three "hangs" on 2026-09-25. Killing Fusion over one brings the dialog
    back at the next start;
  * never ui.messageBox from a bridge script - it blocks Fusion's main thread;
  * the add-in times out after ~30 s but the work keeps running - poll --health
    instead of re-sending, or you run the script twice;
  * exec has no __file__ - appended below so scripts can find their folder;
  * PowerShell's Out-File writes a BOM that exec chokes on - read as utf-8-sig.
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = "http://127.0.0.1:7654"
SECRET = os.path.expanduser("~/.fusion-mcp-secret")


def headers():
    h = {"Content-Type": "application/json"}
    # The add-in only checks the token when this file exists on its side too.
    if os.path.exists(SECRET):
        with open(SECRET, encoding="utf-8") as f:
            h["Authorization"] = "Bearer " + f.read().strip()
    return h


def health():
    req = urllib.request.Request(URL + "/health", headers=headers())
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def execute(path, overrides=()):
    path = os.path.abspath(path)
    with open(path, encoding="utf-8-sig") as f:
        src = f.read()
    src += f"\n__file__ = r'{path}'\n"     # runs before the bridge calls run()
    for kv in overrides:
        name, value = kv.split("=", 1)
        src += f"{name} = {value}\n"
    req = urllib.request.Request(URL + "/execute",
                                 data=json.dumps({"script": src}).encode("utf-8"),
                                 headers=headers())
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.load(r).get("result", "<no result>")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    try:
        if sys.argv[1] == "--health":
            print(json.dumps(health(), indent=2))
        else:
            print(execute(sys.argv[1], sys.argv[2:]))
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')}")
    except urllib.error.URLError as e:
        sys.exit(f"most nie odpowiada ({e.reason}) - czy Fusion i add-in "
                 f"FusionMCPBridge sa uruchomione? Shift+S -> Run")
    except TimeoutError:
        sys.exit("most dziala, ale Fusion nie odpowiada - zajety albo wisi okno "
                 "dialogowe (po starcie: ostatnio zamkniete dokumenty) - zamknij "
                 "okno, NIE zamykaj Fusion")


if __name__ == "__main__":
    main()
