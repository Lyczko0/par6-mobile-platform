#!/usr/bin/env python3
"""Bench console for the Gen2.x hoverboard boards - UART control plus plots.

    python test_rig/hover_console.py             # GUI
    python test_rig/hover_console.py --selftest  # no hardware, checks the codec

WHY
  The drive is two salvaged hoverboard mainboards running RoboDurden's Gen2.x
  firmware. They speak a small binary protocol over one 3.3 V serial line, and
  nothing off the shelf speaks it. This is that client, plus the plots that
  make a first power-on readable.

WIRING (layout Gen2.1.1, PL2303 with the jumper on 3.3 V)
    PL2303 GND  ->  board G
    PL2303 TXD  ->  board R   (board RX)
    PL2303 RXD  ->  board T   (board TX)
    PL2303 VCCIO -> leave disconnected, the board has its own supply
  The board's 5V pin is an accessory supply, NOT a logic level. The GD32 is not
  5 V tolerant, so the adapter must be switched to 3.3 V before anything is
  plugged in.

WHICH HEADER - measured, not guessed
  Read back from the running master over SWD: USART0 BAUD = 0x0EA6 (19200 at
  72 MHz) on PB6/PB7, USART1 BAUD = 0x0271 (115200) on PA2/PA3. So the host is
  PB6/PB7 and the master<->slave ribbon is PA2/PA3.
  PB6/PB7 come out on the unpopulated pad column silkscreened REMOTE
  "G T R 5V" (back side: "5V R T G"), right beside the SWD column. It has to be
  the MASTER board - slave builds compile no remote at all.
  On the master the factory 433 MHz key-fob receiver (XL-R93H) sits on that
  spot. If its DATA pin is on T or R it fights the adapter on the same wire, so
  it comes off before this link can be trusted.
  Measured on COM6 (PL2303) with the motor unplugged: the master streams
  feedback unprompted - 82 frames in 20 s of pure listening, then 140 frames in
  15 s while zero commands went out at 20 Hz, zero CRC rejects in either phase.
  So a silent LISTEN really does mean wrong pads, wrong baud or TX/RX swapped.

WHAT THIS DOES NOT DO
  It does not close any loop. Speed is a command, not a measurement; the number
  plotted as speed is what the board reports back over the same link, which is
  its own hall-derived estimate. If the board lies, this plots the lie.
"""

import argparse
import csv
import queue
import struct
import threading
import time
from collections import deque

BAUD_DEFAULT = 19200      # firmware default, see BAUDRATE in the Arduino examples
POLL_MS = 50
SEND_MS = 50              # 20 Hz command rate
HIST_S = 30.0

START_TX = 0x2F           # '/'
START_RX = 0xABCD

# Host -> board, 9 bytes.  <B h h B B H
TX_FMT = "<BhhBBH"
TX_LEN = struct.calcsize(TX_FMT)

# Board -> host, 22 bytes.  <H h h H h h i i H
RX_FMT = "<HhhHhhiiH"
RX_LEN = struct.calcsize(RX_FMT)

# wState bits. 128 is deliberately NOT exposed anywhere in the UI - it powers
# the board down, and a stray click that kills the drive mid-test is not a
# feature.
ST_LED_GREEN, ST_LED_ORANGE, ST_LED_RED = 1, 2, 4
ST_LED_UP, ST_LED_DOWN, ST_BATT3 = 8, 16, 32
ST_DISABLE, ST_SHUTOFF = 64, 128

SPEED_LIMIT = 1000        # protocol range


def crc16(data):
    """CRC-16/XMODEM - poly 0x1021, init 0, no reflection, no final xor.

    Transcribed from CalcCRC() in the firmware's hoverserial.h. Anything else
    (Modbus, CCITT-FALSE) produces frames the board silently drops, which looks
    exactly like wrong wiring - so this is worth the self-test below.
    """
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def pack_cmd(speed, steer, state_master=ST_BATT3, state_slave=0):
    body = struct.pack("<BhhBB", START_TX, int(speed), int(steer),
                       state_master & 0x7F, state_slave & 0x7F)
    return body + struct.pack("<H", crc16(body))


RX_FIELDS = ("speedL", "speedR", "volt", "ampL", "ampR", "odomL", "odomR")


def parse_limit(text, last):
    """Output limit from a text field that is mid-edit most of the time.

    Returns the last good value instead of raising. An IntVar read here raised
    on an empty field, the exception escaped the Tk after() callback before it
    re-armed itself, and the command stream stopped for good.
    """
    try:
        v = int(float(str(text).strip()))
    except ValueError:
        return last
    return max(0, min(SPEED_LIMIT, v))


def parse_frame(buf):
    """Parse one 22-byte feedback frame. Returns a dict or None on bad CRC."""
    if len(buf) != RX_LEN:
        return None
    vals = struct.unpack(RX_FMT, buf)
    if vals[0] != START_RX or crc16(buf[:-2]) != vals[-1]:
        return None
    return {
        "speedL": vals[1] / 100.0,      # km/h
        "speedR": vals[2] / 100.0,
        "volt":   vals[3] / 100.0,      # V
        "ampL":   vals[4] / 100.0,      # A
        "ampR":   vals[5] / 100.0,
        "odomL":  vals[6],              # hall steps
        "odomR":  vals[7],
    }


class Link:
    """Serial reader thread with frame resync. The GUI never blocks on it."""

    def __init__(self):
        self.ser = None
        self.q = queue.Queue()
        self.stop = threading.Event()
        self.thread = None
        self.bad = 0            # frames dropped on CRC / desync

    def open(self, port, baud):
        import serial
        self.close()
        self.ser = serial.Serial(port, baud, timeout=0.1)
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
        buf = bytearray()
        while not self.stop.is_set():
            try:
                chunk = self.ser.read(64)
            except Exception as e:
                self.q.put(("err", str(e)))
                return
            if chunk:
                buf += chunk
            # Resync on the start word rather than assuming alignment: the
            # board streams continuously and we join mid-frame every time.
            while len(buf) >= RX_LEN:
                if buf[0] | (buf[1] << 8) != START_RX:
                    del buf[0]
                    continue
                frame = bytes(buf[:RX_LEN])
                d = parse_frame(frame)
                if d is None:
                    self.bad += 1
                    del buf[0]          # false start word, step past it
                    continue
                del buf[:RX_LEN]
                self.q.put(("frame", d))

    def send(self, payload):
        if not self.ser:
            return False
        try:
            self.ser.write(payload)
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


def run_gui():
    import tkinter as tk
    from tkinter import ttk
    import matplotlib
    matplotlib.use("TkAgg")
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg

    link = Link()
    t0 = time.monotonic()
    hist = {k: deque() for k in ("t", "speedL", "speedR", "ampL", "ampR", "volt")}
    logger = {"writer": None, "fh": None}
    stats = {"frames": 0, "last": 0.0}
    # Live driving state. drive[] is what actually goes out; it ramps
    # toward the target instead of stepping, because a hub motor fed a
    # step command answers with a jerk through the whole chassis.
    drive = {"a": 0.0, "b": 0.0}
    keys = {}                 # key -> monotonic time of the last KeyPress
    # Windows sends one KeyPress, waits ~0.5 s, then auto-repeats. At 0.15 s
    # the key read as released inside that gap and the ramp collapsed before
    # the repeats arrived. Real releases still stop at once via KeyRelease.
    KEY_HOLD = 0.6
    RAMP, DECAY = 25.0, 60.0  # units per 50 ms tick

    root = tk.Tk()
    root.title("Hoverboard bench - Gen2.1.1")
    root.geometry("1200x780")
    left = ttk.Frame(root, padding=8)
    left.pack(side="left", fill="y")
    right = ttk.Frame(root)
    right.pack(side="right", fill="both", expand=True)

    # --- connection --------------------------------------------------------
    box = ttk.LabelFrame(left, text="Port", padding=6)
    box.pack(fill="x", pady=3)
    f = ttk.Frame(box); f.pack(fill="x")
    port_var = tk.StringVar()
    port_cb = ttk.Combobox(f, textvariable=port_var, width=13, values=list_ports())
    port_cb.pack(side="left")
    if port_cb["values"]:
        port_var.set(port_cb["values"][0])
    ttk.Button(f, text="R", width=3,
               command=lambda: port_cb.configure(values=list_ports())).pack(side="left", padx=2)
    baud_var = tk.StringVar(value=str(BAUD_DEFAULT))
    ttk.Combobox(f, textvariable=baud_var, width=7,
                 values=("19200", "115200", "38400", "9600")).pack(side="left", padx=2)
    conn_btn = ttk.Button(box, text="Connect")
    conn_btn.pack(fill="x", pady=(4, 0))

    listen_var = tk.IntVar(value=1)
    ttk.Checkbutton(box, text="LISTEN only (transmit nothing)",
                    variable=listen_var).pack(anchor="w", pady=(4, 0))
    ttk.Label(box, text="Start here to find the right header.\n"
                        "Frames arriving = correct connector.",
              foreground="#666").pack(anchor="w")

    def toggle_conn():
        if link.connected:
            link.send(pack_cmd(0, 0))
            link.close()
            conn_btn.config(text="Connect")
            log("- disconnected")
            return
        try:
            link.open(port_var.get(), int(baud_var.get()))
        except Exception as e:
            log(f"! {e}")
            return
        conn_btn.config(text="Disconnect")
        log(f"- {port_var.get()} @ {baud_var.get()}")

    conn_btn.config(command=toggle_conn)

    # --- drive -------------------------------------------------------------
    box = ttk.LabelFrame(left, text="Drive", padding=6)
    box.pack(fill="x", pady=3)
    mode_var = tk.StringVar(value="tank")
    ttk.Radiobutton(box, text="speed + steer", variable=mode_var,
                    value="ss").pack(anchor="w")
    ttk.Radiobutton(box, text="left / right wheel", variable=mode_var,
                    value="tank").pack(anchor="w")

    def slider(parent, label):
        ttk.Label(parent, text=label).pack(anchor="w", pady=(6, 0))
        v = tk.IntVar(value=0)
        ttk.Scale(parent, from_=-SPEED_LIMIT, to=SPEED_LIMIT, variable=v,
                  orient="horizontal", length=250).pack(fill="x")
        lbl = ttk.Label(parent, text="0")
        lbl.pack(anchor="w")
        v.trace_add("write", lambda *_: lbl.config(text=str(v.get())))
        return v

    a_var = slider(box, "speed / left")
    b_var = slider(box, "steer / right")

    f = ttk.Frame(box); f.pack(fill="x", pady=(6, 0))
    ttk.Label(f, text="max output").pack(side="left")
    max_var = tk.StringVar(value="200")
    lim_state = {"last": 200}
    spin = ttk.Spinbox(f, from_=50, to=SPEED_LIMIT, increment=50, width=6,
                       textvariable=max_var)
    spin.pack(side="left", padx=4)
    # Hand the keyboard back to driving as soon as the field is done with.
    for ev in ("<Return>", "<KP_Enter>", "<<Increment>>", "<<Decrement>>"):
        spin.bind(ev, lambda e: root.after_idle(root.focus_set))
    ttk.Label(f, text=f"of {SPEED_LIMIT}").pack(side="left")

    kb_var = tk.IntVar(value=1)
    ttk.Checkbutton(box, text="keyboard: hold W A S D to drive",
                    variable=kb_var).pack(anchor="w", pady=(4, 0))
    ttk.Label(box, text="Release and it returns to zero on its own.\n"
                        "After typing a number press Enter.",
              foreground="#666").pack(anchor="w")
    kb_lbl = tk.Label(box, text="", anchor="w", font=("TkDefaultFont", 9, "bold"))
    kb_lbl.pack(fill="x")

    KEYMAP = {"w": "up", "s": "down", "a": "left", "d": "right",
              "Up": "up", "Down": "down", "Left": "left", "Right": "right"}

    TYPING = ("Entry", "TEntry", "Spinbox", "TSpinbox", "TCombobox", "Text")

    def typing_widget(w):
        try:
            return w is not None and w.winfo_class() in TYPING
        except Exception:
            return False

    def on_key(ev, down):
        k = KEYMAP.get(ev.keysym)
        if k is None:
            return
        if down:
            # A letter typed into a number field is text, not a drive command.
            if typing_widget(root.focus_get()):
                return
            keys[k] = time.monotonic()
        else:
            keys.pop(k, None)

    root.bind_all("<KeyPress>", lambda e: on_key(e, True), add="+")
    root.bind_all("<KeyRelease>", lambda e: on_key(e, False), add="+")

    def reclaim_focus(ev):
        # Sliders, buttons, the plot: after any click that is not into a text
        # field, the keyboard belongs to driving again.
        if not typing_widget(ev.widget):
            root.after_idle(root.focus_set)

    root.bind_all("<ButtonRelease-1>", reclaim_focus, add="+")
    # Window loses focus while a key is down: no KeyRelease will ever come.
    root.bind("<FocusOut>", lambda e: keys.clear(), add="+")

    def held(k):
        t = keys.get(k)
        return t is not None and time.monotonic() - t < KEY_HOLD

    def zero():
        a_var.set(0)
        b_var.set(0)

    ttk.Button(box, text="ZERO both", command=zero).pack(fill="x", pady=4)

    stop = tk.Button(left, text="STOP", bg="#c0392b", fg="white",
                     font=("TkDefaultFont", 14, "bold"), height=2, command=zero)
    stop.pack(fill="x", pady=6)
    ttk.Label(left, text="STOP sends zero, it does not cut power.\n"
                         "The only real stop is the battery.",
              foreground="#c0392b").pack(anchor="w")

    # --- logging -----------------------------------------------------------
    box = ttk.LabelFrame(left, text="Logging", padding=6)
    box.pack(fill="x", pady=3)
    log_var = tk.IntVar()

    def toggle_log():
        if log_var.get():
            name = time.strftime("hover_%Y%m%d_%H%M%S.csv")
            logger["fh"] = open(name, "w", newline="", encoding="utf-8")
            logger["writer"] = csv.writer(logger["fh"])
            logger["writer"].writerow(("t",) + RX_FIELDS)
            log(f"- logging to {name}")
        else:
            if logger["fh"]:
                logger["fh"].close()
            logger["fh"] = logger["writer"] = None

    ttk.Checkbutton(box, text="write CSV", variable=log_var,
                    command=toggle_log).pack(anchor="w")

    status_lbl = tk.Label(left, text="-", justify="left", anchor="w",
                          font=("TkFixedFont", 9))
    status_lbl.pack(fill="x", pady=4)
    console = tk.Text(left, height=7, width=42, font=("TkFixedFont", 8))
    console.pack(fill="both", expand=True)

    def log(msg):
        console.insert("end", msg + "\n")
        console.see("end")

    # --- plots -------------------------------------------------------------
    fig = Figure(figsize=(7.6, 7.4), dpi=96)
    ax_s = fig.add_subplot(311)
    ax_a = fig.add_subplot(312, sharex=ax_s)
    ax_v = fig.add_subplot(313, sharex=ax_s)
    fig.subplots_adjust(hspace=0.3, left=0.1, right=0.97, top=0.96, bottom=0.07)
    lsl, = ax_s.plot([], [], lw=1.5, label="left")
    lsr, = ax_s.plot([], [], lw=1.5, label="right")
    lal, = ax_a.plot([], [], lw=1.3, label="left")
    lar, = ax_a.plot([], [], lw=1.3, label="right")
    lv,  = ax_v.plot([], [], lw=1.4, color="#8e44ad")
    ax_s.set_ylabel("speed [km/h]"); ax_s.legend(loc="upper right", fontsize=8)
    ax_a.set_ylabel("current [A]");  ax_a.legend(loc="upper right", fontsize=8)
    ax_v.set_ylabel("pack [V]");     ax_v.set_xlabel("time [s]")
    for a in (ax_s, ax_a, ax_v):
        a.grid(alpha=0.3)
    canvas = FigureCanvasTkAgg(fig, master=right)
    canvas.get_tk_widget().pack(fill="both", expand=True)

    # --- loops -------------------------------------------------------------
    tx_err = {"shown": False}

    def tx():
        try:
            tx_body()
        except Exception as e:
            if not tx_err["shown"]:
                log(f"! tx: {e}")
                tx_err["shown"] = True
        finally:
            # Re-arm unconditionally. The first version did this as the last
            # line of the body, so one exception silently ended all sending.
            root.after(SEND_MS, tx)

    def tx_body():
        # A heartbeat, not a one-shot: the firmware stops the motors when the
        # command stream dries up, which is the behaviour we want and the
        # reason this runs even when both sliders sit at zero.
        if kb_var.get():
            lim = parse_limit(max_var.get(), lim_state["last"])
            lim_state["last"] = lim
            tgt_a = (lim if held("up") else 0) - (lim if held("down") else 0)
            tgt_b = (lim if held("right") else 0) - (lim if held("left") else 0)
            for k, tgt in (("a", tgt_a), ("b", tgt_b)):
                step = RAMP if tgt else DECAY
                delta = tgt - drive[k]
                drive[k] += max(-step, min(step, delta))
            a_var.set(int(drive["a"]))
            b_var.set(int(drive["b"]))
        else:
            drive["a"], drive["b"] = float(a_var.get()), float(b_var.get())

        if link.connected and not listen_var.get():
            a, b = int(drive["a"]), int(drive["b"])
            if kb_var.get():
                # The keyboard fills a = forward/back, b = turn. Routing that
                # through tank mode read it as left/right wheel and turned a
                # held W into a half-speed spin in place.
                speed, steer = a, b
            elif mode_var.get() == "tank":
                # HoverSendLR() in the firmware's hoverserial.h: steer is the
                # difference, speed the mean. Its own comment says this only
                # maps 1:1 when the build has SPEED_COEFFICIENT 16384 and
                # STEER_COEFFICIENT 8192 - unknown for a released binary, so
                # treat left/right as approximate until measured.   [VERIFY]
                speed, steer = (a + b) // 2, b - a
            else:
                speed, steer = a, b
            link.send(pack_cmd(speed, steer))

    def pump():
        try:
            pump_body()
        except Exception as e:
            log(f"! pump: {e}")
        finally:
            root.after(POLL_MS, pump)

    def pump_body():
        w = root.focus_get()
        if w is None:
            kb_lbl.config(text="keyboard: window not focused", fg="#888")
        elif typing_widget(w):
            kb_lbl.config(text="keyboard: TYPING - press Enter", fg="#d35400")
        else:
            kb_lbl.config(text="keyboard: ACTIVE", fg="#1e8449")
        got = False
        while True:
            try:
                kind, payload = link.q.get_nowait()
            except queue.Empty:
                break
            if kind == "err":
                log(f"! {payload}")
                continue
            got = True
            stats["frames"] += 1
            stats["last"] = time.monotonic()
            t = time.monotonic() - t0
            hist["t"].append(t)
            for k in ("speedL", "speedR", "ampL", "ampR", "volt"):
                hist[k].append(payload[k])
            if logger["writer"]:
                logger["writer"].writerow([round(t, 3)] + [payload[k] for k in RX_FIELDS])
            last = payload

        if got:
            cutoff = hist["t"][-1] - HIST_S
            while hist["t"] and hist["t"][0] < cutoff:
                for d in hist.values():
                    d.popleft()
            lsl.set_data(hist["t"], hist["speedL"])
            lsr.set_data(hist["t"], hist["speedR"])
            lal.set_data(hist["t"], hist["ampL"])
            lar.set_data(hist["t"], hist["ampR"])
            lv.set_data(hist["t"], hist["volt"])
            for a in (ax_s, ax_a, ax_v):
                a.relim(); a.autoscale_view()
            canvas.draw_idle()
            status_lbl.config(
                text=(f"speed  L {last['speedL']:7.2f}  R {last['speedR']:7.2f} km/h\n"
                      f"amps   L {last['ampL']:7.2f}  R {last['ampR']:7.2f} A\n"
                      f"pack   {last['volt']:7.2f} V\n"
                      f"odom   L {last['odomL']:>9}  R {last['odomR']:>9}\n"
                      f"frames {stats['frames']}   dropped {link.bad}"),
                fg="#000")
        elif link.connected and time.monotonic() - stats["last"] > 1.5:
            status_lbl.config(text="no frames - wrong header, wrong baud,\n"
                                   "or TX/RX swapped", fg="#c0392b")

    def on_close():
        if link.connected:
            link.send(pack_cmd(0, 0))
            time.sleep(0.15)
        link.close()
        if logger["fh"]:
            logger["fh"].close()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)
    root.after(POLL_MS, pump)
    root.after(SEND_MS, tx)
    root.mainloop()


def selftest():
    # The published check value for CRC-16/XMODEM. If this drifts, every frame
    # we send is silently dropped by the board and it looks like bad wiring.
    assert crc16(b"123456789") == 0x31C3, hex(crc16(b"123456789"))
    assert crc16(b"") == 0

    cmd = pack_cmd(250, -100)
    assert len(cmd) == 9, len(cmd)
    assert cmd[0] == START_TX
    assert struct.unpack("<H", cmd[-2:])[0] == crc16(cmd[:-2])
    assert struct.unpack("<hh", cmd[1:5]) == (250, -100)

    body = struct.pack("<HhhHhhii", START_RX, -123, 456, 3980, -150, 275,
                       -100000, 200000)
    frame = body + struct.pack("<H", crc16(body))
    assert len(frame) == 22, len(frame)
    d = parse_frame(frame)
    assert d is not None
    assert abs(d["speedL"] + 1.23) < 1e-9 and abs(d["speedR"] - 4.56) < 1e-9
    assert abs(d["volt"] - 39.80) < 1e-9
    assert d["odomL"] == -100000 and d["odomR"] == 200000

    bad = bytearray(frame); bad[5] ^= 0xFF
    assert parse_frame(bytes(bad)) is None, "corrupted frame must be rejected"
    assert parse_frame(frame[:-1]) is None, "short frame must be rejected"

    # Resync: the reader joins the stream mid-frame, so a valid frame preceded
    # by junk still has to be found.
    class FakeSer:
        def __init__(self, data): self.data = bytearray(data)
        def read(self, n):
            out, self.data = bytes(self.data[:n]), self.data[n:]
            return out
        def close(self): pass

    lk = Link()
    lk.ser = FakeSer(b"\x00\xcd\xff\xab" + frame)
    lk.stop.set()                       # one pass only
    lk.stop.clear()
    t = threading.Thread(target=lk._read, daemon=True); t.start()
    time.sleep(0.3); lk.stop.set(); t.join(timeout=1)
    kinds = []
    while not lk.q.empty():
        kinds.append(lk.q.get_nowait())
    assert any(k == "frame" for k, _ in kinds), kinds

    assert parse_limit("300", 200) == 300
    assert parse_limit("", 200) == 200, "empty field must keep the last value"
    assert parse_limit("3a", 150) == 150
    assert parse_limit("99999", 200) == SPEED_LIMIT
    assert parse_limit("-5", 200) == 0
    assert parse_limit("250.0", 200) == 250

    print("selftest OK")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    selftest() if a.selftest else run_gui()
