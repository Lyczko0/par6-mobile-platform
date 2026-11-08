// ############################################################################
//  nema23_bench.ino  -  bench control for ONE NEMA23 57BYG250B with brake
//
//  Teensy 4.1 + TMC5160 on the J1 slot of the PAROL6 control board.
//  NO ROS, no micro-ROS, no trajectory streaming. A line protocol over USB
//  serial and nothing else - this exists to spin one motor against a test
//  lever and log what happens.
//
//  PIN MAP is lifted verbatim from Lyczko0/Parol6-firmware (src/main.cpp,
//  src/sensors.cpp) so the same board runs both without rewiring. Only the
//  BRAKE line is new: the arm has no brakes, this motor does.
//
//  WHAT THIS IS NOT
//    Closed loop. The TMC5160 runs open loop; "position" below is commanded
//    steps, not measured shaft angle. If the motor skips, this firmware will
//    not know and will happily report the wrong number. That is exactly what
//    the lever test is meant to expose.
// ############################################################################

#include <Arduino.h>
#include <SPI.h>
#include <TMCStepper.h>
#include <AccelStepper.h>

// ---------------------------------------------------------------------------
//  PINS - same slot as J1 on the PAROL6 board
// ---------------------------------------------------------------------------
#define STEP_PIN   2        // J1_STEP
#define DIR_PIN    3        // J1_DIR
#define CS_PIN     6        // CS_J1  (hardware SPI: SCK 13, MOSI 11, MISO 12)

// J2 carries the only other TMC5160 on this board (J3-J6 are standalone
// STEP/DIR drivers). Its CS must be driven HIGH: left as a floating input it
// drifts low, that driver answers at the same time as J1, and the two fight
// over MISO. The symptom is that every other SPI read comes back as all zeros,
// which reads exactly like a dead driver.
#define CS_J2_PIN  8        // CS_J2 - deselected, never talked to
#define EN_PIN     15       // DRV_EN, shared by every driver, ACTIVE LOW
#define ESTOP_PIN  0        // ESTOP_BTN
#define V24_PIN    41       // A17, 22k/3.3k divider on the 24 V rail
#define LIMIT_PIN  31       // J1 inductive NPN. A lever has no limit - the pin is
                            // only driven to a defined state, never read.

// The brake coil is 24 V and is NOT on the arm board's schematic. SOL1 is a
// switched 24 V output (+24V_IN <-> SOL1_OUT) already sized for a solenoid, so
// the brake goes there. Check the coil current against that output before
// wiring it - a brake pulling more than the solenoid driver allows will cook
// the FET, and it will do it silently.                              [VERIFY]
#define BRAKE_PIN  23       // SOL1_PIN

// Brake is POWER-TO-RELEASE: pin HIGH = coil energised = shaft FREE.
// Getting this backwards drives the motor against a clamped brake.
#define BRAKE_RELEASED HIGH
#define BRAKE_CLAMPED  LOW

#define ESTOP_ACTIVE_HIGH 1

// ---------------------------------------------------------------------------
//  DRIVER + MECHANICS
// ---------------------------------------------------------------------------
#define R_SENSE 0.075f      // BTT TMC5160 module

// 57BYG250B is a 2.5 A/phase motor. rms_current() sets the coil RMS and the
// sine peak is rms * sqrt(2), so full rating = 2500/1.414 = 1768 mA rms.
// Starting there on a cold bench is how drivers die - start low, raise it from
// the app with CUR once the motor is bolted down and you are watching it.
const uint16_t CURRENT_DEFAULT_MA = 1200;
const uint16_t CURRENT_MAX_MA     = 1800;   // hard ceiling, see above

const float MICROSTEPS   = 16.0f;           // matches the arm firmware
const float FULLSTEPS    = 200.0f;          // 1.8 deg/step                [VERIFY]
const float GEAR_RATIO   = 1.0f;            // lever sits ON the shaft, no reduction
const float STEPS_PER_DEG = FULLSTEPS * MICROSTEPS * GEAR_RATIO / 360.0f;  // 8.888

// 24 V sense, same divider and thresholds as the arm firmware.
const float V24_DIVIDER  = (22.0f + 3.3f) / 3.3f;
const float V24_PRESENT  = 18.0f;
const float V24_ABSENT   = 12.0f;    // hysteresis, so a sagging rail does not chatter

// ---------------------------------------------------------------------------
//  BRAKE TIMING
//  A brake needs time to let go before the motor pushes, and the motor must
//  still be holding when the brake bites. Both delays are one-way safe: too
//  long only wastes time, too short breaks something.
// ---------------------------------------------------------------------------
const uint32_t BRAKE_RELEASE_MS = 120;   // energise -> shaft actually free  [VERIFY]
const uint32_t BRAKE_ENGAGE_MS  = 120;   // de-energise -> pads actually bite [VERIFY]
const uint32_t BRAKE_IDLE_MS    = 400;   // idle this long -> clamp again

// ---------------------------------------------------------------------------
//  STATE
// ---------------------------------------------------------------------------
TMC5160Stepper driver(CS_PIN, R_SENSE);
AccelStepper   stepper(AccelStepper::DRIVER, STEP_PIN, DIR_PIN);

bool     drv_enabled   = false;
bool     brake_free    = false;     // true = released
bool     brake_manual  = false;     // BRK command wins until the next move
uint32_t brake_changed = 0;
uint32_t idle_since    = 0;
bool     estop_latched = false;
uint16_t current_ma    = CURRENT_DEFAULT_MA;

// The TMC5160 only answers SPI once VM (24 V) is up. A config written before
// that lands nowhere and stays lost - the chip keeps TOFF=0, the output stage
// never turns on, and the shaft is free however hard you press ENABLE. So the
// full config waits for VM, exactly like update_tmc_power() in the arm
// firmware. That is why the USB/PSU order does not matter there.
enum TmcState { TMC_WAIT_VM, TMC_READY };
TmcState tmc_state = TMC_WAIT_VM;
uint32_t vm_since  = 0;
const uint32_t VM_SETTLE_MS = 300;

// Cycle mode: +angle, dwell, -angle, dwell, repeat.
enum CycPhase { CYC_OFF, CYC_FWD, CYC_DWELL_A, CYC_BACK, CYC_DWELL_B };
CycPhase cyc_phase   = CYC_OFF;
long     cyc_steps   = 0;           // amplitude in steps
uint32_t cyc_dwell   = 300;
long     cyc_target  = 0;           // 0 = forever
long     cyc_done    = 0;
uint32_t cyc_mark    = 0;
long     cyc_origin  = 0;           // position the cycle started from

uint32_t telem_last  = 0;
const uint32_t TELEM_MS = 20;

// ---------------------------------------------------------------------------
//  HELPERS
// ---------------------------------------------------------------------------
static float v24_read() {
    return (analogRead(V24_PIN) * 3.3f / 1023.0f) * V24_DIVIDER;
}

static bool estop_pressed() {
    int raw = digitalRead(ESTOP_PIN);
#if ESTOP_ACTIVE_HIGH
    return raw == HIGH;
#else
    return raw == LOW;
#endif
}

static void brake_set(bool release) {
    if (brake_free == release) return;
    brake_free = release;
    digitalWrite(BRAKE_PIN, release ? BRAKE_RELEASED : BRAKE_CLAMPED);
    brake_changed = millis();
}

// True once the brake has had time to finish whatever it was asked to do.
static bool brake_settled() {
    uint32_t need = brake_free ? BRAKE_RELEASE_MS : BRAKE_ENGAGE_MS;
    return (millis() - brake_changed) >= need;
}

static void driver_enable(bool on) {
    drv_enabled = on;
    digitalWrite(EN_PIN, on ? LOW : HIGH);   // ACTIVE LOW
}

// TMC SPI is pipelined: the reply to a datagram carries the data asked for by
// the PREVIOUS datagram, so a single read hands back whatever was pending.
// Measured on this board: reading DRV_STATUS once gave a clean 50/50 split
// between the real value and all zeros over 100 samples - the signature of the
// pipeline, not of noise or bus contention. Asking twice and keeping the second
// answer is the protocol-level fix, not a workaround. Every read goes through
// one of these two helpers.
static uint32_t drv_status_read2() {
    driver.DRV_STATUS();
    return driver.DRV_STATUS();
}

static uint8_t driver_version() {
    driver.version();
    return driver.version();
}

static void init_TMC5160() {
    // TMCStepper defaults to 2 MHz. On a socketed module with ribbon-length
    // traces that is enough to hand back the odd all-zero datagram, which then
    // shows up as a phantom "driver dead" reading. 1 MHz costs nothing here -
    // the whole SPI traffic is one status register at 10 Hz.
    driver.setSPISpeed(1000000);
    driver.begin();
    delay(50);                       // internal reset after begin()

    driver.GSTAT(0b111);             // clear latched reset / drv_err / uv_cp
    driver.GCONF(driver.GCONF() & ~1UL);   // I_scale_analog off - no VREF on BTT

    driver.en_pwm_mode(true);        // stealthChop
    driver.pwm_autoscale(true);
    driver.pwm_autograd(true);
    driver.toff(8);
    driver.tbl(2);
    driver.hstrt(4);
    driver.hend(2);
    driver.microsteps((uint16_t)MICROSTEPS);
    driver.intpol(true);

    // The arm firmware sets diss2vs/diss2g TRUE because six drivers plus a
    // TMC2209 chopping next door produce false short alarms. On a bench with
    // ONE driver that noise source does not exist, so the protection stays ON.
    // If it trips for no reason with long motor leads, that is the first thing
    // to flip - and it is a real finding, not an annoyance.
    driver.diss2vs(false);
    driver.diss2g(false);

    driver.rms_current(current_ma);
}

// Configure the driver the moment VM has been up long enough, and forget the
// configuration again if VM goes away - a chip that lost its supply lost its
// registers with it.
static void update_tmc_power() {
    float v = v24_read();
    if (tmc_state == TMC_WAIT_VM) {
        if (v < V24_PRESENT) { vm_since = 0; return; }
        if (vm_since == 0) { vm_since = millis(); return; }
        if (millis() - vm_since < VM_SETTLE_MS) return;
        init_TMC5160();
        tmc_state = TMC_READY;
        Serial.print("I TMC configured, version=0x");
        Serial.print(driver_version(), HEX);
        Serial.print(" current=");
        Serial.println(driver.rms_current());
    } else if (v < V24_ABSENT) {
        driver_enable(false);
        brake_set(false);
        tmc_state = TMC_WAIT_VM;
        vm_since  = 0;
        Serial.println("! 24V LOST - driver off, brake clamped");
    }
}

// Stop everything, brake first, driver after. Order matters: dropping the
// coils and the brake at the same instant leaves the shaft free for the ~100 ms
// the pads take to bite.
static void panic(const char* why) {
    stepper.setCurrentPosition(stepper.currentPosition());   // kill any target
    cyc_phase = CYC_OFF;
    brake_set(false);
    delay(BRAKE_ENGAGE_MS);
    driver_enable(false);
    Serial.print("! ESTOP ");
    Serial.println(why);
}

// ---------------------------------------------------------------------------
//  MOTION REQUESTS
//  Everything that starts motion goes through here so the brake can never be
//  forgotten. Nothing else may call stepper.moveTo().
// ---------------------------------------------------------------------------
static bool motion_allowed() {
    if (estop_latched)         { Serial.println("! BLOCKED estop");   return false; }
    if (tmc_state != TMC_READY){ Serial.println("! BLOCKED no 24V");  return false; }
    if (!drv_enabled)          { Serial.println("! BLOCKED not enabled"); return false; }
    return true;
}

static void goto_steps(long target) {
    if (!motion_allowed()) return;
    brake_manual = false;             // a real move takes the brake back
    brake_set(true);
    stepper.moveTo(target);
    idle_since = 0;
}

static void goto_deg(float deg)   { goto_steps((long)lroundf(deg * STEPS_PER_DEG)); }
static void jog_deg(float deg)    { goto_steps(stepper.currentPosition()
                                               + (long)lroundf(deg * STEPS_PER_DEG)); }

// ---------------------------------------------------------------------------
//  COMMANDS
// ---------------------------------------------------------------------------
static void handle(char* line) {
    char* cmd = strtok(line, " ");
    if (!cmd) return;
    char* a1 = strtok(NULL, " ");
    char* a2 = strtok(NULL, " ");
    char* a3 = strtok(NULL, " ");

    if (!strcmp(cmd, "EN")) {
        bool on = a1 && atoi(a1);
        if (on && estop_latched) { Serial.println("! ESTOP LATCHED"); return; }
        if (on && tmc_state != TMC_READY) {
            // Enabling an unconfigured driver produces no torque and looks
            // exactly like a dead motor. Say so instead of pretending.
            Serial.println("! NO 24V - driver not configured, EN would do nothing");
            return;
        }
        driver_enable(on);
        if (!on) brake_set(false);
        Serial.print("K EN "); Serial.println(on);

    } else if (!strcmp(cmd, "BRK")) {
        // Manual override. It has to survive the idle auto-clamp below, or the
        // brake snaps shut 400 ms later and the command looks like it did
        // nothing. Cleared by the next real move.
        brake_manual = true;
        brake_set(a1 && atoi(a1));
        Serial.print("K BRK "); Serial.println(brake_free);

    } else if (!strcmp(cmd, "CUR")) {
        if (a1) {
            uint16_t ma = (uint16_t)atoi(a1);
            if (ma > CURRENT_MAX_MA) ma = CURRENT_MAX_MA;
            current_ma = ma;
            driver.rms_current(current_ma);
        }
        Serial.print("K CUR "); Serial.println(current_ma);

    } else if (!strcmp(cmd, "V")) {
        if (a1) stepper.setMaxSpeed(atof(a1) * STEPS_PER_DEG);
        Serial.print("K V "); Serial.println(stepper.maxSpeed() / STEPS_PER_DEG);

    } else if (!strcmp(cmd, "A")) {
        if (a1) stepper.setAcceleration(atof(a1) * STEPS_PER_DEG);
        Serial.print("K A "); Serial.println(a1 ? atof(a1) : 0.0f);

    } else if (!strcmp(cmd, "J")) {
        if (a1) jog_deg(atof(a1));

    } else if (!strcmp(cmd, "G")) {
        if (a1) goto_deg(atof(a1));

    } else if (!strcmp(cmd, "Z")) {
        stepper.setCurrentPosition(0);
        cyc_origin = 0;
        Serial.println("K Z");

    } else if (!strcmp(cmd, "S")) {
        cyc_phase = CYC_OFF;
        stepper.stop();                       // decelerate, coils keep holding
        Serial.println("K S");

    } else if (!strcmp(cmd, "X")) {
        estop_latched = true;
        panic("cmd");

    } else if (!strcmp(cmd, "CLR")) {
        if (estop_pressed()) { Serial.println("! ESTOP STILL PRESSED"); return; }
        estop_latched = false;
        Serial.println("K CLR");

    } else if (!strcmp(cmd, "CYC")) {
        // CYC <deg> <dwell_ms> <cycles>   cycles 0 = forever
        if (!a1) { Serial.println("! CYC needs deg"); return; }
        cyc_steps  = (long)lroundf(atof(a1) * STEPS_PER_DEG);
        cyc_dwell  = a2 ? (uint32_t)atol(a2) : 300;
        cyc_target = a3 ? atol(a3) : 0;
        cyc_done   = 0;
        cyc_origin = stepper.currentPosition();
        if (!motion_allowed()) { Serial.println("! BLOCKED"); return; }
        cyc_phase  = CYC_FWD;
        goto_steps(cyc_origin + cyc_steps);
        Serial.println("K CYC");

    } else if (!strcmp(cmd, "CYC0")) {
        cyc_phase = CYC_OFF;
        stepper.stop();
        Serial.println("K CYC0");

    } else if (!strcmp(cmd, "?")) {
        Serial.print("I nema23_bench spd=");   Serial.print(STEPS_PER_DEG);
        Serial.print(" cur=");                 Serial.print(current_ma);
        Serial.print(" en=");                  Serial.print(drv_enabled);
        Serial.print(" brk=");                 Serial.print(brake_free);
        Serial.print(" v24=");                 Serial.print(v24_read(), 1);
        Serial.print(" tmc=");                 Serial.print(tmc_state == TMC_READY
                                                            ? "READY" : "WAIT_VM");
        Serial.print(" ver=");                 Serial.println(driver_version(), HEX);

    } else {
        Serial.print("! UNKNOWN "); Serial.println(cmd);
    }
}

// ---------------------------------------------------------------------------
//  CYCLE STATE MACHINE
// ---------------------------------------------------------------------------
static void cycle_tick() {
    if (cyc_phase == CYC_OFF) return;
    if (stepper.distanceToGo() != 0) return;      // still travelling

    switch (cyc_phase) {
        case CYC_FWD:
            cyc_phase = CYC_DWELL_A;
            cyc_mark  = millis();
            break;
        case CYC_DWELL_A:
            if (millis() - cyc_mark < cyc_dwell) return;
            cyc_phase = CYC_BACK;
            goto_steps(cyc_origin);
            break;
        case CYC_BACK:
            cyc_phase = CYC_DWELL_B;
            cyc_mark  = millis();
            break;
        case CYC_DWELL_B:
            if (millis() - cyc_mark < cyc_dwell) return;
            cyc_done++;
            if (cyc_target > 0 && cyc_done >= cyc_target) {
                cyc_phase = CYC_OFF;
                Serial.print("K CYCDONE "); Serial.println(cyc_done);
                return;
            }
            cyc_phase = CYC_FWD;
            goto_steps(cyc_origin + cyc_steps);
            break;
        default: break;
    }
}

// ---------------------------------------------------------------------------
//  TELEMETRY
//  One CSV line, parsed by motor_console.py. Keep it short - this runs in the
//  same loop that generates step pulses.
//
//  In stealthChop SG_RESULT is meaningless, so the load proxy is
//  PWM_SCALE_SUM: the amplitude the autoscaler settled on, which climbs with
//  torque. That is the trace worth plotting during a lever test.
// ---------------------------------------------------------------------------
// DRV_STATUS is a status register, not a signal - polling it at the 50 Hz
// telemetry rate buys nothing and puts an SPI transaction inside every single
// telemetry cycle. Read it at 10 Hz and reuse the value in between.
uint32_t drv_status_cache = 0;
uint32_t drv_status_read  = 0;

static void telemetry() {
    if (tmc_state == TMC_READY && millis() - drv_status_read >= 100) {
        drv_status_read  = millis();
        drv_status_cache = drv_status_read2();
    }
    uint32_t st = drv_status_cache;
    Serial.print("T,");
    Serial.print(millis());                                    Serial.print(',');
    Serial.print(stepper.currentPosition() / STEPS_PER_DEG, 3); Serial.print(',');
    Serial.print(stepper.speed() / STEPS_PER_DEG, 2);           Serial.print(',');
    Serial.print(stepper.targetPosition() / STEPS_PER_DEG, 3);  Serial.print(',');
    Serial.print(driver.pwm_scale_sum());                       Serial.print(',');
    Serial.print(st, HEX);                                      Serial.print(',');
    Serial.print(v24_read(), 2);                                Serial.print(',');
    Serial.print(drv_enabled);                                  Serial.print(',');
    Serial.print(brake_free);                                   Serial.print(',');
    Serial.print(estop_latched);                                Serial.print(',');
    Serial.println(cyc_done);
}

// ---------------------------------------------------------------------------
void setup() {
    Serial.begin(115200);            // USB CDC - the number is ignored

    pinMode(EN_PIN, OUTPUT);    digitalWrite(EN_PIN, HIGH);     // disabled
    pinMode(BRAKE_PIN, OUTPUT); digitalWrite(BRAKE_PIN, BRAKE_CLAMPED);
    // Same wiring as the arm firmware: NC contact to GND, internal pull-up.
    // Idle = LOW (contact closed), pressed OR broken wire = HIGH. Fail-safe,
    // which also means an UNWIRED button reads as pressed and latches at boot.
    // On a bench with no E-stop, jumper pin 0 to GND.
    pinMode(ESTOP_PIN, INPUT_PULLUP);
    pinMode(LIMIT_PIN, INPUT);
    analogReadResolution(10);

    // Deselect the other SPI chip BEFORE the bus is used for the first time.
    pinMode(CS_J2_PIN, OUTPUT); digitalWrite(CS_J2_PIN, HIGH);

    SPI.begin();
    driver.begin();          // SPI layer only. The real config waits for VM -
                             // see update_tmc_power().

    stepper.setMinPulseWidth(2);                 // TMC5160 needs ~100 ns, 2 us is safe
    // First rung of the ladder in control/z_drive.py: 300 deg/s = 50 rpm with a
    // 0.15 s ramp. Low enough that an open-loop stepper cannot miss it, high
    // enough to be worth watching. Climb from here, do not start higher.
    stepper.setMaxSpeed(300.0f * STEPS_PER_DEG);
    stepper.setAcceleration(2000.0f * STEPS_PER_DEG);

    brake_changed = millis();
    Serial.println("I ready");

    // Say it out loud rather than letting the console look dead. Without this
    // an unwired E-stop looks exactly like a broken firmware.
    if (estop_pressed()) {
        estop_latched = true;
        Serial.println("! ESTOP HIGH AT BOOT - button open or not wired "
                       "(jumper pin 0 to GND on a bench), then send CLR");
    }
}

void loop() {
    // 1. Hardware E-stop wins over everything.
    if (estop_pressed() && !estop_latched) {
        estop_latched = true;
        panic("button");
    }

    // 2. 24 V handshake - owns the whole driver configuration.
    update_tmc_power();

    // 3. Commands.
    static char buf[64];
    static uint8_t n = 0;
    while (Serial.available()) {
        char c = Serial.read();
        if (c == '\n' || c == '\r') {
            if (n) { buf[n] = 0; handle(buf); n = 0; }
        } else if (n < sizeof(buf) - 1) {
            buf[n++] = c;
        }
    }

    // 4. Steps. Held off until the brake has actually let go - AccelStepper
    //    would otherwise ramp against a clamped brake and lose the whole ramp.
    if (brake_free && brake_settled()) {
        stepper.run();
    }

    // 5. Cycle sequencer.
    cycle_tick();

    // 6. Re-clamp the brake after a spell of standing still. The coils keep
    //    holding, so this is belt AND braces, not a handover.
    if (stepper.distanceToGo() == 0 && cyc_phase == CYC_OFF) {
        if (idle_since == 0) idle_since = millis();
        if (!brake_manual && brake_free
            && (millis() - idle_since) > BRAKE_IDLE_MS) brake_set(false);
    } else {
        idle_since = 0;
    }

    // 7. Telemetry.
    if (millis() - telem_last >= TELEM_MS) {
        telem_last = millis();
        telemetry();
    }
}
