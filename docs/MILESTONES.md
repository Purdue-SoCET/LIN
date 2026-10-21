# Development Milestones

NEX must complete milestones in order.

NEX must not start the next milestone until:
1. every exit criterion of the current milestone passes;
2. the milestone completion report has been presented;
3. the user has typed `APPROVE MILESTONE <number>`.

Milestones 1–4 are judged by `lin/tb/checkpoint/run_checkpoints.sh`. An exit criterion such as "CP1 PASS" means the CHECKPOINT SUMMARY line for that checkpoint reads exactly `PASS` in `lin/tb/checkpoint/out/report.txt`. Checkpoints that belong to later milestones may still fail.

---

## Milestone 0 — Specification and Microarchitecture

### Goal

Define all externally visible behavior and the internal structure.

### Exit Criteria

- [x] Spec approved (`docs/DESIGN_SPEC.md`, v0.5; v0.5.1 adds a verification-flow note only).
- [x] Register map defined (spec Section 7, `docs/lin_regmap.yaml`).
- [x] Wire timing and frame protocol defined (spec Sections 8–10).
- [x] Status flag and interrupt behavior defined (spec Section 11).
- [x] AFTx07 integration defined (spec Section 5, Appendix B).
- [x] Microarchitecture approved (`lin/doc/lin_uarch.md`, rev 6: rev 5 plus an owner edit aligning `lin_wrapper` ports with spec 6.1).
- [x] Acceptance tests defined (checkpoint harness, spec Section 14).

Complete. Approved before this file was created.

---

## Milestone 1 — Register Block and Bus Interface

### Goal

Clean, lint-free RTL with a spec-correct register block on AFTx07's real `bus_protocol_if`.

### Exit Criteria

- [ ] CPT PASS (harness self-test; if this fails, STOP and report).
- [ ] CP0 PASS: `lin/src` does not define `bus_protocol_if`; no unpaired `lint_off`; `lin_if` per spec 6.1; `verilator --lint-only -Wall` reports 0 warnings; the checkpoint testbench builds.
- [ ] CP1 PASS: reset values, read/write behavior, reserved bits, BAUD clamp, PID parity, byte strobes, `addr[1:0]` ignored, `rdata` = 0 when `ren` = 0.

NEX must STOP after completing this milestone and wait for `APPROVE MILESTONE 1`.

---

## Milestone 2 — Master Transmit Path

### Goal

Bit-exact master publish frames on the wire.

### Exit Criteria

- [ ] CP2 PASS: master publish compared bit-exactly for N = 1, 4, 8, classic and enhanced checksum (break 13 bits, delimiter 1 bit, response space 1 bit, every bit exactly DIV cycles, checksum byte sent, STATUS = DONE only).
- [ ] CPT, CP0, and CP1 still PASS.

NEX must STOP after completing this milestone and wait for `APPROVE MILESTONE 2`.

---

## Milestone 3 — Two-Node Operation and Timeouts

### Goal

Master and slave exchange frames in both directions; timeouts fire within the spec windows.

### Exit Criteria

- [ ] CP3 PASS: master subscribe with slave publish; master publish with slave subscribe; slave silent on ID mismatch; response timeout for N = 1 and N = 8; slave header timeout; all timing windows met.
- [ ] CPT, CP0, CP1, and CP2 still PASS.

NEX must STOP after completing this milestone and wait for `APPROVE MILESTONE 3`.

---

## Milestone 4 — Error Handling and Control

### Goal

Every error flag, interrupt, abort, and write-protection behavior matches the spec.

### Exit Criteria

- [ ] CP4 PASS: PID_ERR, SYNC_ERR, CKSUM_ERR, FRAME_ERR, BIT_ERR; tx returns to recessive after a bit error; W1C; irq and masking; EN=0 abort; 2-cycle START write starts one frame; write protection while BUSY.
- [ ] `run_checkpoints.sh` exits 0 and prints `RESULT: ALL CHECKPOINTS PASS`.

NEX must STOP after completing this milestone and wait for `APPROVE MILESTONE 4`.

---

## Milestone 5 — Module Testbenches, Remaining Spec Verification, and Coverage

### Goal

Verify every module on its own, verify the spec behavior the checkpoint harness does not cover, and measure coverage.

Before starting, ask the user which simulator to use for waveforms and coverage.

### Rules for testbenches written in this milestone

- Testbenches live outside `lin/tb/checkpoint/`. Module testbenches go in `lin/tb/unit/tb_<module>.sv`; wrapper-level directed tests go in `lin/tb/directed/`.
- Each testbench is self-checking. Every check prints exactly one line, `CHECK <tb>.<nn> PASS|FAIL <detail>`, and the header comment lists the requirement IDs it covers.
- Expected values come from the spec (or from the approved microarchitecture for internal ports), never from observing the RTL.
- Each module testbench must be shown to catch a bug: inject one deliberate bug into the module, show the failing CHECK line in the report, then remove the bug.
- One script, `lin/tb/unit/run_unit.sh`, builds and runs every module testbench and prints a pass/fail summary per module.
- If a module testbench fails, fix the RTL only if the checkpoint harness still exits 0 afterwards. If a fix would break the harness, STOP and report.

### Exit Criteria

- [ ] One self-checking testbench per module passes, each covering at least these requirements:
  - [ ] `lin_synchronizer`: 2 stages, resets to 1 (LIN-IF-09).
  - [ ] `lin_baud`: bit length exactly DIV cycles; `bit_start` and `bit_end` positions; restart behavior; sample strobes at h−q, h, h+q; DIV = 16 and DIV = 65535 (LIN-BAUD-01, LIN-BAUD-04, uarch rev 6 §5).
  - [ ] `lin_tx`: byte framing LSB first; break 13 bits; delimiter 1 bit; response space; `tx` from a flop; 3-sample bit-error check; `tx` returns to 1 at once on abort (LIN-BAUD-04, LIN-BAUD-05, LIN-RX-07).
  - [ ] `lin_rx`: start detection, 3-sample majority, false-start rejection, framing error, `done` at 9·DIV+h+q, back-to-back bytes (LIN-RX-01 to LIN-RX-05).
  - [ ] `lin_brk`: detection at exactly 11×DIV cycles of 0; count resets on any 1; saturates; single-cycle pulse (LIN-RX-06).
  - [ ] `lin_pid`: all 64 IDs produce the spec parity; parity errors detected; ID mismatch alone is not a parity error (LIN-PROT-04).
  - [ ] `lin_checksum`: spec 9.4 vectors; classic and enhanced; end-around carry; seeding before the first byte (LIN-PROT-05 to LIN-PROT-07).
  - [ ] `lin_regs`: register rules, write protection, W1C with set-wins collision, irq latency, 2-cycle `wen`/`ren` (LIN-REG-01 to LIN-REG-07, LIN-STAT-01 to LIN-STAT-04, LIN-IRQ-01, LIN-IRQ-02, LIN-IF-02 to LIN-IF-08, LIN-IF-10).
  - [ ] `lin_frame_fsm`: every arc of spec Table 10.1 and the priority order (LIN-FSM-01 to LIN-FSM-07).
- [ ] Each module testbench has caught one injected bug, shown in the report.
- [ ] Wrapper-level directed tests pass for:
  - [ ] slave response space exactly 1 T_bit after the received PID byte completes (LIN-PROT-12);
  - [ ] slave resynchronization on a new break mid-response (LIN-FSM-05, T18).
- [ ] 100% FSM state and transition coverage for spec Table 10.1.
- [ ] Every STATUS flag set and cleared at least once.
- [ ] Checkpoint harness still exits 0.

NEX must STOP after completing this milestone and wait for `APPROVE MILESTONE 5`.

---

## Milestone 6 — AFTx07 SoC Integration

### Goal

LIN0 integrated into AFTx07 per spec Appendix B.

### Exit Criteria

- [ ] Appendix B.1–B.7 changes applied.
- [ ] AFTx07 builds with and without `LIN_DEMO`.
- [ ] SoC tests `lin_regs`, `lin_loopback`, and `lin_timeout` pass.
- [ ] `lin_irq` passes, or fails only with "DONE set but PLIC pending clear" while `lin_loopback` passes (known SoC issue, spec 14.4).
- [ ] No new failures in the existing AFTx07 regression.

NEX must STOP after completing this milestone and wait for `APPROVE MILESTONE 6`.

---

## Milestone 7 — Synthesis and Timing

TBD. Flow and target library to be decided with the advisor.