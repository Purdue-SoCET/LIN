# LIN checkpoint harness

A fixed, black-box test of `lin_wrapper` against spec v0.5. It only uses what the spec fixes: the `lin_wrapper` ports and parameter (spec 6.1), the register map (spec 7), and the bits on the LIN wire. Internal module structure is free to change.

## Run

```sh
lin/tb/checkpoint/run_checkpoints.sh          # tests lin/src
LIN_SRC=/other/src lin/tb/checkpoint/run_checkpoints.sh
```

Needs Verilator 5 or newer, bash, `sha256sum`, and `timeout`. Raw logs go to `lin/tb/checkpoint/out/`.

| Exit code | Meaning | What to do |
| --- | --- | --- |
| 0 | Every checkpoint passes | Done |
| 1 | At least one checkpoint fails | Fix RTL in `lin/src`, run again |
| 2 | Harness modified or its self-test failed | Stop and report; this is not an RTL problem |

## Checkpoints (in order)

| Checkpoint | Checks | Covers |
| --- | --- | --- |
| CPT | 3 | Harness self-test: PID and checksum math vs. spec 9.3/9.4; a testbench-driven frame passes the bit-exact comparator |
| CP0 | 5 | `lin/src` does not define `bus_protocol_if`; no unpaired `lint_off`; `lin_if` per spec 6.1; `verilator --lint-only -Wall` gives 0 warnings; testbench builds |
| CP1 | 21 | Reset values, read/write behavior, reserved bits, BAUD clamp, PID parity, byte strobes, `addr[1:0]` ignored, `rdata` = 0 when `ren` = 0 |
| CP2 | 9 | Master publish compared bit-exactly on the wire (break 208 cycles, delimiter 16, response space 16, every bit 16 cycles at DIV=16) for N = 1, 4, 8, classic and enhanced |
| CP3 | 14 | Two nodes: master subscribe/slave publish, master publish/slave subscribe, slave ID mismatch is silent; response timeout (N=1, N=8) and slave header timeout, with timing windows |
| CP4 | 14 | PID_ERR, SYNC_ERR, CKSUM_ERR, FRAME_ERR, BIT_ERR (via a testbench-driven node); W1C; irq and masking; EN=0 abort; 2-cycle START write; write protection while BUSY |

Every check prints one line: `CHECK <id> PASS|FAIL <detail>`. A missing line counts as a failure.

## Rules

- Do not edit any file in this directory. `MANIFEST.sha256` is checked on every run, and the owner re-checks it independently.
- If you believe a check contradicts the spec, stop and report the check ID, the spec section, and waveform evidence. Do not change the RTL to satisfy a check you believe is wrong.
- Not covered here, still required by spec 14.2: exact slave response-space timing, RX sample-point placement, W1C set-wins collision, slave resync on a mid-frame break, false-start rejection, multi-cycle `ren`.

## Bus model

Wired-AND of master `tx`, slave `tx`, and a testbench driver, fed back to both `rx` inputs through a 2-cycle loop delay (spec LIN-VER-01/02). Register accesses hold `wen` or `ren` for one cycle; `rdata` is sampled in the same cycle (LIN-IF-04).
