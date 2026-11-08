#!/usr/bin/env python3
"""Bench console for one NEMA23 with a brake - single motor, zero ROS.

    python test_rig/motor_console.py            # GUI
    python test_rig/motor_console.py --selftest # no hardware, checks the parser

WHY
  The PAROL6 commander runs on ROS 2 and MoveIt because it has to solve
  kinematics for six axes. To find out how much this ONE axis pulls on a test
  lever that whole stack is dead weight - a serial port, three plots and a STOP
  button do the job, and they start in a second instead of a minute.

WHAT THIS DOES NOT DO
  It does not know the real shaft angle. The TMC5160 runs open loop, so
  "position" is steps SENT. If the motor skips, this plot will not show it - a
  protractor held against the lever will. The gap between the two IS the result
  of the test.
  It does not measure torque. Torque is the hanging mass times the radius -
  see lever_check.py.
"""

import argparse
import csv
import queue
import threading
import time
from collections import deque

BAUD = 115200
HIST_S = 30.0            # seconds of history kept on the plots
POLL_MS = 50             # how often the GUI drains the queue


# ---------------------------------------------------------------------------
#  TELEMETRY
#  Line format from the firmware (nema23_bench.ino, telemetry()):
#    T,ms,pos_deg,vel_dps,tgt_deg,pwm_scale,drv_status_hex,v24,en,brk,estop,cyc
# ---------------------------------------------------------------------------
FIELDS = ("ms", "pos", "vel", "tgt", "pwm", "status", "v24", "en", "brk",
          "estop", "cyc")


def parse_telem(line):
    """Return a dict, or None when the line is not telemetry."""
    if not line.startswith("T,"):
        return None
    parts = line.strip().split(",")
    if len(parts) != len(FIELDS) + 1:
        return None
    try:
        d = {
            "ms":     int(parts[1]),
            "pos":    float(parts[2]),
            "vel":    float(parts[3]),
            "tgt":    float(parts[4]),
            "pwm":    int(parts[5]),
            "status": int(parts[6], 16),
            "v24":    float(parts[7]),
            "en":     bool(int(parts[8])),
            "brk":    bool(int(parts[9])),
            "estop":  bool(int(parts[10])),
            "cyc":    int(parts[11]),
        }
    except (ValueError, IndexError):
        return None
    return d


# TMC5160 DRV_STATUS. Only the bits that mean something during a load test -
# overheating and shorts matter more than the rest of the register.
STATUS_BITS = (
    (25, "OT",    "OVERHEAT - driver shut down"),
    (26, "OTPW",  "temperature pre-warning"),
    (27, "S2GA",  "short to ground, phase A"),
    (28, "S2GB",  "short to ground, phase B"),
    (12, "S2VSB", "short to supply, phase B"),
    (11, "S2VSA", "short to supply, phase A"),
    (29, "OLA",   "open load phase A (or motor standing still)"),
    (30, "OLB",   "open load phase B (or motor standing still)"),
)


def status_flags(status):
    """List of (short, description) for every alarm bit that is set."""
    return [(short, desc) for bit, short, desc in STATUS_BITS
            if status & (1 << bit)]


def status_cs(status):
    """CS_ACTUAL - the current scale the driver actually drives (0-31)."""
    return (status >> 16) & 0x1F


# ---------------------------------------------------------------------------
#  SERIAL LAYER
# ---------------------------------------------------------------------------
class Link:
    """Reader thread for the serial port. The GUI never blocks on it."""

    def __init__(self):
        self.ser = None
        self.q = queue.Queue()
        self.stop = threading.Event()
        self.thread = None

    def open(self, port):
        import serial          # imported here so --selftest runs without pyserial
        self.close()
        self.ser = serial.Serial(port, BAUD, timeout=0.1)
        self.stop.clear()
        self.thread = threading.Thread(target=self._read, daemon=True)
        self.thread.start()

    def close(self):
        self.stop.set()
        if self.thread:
            self.thread.join(timeout=0.5)
            self.thread = None
        if self.ser:
            try:
                self.ser.close()
            except Exception:
                pass
            self.ser = None

    def _read(self):
        buf = b""
        while not self.stop.is_set():
            try:
                chunk = self.ser.read(256)
            except Exception as e:
                self.q.put(("err", str(e)))
                return
            if not chunk:
                continue
            buf += chunk
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                self.q.put(("line", raw.decode("ascii", "replace").strip()))

    def send(self, text):
        if not self.ser:
            return False
        try:
            self.ser.write((text + "\n").encode())
            return True
        except Exception as e:
            self.q.put(("err", str(e)))
            return False

    @property
    def connected(self):
        return self.ser is not None


def list_ports():
    try:
        from serial.tools import list_ports
        return [p.device for p in list_ports.comports()]
    except Exception:
        return []


# ---------------------------------------------------------------------------
#  GUI
# ---------------------------------------------------------------------------
def run_gui():
    import tkinter as tk
    from tkinter import ttk
    import matplotlib
    matplotlib.use("TkAgg")
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg

    link = Link()
    t0 = time.monotonic()
    hist = {k: deque() for k in ("t", "pos", "tgt", "vel", "pwm")}
    logger = {"writer": None, "fh": None}

    root = tk.Tk()
    root.title("NEMA23 bench - 57BYG250B with brake")
    root.geometry("1180x760")

    left = ttk.Frame(root, padding=8)
    left.pack(side="left", fill="y")
    right = ttk.Frame(root)
    right.pack(side="right", fill="both", expand=True)

    def send(cmd):
        if not link.send(cmd):
            log(f"! not connected ({cmd})")

    # --- connection --------------------------------------------------------
    box = ttk.LabelFrame(left, text="Port", padding=6)
    box.pack(fill="x", pady=3)
    port_var = tk.StringVar()
    port_cb = ttk.Combobox(box, textvariable=port_var, width=16,
                           values=list_ports())
    port_cb.pack(side="left")
    if port_cb["values"]:
        port_var.set(port_cb["values"][0])

    def refresh_ports():
        port_cb["values"] = list_ports()

    ttk.Button(box, text="R", width=3, command=refresh_ports).pack(side="left", padx=2)

    conn_btn = ttk.Button(box, text="Connect")
    conn_btn.pack(side="left", padx=2)

    def toggle_conn():
        if link.connected:
            link.close()
            conn_btn.config(text="Connect")
            log("- disconnected")
        else:
            try:
                link.open(port_var.get())
            except Exception as e:
                log(f"! {e}")
                return
            conn_btn.config(text="Disconnect")
            log(f"- connected {port_var.get()}")
            send("?")

    conn_btn.config(command=toggle_conn)

    # --- drive state -------------------------------------------------------
    box = ttk.LabelFrame(left, text="Drive", padding=6)
    box.pack(fill="x", pady=3)
    en_var = tk.IntVar()
    brk_var = tk.IntVar()
    ttk.Checkbutton(box, text="ENABLE (coils on)", variable=en_var,
                    command=lambda: send(f"EN {en_var.get()}")).pack(anchor="w")
    ttk.Checkbutton(box, text="brake released", variable=brk_var,
                    command=lambda: send(f"BRK {brk_var.get()}")).pack(anchor="w")
    ttk.Label(box, text="The brake releases itself before a move.\n"
                        "This toggle is for turning the shaft by hand.",
              foreground="#666").pack(anchor="w")

    # --- settings ----------------------------------------------------------
    box = ttk.LabelFrame(left, text="Settings", padding=6)
    box.pack(fill="x", pady=3)

    def row(parent, label, default, cmd, unit):
        """cmd=None -> entry with no button (read only when START is pressed)."""
        f = ttk.Frame(parent)
        f.pack(fill="x", pady=1)
        ttk.Label(f, text=label, width=9).pack(side="left")
        v = tk.StringVar(value=str(default))
        ttk.Entry(f, textvariable=v, width=8).pack(side="left")
        ttk.Label(f, text=unit, width=11).pack(side="left")
        if cmd:
            ttk.Button(f, text="set", width=4,
                       command=lambda: send(f"{cmd} {v.get()}")).pack(side="left")
        return v

    cur_v = row(box, "current", 1200, "CUR", "mA rms")
    spd_v = row(box, "speed", 300, "V", "deg/s")
    acc_v = row(box, "accel", 2000, "A", "deg/s2")
    ttk.Label(box, text="2.5 A/phase  ->  1768 mA rms max.\n"
                        "Start low, raise it while watching OTPW.",
              foreground="#666").pack(anchor="w", pady=(4, 0))

    # --- jog ---------------------------------------------------------------
    box = ttk.LabelFrame(left, text="Manual move", padding=6)
    box.pack(fill="x", pady=3)
    jog = ttk.Frame(box)
    jog.pack()
    for i, d in enumerate((-90, -10, -1, 1, 10, 90)):
        ttk.Button(jog, text=f"{d:+d} deg", width=7,
                   command=lambda d=d: send(f"J {d}")).grid(row=0, column=i, padx=1)
    f = ttk.Frame(box)
    f.pack(fill="x", pady=3)
    goto_v = tk.StringVar(value="0")
    ttk.Label(f, text="go to").pack(side="left")
    ttk.Entry(f, textvariable=goto_v, width=8).pack(side="left", padx=2)
    ttk.Label(f, text="deg").pack(side="left")
    ttk.Button(f, text="GO", command=lambda: send(f"G {goto_v.get()}")).pack(side="left", padx=2)
    ttk.Button(f, text="ZERO", command=lambda: send("Z")).pack(side="left")

    # --- cycle -------------------------------------------------------------
    box = ttk.LabelFrame(left, text="Left-right cycle", padding=6)
    box.pack(fill="x", pady=3)
    cyc_a = row(box, "amplitude", 90, None, "deg")
    cyc_d = row(box, "dwell", 500, None, "ms")
    cyc_n = row(box, "cycles", 0, None, "0 = forever")
    f = ttk.Frame(box)
    f.pack(fill="x", pady=2)
    ttk.Button(f, text="START",
               command=lambda: send(f"CYC {cyc_a.get()} {cyc_d.get()} {cyc_n.get()}")
               ).pack(side="left", padx=2)
    ttk.Button(f, text="STOP", command=lambda: send("CYC0")).pack(side="left")

    # --- stop --------------------------------------------------------------
    box = ttk.Frame(left, padding=4)
    box.pack(fill="x", pady=6)
    ttk.Button(box, text="STOP (ramp down)", command=lambda: send("S")).pack(fill="x", pady=2)
    estop = tk.Button(box, text="E-STOP", bg="#c0392b", fg="white",
                      font=("TkDefaultFont", 13, "bold"), height=2,
                      command=lambda: send("X"))
    estop.pack(fill="x", pady=2)
    ttk.Button(box, text="clear E-STOP", command=lambda: send("CLR")).pack(fill="x")

    # --- CSV log -----------------------------------------------------------
    box = ttk.LabelFrame(left, text="Logging", padding=6)
    box.pack(fill="x", pady=3)
    log_var = tk.IntVar()

    def toggle_log():
        if log_var.get():
            name = time.strftime("bench_%Y%m%d_%H%M%S.csv")
            logger["fh"] = open(name, "w", newline="", encoding="utf-8")
            logger["writer"] = csv.writer(logger["fh"])
            logger["writer"].writerow(FIELDS)
            log(f"- logging to {name}")
        else:
            if logger["fh"]:
                logger["fh"].close()
            logger["fh"] = logger["writer"] = None
            log("- log closed")

    ttk.Checkbutton(box, text="write CSV", variable=log_var,
                    command=toggle_log).pack(anchor="w")

    # --- status ------------------------------------------------------------
    status_lbl = tk.Label(left, text="-", justify="left", anchor="w",
                          font=("TkFixedFont", 9))
    status_lbl.pack(fill="x", pady=4)

    console = tk.Text(left, height=8, width=44, font=("TkFixedFont", 8))
    console.pack(fill="both", expand=True)

    def log(msg):
        console.insert("end", msg + "\n")
        console.see("end")
        if int(console.index("end-1c").split(".")[0]) > 400:
            console.delete("1.0", "200.0")

    # --- plots -------------------------------------------------------------
    fig = Figure(figsize=(7.5, 7.2), dpi=96)
    ax_p = fig.add_subplot(311)
    ax_v = fig.add_subplot(312, sharex=ax_p)
    ax_l = fig.add_subplot(313, sharex=ax_p)
    fig.subplots_adjust(hspace=0.28, left=0.11, right=0.97, top=0.96, bottom=0.07)

    l_pos, = ax_p.plot([], [], lw=1.6, label="position")
    l_tgt, = ax_p.plot([], [], lw=1.0, ls="--", label="target")
    l_vel, = ax_v.plot([], [], lw=1.4, color="#e67e22")
    l_pwm, = ax_l.plot([], [], lw=1.4, color="#8e44ad")

    ax_p.set_ylabel("angle [deg]"); ax_p.legend(loc="upper right", fontsize=8)
    ax_v.set_ylabel("speed [deg/s]")
    ax_l.set_ylabel("PWM_SCALE (load)")
    ax_l.set_xlabel("time [s]")
    for a in (ax_p, ax_v, ax_l):
        a.grid(alpha=0.3)

    canvas = FigureCanvasTkAgg(fig, master=right)
    canvas.get_tk_widget().pack(fill="both", expand=True)

    # --- GUI loop ----------------------------------------------------------
    def trim():
        cutoff = hist["t"][-1] - HIST_S if hist["t"] else 0
        while hist["t"] and hist["t"][0] < cutoff:
            for d in hist.values():
                d.popleft()

    def pump():
        got = False
        while True:
            try:
                kind, payload = link.q.get_nowait()
            except queue.Empty:
                break
            if kind == "err":
                log(f"! {payload}")
                continue
            d = parse_telem(payload)
            if d is None:
                if payload:
                    log(payload)
                continue
            got = True
            t = time.monotonic() - t0
            hist["t"].append(t)
            hist["pos"].append(d["pos"])
            hist["tgt"].append(d["tgt"])
            hist["vel"].append(d["vel"])
            hist["pwm"].append(d["pwm"])
            if logger["writer"]:
                logger["writer"].writerow([d[k] for k in FIELDS])

            flags = status_flags(d["status"])
            en_var.set(int(d["en"]))
            brk_var.set(int(d["brk"]))
            status_lbl.config(
                text=(f"angle {d['pos']:8.2f}    target {d['tgt']:8.2f}\n"
                      f"speed {d['vel']:8.2f}    cycles {d['cyc']}\n"
                      f"24V   {d['v24']:5.2f}    CS {status_cs(d['status'])}/31\n"
                      f"{'E-STOP' if d['estop'] else 'ok'}  "
                      f"{' '.join(f for f, _ in flags) if flags else ''}"),
                fg="#c0392b" if (d["estop"] or flags) else "#000")

        if got:
            trim()
            l_pos.set_data(hist["t"], hist["pos"])
            l_tgt.set_data(hist["t"], hist["tgt"])
            l_vel.set_data(hist["t"], hist["vel"])
            l_pwm.set_data(hist["t"], hist["pwm"])
            for a in (ax_p, ax_v, ax_l):
                a.relim()
                a.autoscale_view()
            canvas.draw_idle()

        root.after(POLL_MS, pump)

    def on_close():
        # Do not leave the motor energised just because the window went away.
        if link.connected:
            link.send("X")
            time.sleep(0.2)
        link.close()
        if logger["fh"]:
            logger["fh"].close()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)
    root.after(POLL_MS, pump)
    root.mainloop()


# ---------------------------------------------------------------------------
#  SELFTEST - the only non-trivial logic on this side is the parser and the bits
# ---------------------------------------------------------------------------
def selftest():
    good = "T,12345,90.000,15.20,90.000,42,C0180000,24.31,1,1,0,7"
    d = parse_telem(good)
    assert d is not None
    assert d["ms"] == 12345 and d["pos"] == 90.0 and d["vel"] == 15.2
    assert d["pwm"] == 42 and d["v24"] == 24.31
    assert d["en"] and d["brk"] and not d["estop"] and d["cyc"] == 7

    assert parse_telem("I ready") is None
    assert parse_telem("K EN 1") is None
    assert parse_telem("T,1,2,3") is None, "a short line must be rejected"
    assert parse_telem("T,x,2,3,4,5,6,7,8,9,10") is None, "garbage must be rejected"

    # 0xC0180000: bits 31 (stst) and 30 (OLB) plus CS_ACTUAL = 0x18 = 24
    assert status_cs(0xC0180000) == 24
    assert [f for f, _ in status_flags(0xC0180000)] == ["OLB"]
    # overheating: bits 25 and 26
    flags = [f for f, _ in status_flags((1 << 25) | (1 << 26))]
    assert set(flags) == {"OT", "OTPW"}, flags
    assert status_flags(0) == []

    print("selftest OK")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
    else:
        run_gui()
