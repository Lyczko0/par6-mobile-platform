#!/usr/bin/env python3
"""RCB I/O budget for the mobile manipulator - single source of truth + self-check.

The RCB header is fully allocated by this design. Every pin below is either
claimed by the kernel, claimed by the RCB runtime, or claimed by us. There is
no spare. Run this file to prove the allocation has no conflicts:

    python control/pin_budget.py

Source of the board map: Source-Robotics/RCB-Runtime, docs/pin_map.md and
hardware/gpio_handler.py (fetched 2026-08-18). Do not edit BOARD from memory.
"""

# --- RCB board map -----------------------------------------------------------
# name -> (BCM, header pin, kind, note)
# kind: "iso_in" | "iso_out" | "gpio" | "estop" | "panel" | "reserved"
BOARD = {
    "ISO_IN_1":  (19, 35, "iso_in",   "connector 11, pull-down"),
    "ISO_IN_2":  (13, 33, "iso_in",   "connector 10, pull-down"),
    "ISO_IN_3":  ( 7, 26, "iso_in",   "connector 9, pull-down; also SPI0 CE1, freed by dtoverlay=spi0-1cs"),
    "ISO_OUT_1": (25, 22, "iso_out",  "connector 6"),
    "ISO_OUT_2": (24, 18, "iso_out",  "connector 7"),
    "ISO_OUT_3": (22, 15, "iso_out",  "connector 8"),
    "ESTOP_1":   ( 5, 29, "estop",    "terminals E2+E4, active-LOW, 5-sample debounce"),
    "ESTOP_2":   ( 6, 31, "estop",    "terminals E1+E3 - DEAD on v0 board, excluded in firmware"),
    "GPIO_1":    ( 4,  7, "gpio",     "user-configurable"),
    "GPIO_2":    (27, 13, "gpio",     "user-configurable"),
    "GPIO_3":    (18, 12, "gpio",     "user-configurable"),
    "GPIO_4":    (17, 11, "gpio",     "user-configurable"),
    "LED_1":     (16, 36, "panel",    "supervisor-owned"),
    "LED_2":     (20, 38, "panel",    "supervisor-owned"),
    "BTN_1":     (26, 37, "panel",    "supervisor-owned"),
    "BTN_2":     (21, 40, "panel",    "supervisor-owned"),
    "I2C_SDA":   ( 2,  3, "reserved", "OLED"),
    "I2C_SCL":   ( 3,  5, "reserved", "OLED"),
    "UART_TX":   (14,  8, "reserved", "onboard MCU link, /dev/ttyAMA0 @ 256000"),
    "UART_RX":   (15, 10, "reserved", "onboard MCU link"),
    "SPI0_MOSI": (10, 19, "reserved", "MCP2515"),
    "SPI0_MISO": ( 9, 21, "reserved", "MCP2515"),
    "SPI0_SCLK": (11, 23, "reserved", "MCP2515"),
    "SPI0_CE0":  ( 8, 24, "reserved", "MCP2515"),
    "CAN_INT":   (12, 32, "reserved", "MCP2515 interrupt"),
}

# --- our allocation ----------------------------------------------------------
# board pin name -> (signal, electrical note)
USE = {
    # Z axis driver: bit-banged SPI to TMC5160. The 5160 has an internal ramp
    # generator, so the Pi writes targets, not step pulses - no real-time
    # pulse train from Linux userspace. See CONTROL_ARCHITECTURE.md sec. 4.
    "GPIO_1":    ("TMC5160 SCK",  "3V3 logic"),
    "GPIO_2":    ("TMC5160 SDI",  "3V3 logic"),
    "GPIO_3":    ("TMC5160 SDO",  "3V3 logic"),
    "GPIO_4":    ("TMC5160 CSN",  "3V3 logic, idle high"),

    # Limit switches sit in the isolated 24 V loop, not on 3V3 logic.
    "ISO_IN_1":  ("Z limit low",  "24 V loop"),
    "ISO_IN_2":  ("Z limit high", "24 V loop"),
    "ISO_IN_3":  ("charger plugged in", "24 V loop; interlock - do not drive while charging"),

    # Isolated outputs are rated ~0.5 A [VERIFY for RCB]. Drive relays, not coils.
    "ISO_OUT_1": ("Z brake relay",        "24 V, power-to-release, relay coil"),
    "ISO_OUT_2": ("drive power relay",    "36 V contactor coil, in series with E-stop NC"),
    "ISO_OUT_3": ("road lights MOSFET",   "reused Manta LED strips"),

    "ESTOP_1":   ("E-stop read-back",     "read only - it does not switch anything"),
}

# Pins we must never claim.
FORBIDDEN = {"ESTOP_2"}


def check():
    seen_bcm = {}
    for name, (sig, _note) in USE.items():
        assert name in BOARD, f"{name}: not a pin on the RCB"
        assert name not in FORBIDDEN, f"{name}: forbidden ({BOARD[name][3]})"
        bcm, _hdr, kind, _n = BOARD[name]
        assert kind != "reserved", f"{name}: kernel-reserved, cannot be used for {sig}"
        assert kind != "panel", f"{name}: owned by the RCB supervisor, not free for {sig}"
        assert bcm not in seen_bcm, f"BCM {bcm} allocated twice: {seen_bcm[bcm]} and {sig}"
        seen_bcm[bcm] = sig

    # Category sanity: logic-level signals must not land on isolated I/O and
    # vice versa. Getting this wrong is a dead driver, not a compile error.
    for name, (sig, note) in USE.items():
        kind = BOARD[name][2]
        if "3V3" in note:
            assert kind == "gpio", f"{sig}: 3V3 logic cannot use an isolated {kind}"
        if "24 V loop" in note:
            assert kind == "iso_in", f"{sig}: 24 V loop needs an isolated input, got {kind}"

    free = [n for n, (_b, _h, k, _t) in BOARD.items()
            if k in ("iso_in", "iso_out", "gpio") and n not in USE]
    return free


def table():
    rows = []
    for name, (bcm, hdr, kind, note) in sorted(BOARD.items(), key=lambda kv: kv[1][0]):
        sig = USE.get(name, (None,))[0]
        owner = sig or ("-- FREE --" if kind in ("iso_in", "iso_out", "gpio")
                        else f"[{kind}] {note.split(',')[0]}")
        rows.append(f"  BCM {bcm:>2}  hdr {hdr:>2}  {name:<10} {owner}")
    return "\n".join(rows)


if __name__ == "__main__":
    free = check()
    print(table())
    print(f"\nallocated: {len(USE)}   free user I/O: {len(free)} {free}")
    print("OK - no conflicts")
