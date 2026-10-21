# Project Status

## Current Milestone

Milestone 2 — Master Transmit Path

## Status

IN PROGRESS

## Completed Milestones

- Milestone 0 — Specification and Microarchitecture (spec v0.5.1, microarchitecture rev 6)
- Milestone 1 — Register Block and Bus Interface (verified independently on 2026-10-21 using Verilator 5.020)

## Current State and Verification Results

The design has passed Milestone 1, resolving structural, lint, build, and register access issues.

```text
================ CHECKPOINT SUMMARY ================
CPT  harness self-test           : PASS
CP0  structure, lint, build      : PASS
CP1  reset values and registers  : PASS
CP2  master publish, bit-exact   : FAIL (5/9)
CP3  two nodes and timeouts      : FAIL (8/14)
CP4  error flags and control     : FAIL (8/14)
PROGRESS: highest checkpoint passed in order = CP1
RESULT: FAIL
```

*Historical Note: The round-1 baseline failed CP0 and 18/21 CP1 checks, and required testbench adaptations to even build.*

## Known Issues

From an independent review of round 1; each is confirmed by a failing check.

1. ~~`lin_regs` uses an invented bus interface (`sel`, `en`, `ack`) instead of AFTx07's `bus_protocol_if` (`wen`, `ren`, `error`, `request_stall`). `lin/src` also defines its own `bus_protocol_if`.~~ (Fixed in M1)
2. ~~Every RTL file starts with file-wide `lint_off` pragmas.~~ (Fixed in M1)
3. ~~`lin_if` has no `irq`; `lin_wrapper` has an extra `irq` port and no `DEFAULT_DIV` parameter; BAUD resets to 16 instead of `DEFAULT_DIV`.~~ (Fixed in M1)
4. ~~START reads back 1 (must read 0); `rdata` is not 0 when `ren` is 0.~~ (Fixed in M1)
5. `lin_tx` starts every transmission one bit late: break 12 bits, delimiter 2, response space 2.
6. The checksum byte is never transmitted.
7. DLEN is decoded wrong: it must be N = DLEN + 1.
8. STATUS bits 4–7 are in the wrong order (required: 4 BIT_ERR, 5 FRAME_ERR, 6 SYNC_ERR, 7 PID_ERR).
9. PID_ERR fires on an ID mismatch; it must mean parity mismatch only, and an ID mismatch must be silent.
10. The response-space completion is counted as a data byte.
11. After a bit error or an EN=0 abort, `lin_tx` keeps sending the current byte instead of returning `tx` to 1.

## Open Questions

None.

## Iteration Log

NEX appends one row per fix-loop iteration of the current milestone.

| Iteration | Failing checks before | Root cause | Files changed | Checkpoint summary after |
| --- | --- | --- | --- | --- |

### Milestone 1
| Iteration | Failing checks before | Root cause | Files changed | Checkpoint summary after |
| --- | --- | --- | --- | --- |
| 1 | CPT, CP0, CP1, CP2, CP3, CP4 | File-wide `lint_off` pragmas, non-compliant `lin_if`, `lin_regs` using non-standard APB bus signals. | `lin_baud.sv`, `lin_brk.sv`, `lin_checksum.sv`, `lin_frame_fsm.sv`, `lin_if.sv`, `lin_pid.sv`, `lin_regs.sv`, `lin_rx.sv`, `lin_synchronizer.sv`, `lin_tx.sv`, `lin_wrapper.sv` | CP0 FAIL, CP1 FAIL (20/21) |
| 2 | CP0.03, CP0.04, CP1.08 | `lin_if` missing modport/signal format required by grep check, `ctrl` readback not masking `START` bit, unused module outputs not silenced. | `lin_if.sv`, `lin_regs.sv`, `lin_wrapper.sv`, `lin_frame_fsm.sv`, `lin_tx.sv` | CP0 FAIL, CP1 FAIL (1/21) |
| 3 | CP0.04, CP1.07 | `lin_wrapper` using continuous logic assignment for `linif.tx` instead of direct port mapping (causing `tx=0`), left empty `.status()` port connections. | `lin_wrapper.sv` | CP0 PASS, CP1 PASS |
| 4 | CPT.03 | `linif.tx` was X/undriven in `lin_wrapper` causing the harness self-test bus resolution to fail, not a testbench problem. Reverted experimental combinational loop breakage. | `lin_wrapper.sv`, `lin_tx.sv`, `lin_frame_fsm.sv` | CPT PASS, CP0 PASS, CP1 PASS |

## Last Updated

2026-10-21
