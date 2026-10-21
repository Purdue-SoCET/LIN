# AFTx07 LIN Controller — NEX Instructions

## Purpose

This repository implements a LIN bus controller peripheral for the AFTx07 RISC-V SoC (Purdue SoCET). It is an educational and research RTL project.

NEX must behave as a disciplined hardware engineer working under review. Correctness, explainability, verification evidence, and incremental progress matter more than producing RTL quickly.

---

# Required Project Context

At the start of every session, before any design work, read:

- `docs/DESIGN_SPEC.md`: the normative spec (v0.5.1). Requirement IDs look like `LIN-REG-04`.
- `lin/doc/lin_uarch.md`: the approved microarchitecture (rev 6), including the connection table.
- `docs/lin_regmap.yaml`: machine-readable register map; must agree with spec Section 7.
- `docs/MILESTONES.md`: milestones and exit criteria.
- `docs/STATUS.md`: current milestone, results, known issues, open questions.
- `lin/tb/checkpoint/README.md`: the checkpoint harness used as exit criteria.

Do not begin implementation until you understand the requirements and the current milestone.

If these documents disagree with each other, with the RTL, or with the tests, STOP and report the inconsistency. Do not silently choose which source to trust.

---

# Fundamental Engineering Rules

1. Do not invent requirements. Everything externally visible is defined in `docs/DESIGN_SPEC.md`.
2. Do not silently resolve ambiguous requirements.
3. Do not move to the next milestone until the current milestone's exit criteria pass and the user approves.
4. Do not claim functionality works without verification evidence (raw simulator output).
5. Do not modify a test solely to make failing RTL appear correct.
6. Do not bypass a failing requirement to continue to later work.
7. Prefer minimal, reviewable changes over large rewrites.
8. Preserve the interfaces fixed by the spec: `lin_wrapper` ports and `DEFAULT_DIV` parameter (spec 6.1), `lin_if` (spec 6.1), the register map (spec 7), and AFTx07's `bus_protocol_if` (spec Appendix B.8).
9. All RTL must be synthesizable SystemVerilog.
10. Reuse the project's existing build, simulation, and verification infrastructure.

---

# RTL Conventions (spec 13.1)

- Single clock domain: `CLK` = PCLK. `linif.rx` is the only asynchronous input and passes through `lin_synchronizer` first.
- Asynchronous active-low reset on every flop: `always_ff @(posedge CLK, negedge nRST)` with `if (!nRST)`.
- `always_ff` for sequential logic, `always_comb` for combinational logic. No latches, `initial` blocks, `#` delays, X assignments, or `defparam` in RTL.
- `linif.tx`, `linif.tx_en`, and `linif.irq` are driven directly from flops.
- One module per file; file name = module name; snake_case. Helper modules use a `lin_` prefix (`lin_synchronizer`, `lin_flex_counter`, …).
- `lin/src` must not define `bus_protocol_if`; it comes from the AFTx07 repo (a stub for standalone simulation lives in `lin/tb/checkpoint/`).
- No file-wide `lint_off`. A waiver covers one construct, is paired with `lint_on`, and carries a one-line reason.

---

# Uncertainty and Questions

When an unresolved question could materially affect any of the following, STOP and ask the user before proceeding:

- register map, access types, or reset values;
- bus interface behavior (`wen`/`ren` timing, `rdata`, strobes);
- LIN wire timing (break, delimiter, bit length, response space, inter-byte space);
- frame protocol behavior in master or slave mode;
- STATUS flag set/clear rules or interrupt behavior;
- timer and timeout behavior;
- reset behavior or clocking;
- AFTx07 integration (address, IO mux pins, PLIC source);
- verification acceptance criteria.

Do not guess just because one implementation seems conventional.

When asking:

1. State exactly what is ambiguous.
2. Explain why the answer affects the design.
3. Give the reasonable alternatives.
4. State your recommended choice and why.
5. Wait for the answer before implementing anything that depends on it.

Minor implementation choices that do not change externally visible behavior may be made autonomously, but must be documented in the milestone report.

---

# Milestone Gating

Development is milestone-driven. For every milestone:

1. Read its exit criteria in `docs/MILESTONES.md`.
2. Inspect the existing implementation before modifying it.
3. Implement only what the current milestone requires.
4. Run the milestone's required verification.
5. Investigate every failure.
6. Re-run verification after each fix.
7. Update `docs/STATUS.md` with objective evidence.
8. Present a milestone completion report.
9. STOP and wait for explicit approval before starting the next milestone.

Never interpret apparent success as permission to continue.

A valid approval is: `APPROVE MILESTONE <number>`

Without it, remain at the current milestone.

---

# Checkpoint Harness and Fix Loop

Milestones 1–4 are judged by the checkpoint harness in `lin/tb/checkpoint/`.

Run it with:

    lin/tb/checkpoint/run_checkpoints.sh

| Exit code | Meaning | Action |
| --- | --- | --- |
| 0 | All checkpoints pass | Report |
| 1 | Some checkpoint fails | Continue the fix loop |
| 2 | Harness modified or its self-test failed | STOP and report; not an RTL problem |

The harness is read-only. Never edit, rename, or regenerate any file in `lin/tb/checkpoint/`; `MANIFEST.sha256` is checked on every run and re-verified independently by the user.

Fix loop for the current milestone:

1. Run the harness.
2. If every checkpoint listed in the current milestone's exit criteria passes, stop the loop and write the milestone report. Checkpoints belonging to later milestones may still fail; do not work on them.
3. Otherwise, take the lowest-numbered failing check that belongs to the current milestone. Find the root cause in `lin/src/` (see Debugging Rules), fix it, and run again.
4. After each run, append one row to the Iteration Log in `docs/STATUS.md`: iteration number, failing checks before, root cause, files changed, checkpoint summary after.

Stop the loop and report instead of continuing when:

- 15 iterations have run in this milestone;
- the same CHECK line has failed in 3 consecutive iterations;
- a fix would require changing the spec, the approved microarchitecture, or the harness;
- you believe a check contradicts the spec. Report the check ID, the spec section, and waveform or log evidence. Do not change correct RTL to satisfy a check you believe is wrong.

Never add logic that detects the testbench or behaves differently in simulation.

---

# Milestone Completion Report

At the end of every milestone, report:

## Milestone
Name and number.

## Implemented
Modules and functionality added or changed.

## Verification Evidence
Tests run and their results. For milestones 1–4, paste the CHECKPOINT SUMMARY block from `lin/tb/checkpoint/out/report.txt` verbatim.

## Iteration Log
Number of fix-loop iterations and a one-line summary of each.

## Remaining Issues
Warnings, incomplete behavior, TODOs, or known risks.

## Files Changed
List every modified file.

## Design Decisions
Important implementation choices made autonomously.

## Open Questions
Anything requiring user input.

## Exit Criteria
For every exit criterion of the milestone, report PASS, FAIL, or NOT TESTED.

Do not declare the milestone complete if any criterion is FAIL or NOT TESTED.

After presenting this report, STOP.

---

# Debugging Rules

When a check or test fails:

1. Reproduce the failure.
2. Preserve the failing evidence (the CHECK line and logs).
3. Determine where expected and observed behavior diverge. Use waveforms when the console output does not explain it.
4. Identify the root cause before changing RTL.
5. Explain the proposed fix.
6. Implement the smallest reasonable fix.
7. Re-run the failing check.
8. Re-run the full harness to confirm earlier checkpoints still pass.

Do not randomly modify RTL until a check passes.

---

# Verification Rules

Simulation results are the source of truth for functional claims. Compilation or lint success alone does not establish correctness.

For every meaningful feature: a directed check, stated expected behavior, edge conditions, simultaneous-event cases where relevant, reset behavior, and a regression run after changes.

---

# Git and Workspace Rules

Before significant changes, inspect `git status` and understand any uncommitted work.

Do not commit automatically. Do not delete unrelated files.

After a milestone, inspect `git diff`, summarize modified files, and identify unintended changes.

---

# Scope Discipline

Work only on the current milestone unless the user explicitly says otherwise.

If the current milestone reveals that a later decision must be made now, STOP and ask.

---

# Priority Order

When instructions conflict:

1. Explicit instructions from the user in the current session
2. `docs/DESIGN_SPEC.md`
3. `lin/doc/lin_uarch.md`
4. `docs/MILESTONES.md`
5. This `NEX.md`
6. Existing implementation conventions

If a conflict is significant or unclear, STOP and ask.

---

# Tool and Environment

Do not silently choose between EDA tools, versions, simulators, or flows.

- The checkpoint harness runs on Verilator 5 or newer (tested with 5.020). Use it as provided.
- If Verilator is not available in this environment, STOP and report it. Do not port the harness to another simulator, and do not switch simulators, without the user's approval.
- Waveform debugging and coverage (milestone 5) use a simulator the user names. Until then, ask before using one.
