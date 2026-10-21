# AFTx07 LIN Controller

LIN bus controller peripheral for the AFTx07 RISC-V SoC (Purdue SoCET, VIP 47920).

| Path | Contents |
| --- | --- |
| `NEX.md` | Standing instructions for the NEX agent |
| `docs/DESIGN_SPEC.md` | Normative spec (v0.5.1), with `block_diagram.png` and `fsm_diagram.png` |
| `docs/lin_regmap.yaml` | Register map |
| `docs/MILESTONES.md` | Milestones and exit criteria |
| `docs/STATUS.md` | Current milestone, results, known issues, iteration log |
| `lin/doc/lin_uarch.md` | Approved microarchitecture |
| `lin/src/` | RTL |
| `lin/tb/checkpoint/` | Read-only acceptance harness (`run_checkpoints.sh`) |

Run the acceptance checks: `lin/tb/checkpoint/run_checkpoints.sh`
