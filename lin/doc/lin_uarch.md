# AFTx07 LIN Controller Microarchitecture

## 1. Module Hierarchy (rev 5)

The design follows the recommended partition in specification Section 13.3 without changes, as it cleanly separates protocol layers (timing, byte framing, FSM, and registers).

- `lin_wrapper`: Top-level module exposing the APB and LIN interfaces.
  - `u_sync`: `lin_synchronizer` - Synchronizes to synchronize the asynchronous `linif.rx` input.
  - `u_regs`: `lin_regs` - Handles APB bus decode, register storage, write protection, W1C with set-wins, and interrupt generation.
  - `u_fsm`: `lin_frame_fsm` - Implements the main frame FSM, byte counter, timers, and orchestrates flag-set pulses.
  - `u_baud`: `lin_baud` - The TX/timeout bit timer, generating `bit_start` and TX bit-error sample strobes.
  - `u_tx`: `lin_tx` - Byte and break/delimiter transmitter; registers `tx` and handles bit-error monitoring via 3-sample majority.
  - `u_rx`: `lin_rx` - Contains the dedicated RX sampling timer, handles start detection, 3-sample majority voting, stop check, and false-start rejection.
  - `u_brk`: `lin_brk` - Break detector (monitors synchronized `rx` for 11 dominant bits using its own counter).
  - `u_pid`: `lin_pid` - Combinational block for protected identifier parity generation and checking.
  - `u_checksum`: `lin_checksum` - Accumulator for classic and enhanced checksums with end-around carry and final inversion.

## 2. Port Tables (rev 5)

### `lin_wrapper`
(rev 6, owner edit: ports aligned with spec 6.1. `irq` is a member of `lin_if`, not a separate port, and `DEFAULT_DIV` is a parameter.)

| Name | Direction | Width | Reset | Description |
|---|---|---|---|---|
| `DEFAULT_DIV` | parameter | int unsigned | 521 | Reset value of BAUD.DIV (spec 6.1, LIN-REG-01) |
| `CLK` | input | 1 | - | PCLK (system clock) |
| `nRST` | input | 1 | - | Asynchronous active-low reset |
| `busif` | interface | - | - | APB peripheral interface (`bus_protocol_if.peripheral_vital`) |
| `linif` | interface | - | - | LIN physical layer interface (`lin_if.peripheral`): `rx` in; `tx`, `tx_en`, `irq` out |

### `lin_regs`
| Name | Direction | Width | Reset | Description |
|---|---|---|---|---|
| `CLK` | input | 1 | - | System clock |
| `nRST` | input | 1 | - | Asynchronous active-low reset |
| `busif` | interface | - | - | APB peripheral interface |
| `fsm_set_flags`| input | 8 | - | Hardware set pulses for status flags |
| `fsm_busy` | input | 1 | - | FSM busy status |
| `rx_data_wen` | input | 8 | - | Byte write enables for RXDATA (from FSM) |
| `rx_data_clr` | input | 1 | - | Clear RXDATA to 0 |
| `ctrl` | output | 32 | 0 | CTRL register (only defined fields are stored) |
| `status` | output | 32 | 0 | STATUS register (bits 7:1 are sticky) |
| `baud_div` | output | 16 | DEFAULT | BAUD.DIV register |
| `pid` | output | 32 | 0x80 | PID register (P0/P1 are purely combinational) |
| `tx_data0` | output | 32 | 0 | TXDATA0 register |
| `tx_data1` | output | 32 | 0 | TXDATA1 register |
| `irq_en` | output | 32 | 0 | IRQ_EN register |
| `irq` | output | 1 | 0 | Level-high interrupt output |
| `start_pending`| output | 1 | 0 | Registered start transmitter strobe |
| `rx_byte_in` | input | 8 | - | RX byte to write (from FSM) |

### `lin_frame_fsm`
| Name | Direction | Width | Reset | Description |
|---|---|---|---|---|
| `CLK` | input | 1 | - | System clock |
| `nRST` | input | 1 | - | Asynchronous active-low reset |
| `ctrl` | input | 32 | - | Control register from `lin_regs` |
| `baud_div` | input | 16 | - | BAUD.DIV |
| `pid` | input | 32 | - | PID register |
| `tx_data0` | input | 32 | - | TXDATA0 |
| `tx_data1` | input | 32 | - | TXDATA1 |
| `start_pending`| input | 1 | - | Registered start strobe from `lin_regs` |
| `rx_sync` | input | 1 | - | Synchronized rx from `lin_synchronizer` |
| `cksum_out` | input | 8 | - | Computed checksum from `lin_checksum` |
| `rx_byte` | input | 8 | - | Received byte from `lin_rx` |
| `rx_done` | input | 1 | - | Byte received strobe from `lin_rx` |
| `rx_stop_bit`| input | 1 | - | Stop bit value of received byte |
| `tx_done` | input | 1 | - | Transmit byte/break done strobe from `lin_tx` |
| `bit_err` | input | 1 | - | Bit error strobe from `lin_tx` |
| `break_det`| input | 1 | - | Break detected strobe from `lin_brk` |
| `pid_err` | input | 1 | - | PID parity error from `lin_pid` |
| `cksum_err`| input | 1 | - | Checksum error from `lin_checksum` |
| `bit_start` | input | 1 | - | TX timer tick from `lin_baud` |
| `bit_end` | input | 1 | - | Pulses when tx_timer == DIV-1 |
| `fsm_set_flags` | output | 8 | 0 | Pulses to set STATUS flags |
| `busy` | output | 1 | 0 | FSM busy status |
| `rx_data_wen` | output | 8 | 0 | RX byte write enables |
| `rx_data_clr` | output | 1 | 0 | Clear RXDATA |
| `rx_byte_out` | output | 8 | 0 | RX byte for RXDATA |
| `tx_byte` | output | 8 | 0 | Byte to transmit |
| `tx_start` | output | 1 | 0 | Start transmitter strobe |
| `tx_mode` | output | 2 | 0 | TX mode (0=byte, 1=break, 2=delim, 3=resp_space) |
| `tx_timer_rst`| output| 1 | 0 | Restart TX/timeout timer |
| `rx_en` | output | 1 | 0 | Enable `lin_rx` |
| `cksum_load_seed`| output| 1 | 0 | Load seed strobe to `lin_checksum` |
| `cksum_seed` | output | 8 | 0 | Seed value to `lin_checksum` |
| `cksum_accumulate`| output| 1 | 0 | Accumulate strobe to `lin_checksum` |
| `cksum_data` | output | 8 | 0 | Data byte to `lin_checksum` |

### `lin_baud` (TX/Timeout Timer)
| Name | Direction | Width | Reset | Description |
|---|---|---|---|---|
| `CLK` | input | 1 | - | System clock |
| `nRST` | input | 1 | - | Asynchronous active-low reset |
| `div` | input | 16 | - | Bit-time divider |
| `restart` | input | 1 | - | Restart timer from FSM |
| `bit_start` | output | 1 | 0 | Pulses when tx_timer == 0 |
| `bit_end`   | output | 1 | 0 | Pulses when tx_timer == DIV-1 |
| `sample_h_q`| output| 1 | 0 | Sample strobe at h - q |
| `sample_h` | output | 1 | 0 | Sample strobe at h |
| `sample_h_plus_q`| output| 1| 0| Sample strobe at h + q |

### `lin_tx`
| Name | Direction | Width | Reset | Description |
|---|---|---|---|---|
| `CLK` | input | 1 | - | System clock |
| `nRST` | input | 1 | - | Asynchronous active-low reset |
| `bit_start` | input | 1 | - | tx_timer == 0 from `lin_baud` |
| `bit_end` | input | 1 | - | tx_timer == DIV-1 from `lin_baud` |
| `restart` | input | 1 | - | TX timer restart from FSM |
| `sample_h_q`| input | 1 | - | Sample strobe h - q |
| `sample_h` | input | 1 | - | Sample strobe h |
| `sample_h_plus_q`| input| 1| - | Sample strobe h + q |
| `start` | input | 1 | - | Start transmission strobe |
| `mode` | input | 2 | - | 0=byte, 1=break, 2=delim, 3=resp_space |
| `data_in` | input | 8 | - | Byte to transmit |
| `rx_sync` | input | 1 | - | Synchronized rx for bit-error monitoring |
| `tx_out` | output | 1 | 1 | Transmit line |
| `done` | output | 1 | 0 | Transmission complete strobe |
| `bit_err` | output | 1 | 0 | Pulses if 3-sample majority of rx != tx |

### `lin_rx`
| Name | Direction | Width | Reset | Description |
|---|---|---|---|---|
| `CLK` | input | 1 | - | System clock |
| `nRST` | input | 1 | - | Asynchronous active-low reset |
| `div` | input | 16 | - | Bit-time divider |
| `rx_sync` | input | 1 | - | Synchronized rx |
| `enable` | input | 1 | - | Enable receiver, cleared by EN=0 or FSM abort |
| `data_out` | output | 8 | 0 | Received byte |
| `stop_bit` | output | 1 | 0 | Received stop bit |
| `done` | output | 1 | 0 | Byte received strobe |

### `lin_brk`
| Name | Direction | Width | Reset | Description |
|---|---|---|---|---|
| `CLK` | input | 1 | - | System clock |
| `nRST` | input | 1 | - | Asynchronous active-low reset |
| `div` | input | 16 | - | Bit-time divider |
| `rx_sync` | input | 1 | - | Synchronized rx |
| `break_det`| output | 1 | 0 | Break detected (11 continuous 0s) |

### `lin_pid`
| Name | Direction | Width | Reset | Description |
|---|---|---|---|---|
| `id_in` | input | 6 | - | ID to calculate parity for |
| `pid_in` | input | 8 | - | Received PID to check |
| `pid_out` | output | 8 | - | Computed PID (ID + parity) |
| `pid_err` | output | 1 | - | Parity mismatch flag |

### `lin_checksum`
| Name | Direction | Width | Reset | Description |
|---|---|---|---|---|
| `CLK` | input | 1 | - | System clock |
| `nRST` | input | 1 | - | Asynchronous active-low reset |
| `seed` | input | 8 | - | 0 (classic) or PID (enhanced) |
| `load_seed`| input | 1 | - | Load seed strobe |
| `data_in` | input | 8 | - | Data byte to accumulate |
| `accumulate`| input | 1 | - | Accumulate strobe |
| `rx_checksum_in`| input | 8 | - | Received checksum byte to compare |
| `cksum_err`| output | 1 | 0 | Status of rx checksum check |
| `cksum_out` | output | 8 | 0 | Computed checksum byte to transmit |


### Connection Table (rev 5)

| Signal Name | Width | Driver (Module.Port) | Receiver(s) (Module.Port) |
|---|---|---|---|
| `CLK` | 1 | `lin_wrapper.CLK` | All submodules |
| `nRST` | 1 | `lin_wrapper.nRST` | All submodules |
| `busif` | - | `lin_wrapper.busif` | `lin_regs.busif` |
| `linif.rx` | 1 | `lin_wrapper.linif` | `lin_synchronizer.async_in` |
| `linif.tx` | 1 | `lin_tx.tx_out` | `lin_wrapper.linif` |
| `linif.tx_en`| 1 | `lin_regs.tx_en` (from ctrl) | `lin_wrapper.linif` |
| `irq` | 1 | `lin_regs.irq` | `linif.irq` (rev 6) |
| `rx_sync` | 1 | `lin_synchronizer.sync_out` | `lin_frame_fsm.rx_sync`, `lin_tx.rx_sync`, `lin_rx.rx_sync`, `lin_brk.rx_sync` |
| `fsm_set_flags` | 8 | `lin_frame_fsm.fsm_set_flags` | `lin_regs.fsm_set_flags` |
| `fsm_busy` | 1 | `lin_frame_fsm.busy` | `lin_regs.fsm_busy` |
| `rx_data_wen` | 8 | `lin_frame_fsm.rx_data_wen` | `lin_regs.rx_data_wen` |
| `rx_data_clr` | 1 | `lin_frame_fsm.rx_data_clr` | `lin_regs.rx_data_clr` |
| `rx_byte_in` | 8 | `lin_frame_fsm.rx_byte_out` | `lin_regs.rx_byte_in` |
| `ctrl` | 32 | `lin_regs.ctrl` | `lin_frame_fsm.ctrl` |
| `baud_div` | 16 | `lin_regs.baud_div` | `lin_frame_fsm.baud_div`, `lin_baud.div`, `lin_rx.div`, `lin_brk.div` |
| `pid` | 32 | `lin_regs.pid` | `lin_frame_fsm.pid`, `lin_pid.id_in` (bits 5:0) |
| `tx_data0` | 32 | `lin_regs.tx_data0` | `lin_frame_fsm.tx_data0` |
| `tx_data1` | 32 | `lin_regs.tx_data1` | `lin_frame_fsm.tx_data1` |
| `start_pending` | 1 | `lin_regs.start_pending` | `lin_frame_fsm.start_pending` |
| `rx_byte` | 8 | `lin_rx.data_out` | `lin_frame_fsm.rx_byte`, `lin_pid.pid_in`, `lin_checksum.rx_checksum_in` |
| `rx_done` | 1 | `lin_rx.done` | `lin_frame_fsm.rx_done` |
| `rx_stop_bit` | 1 | `lin_rx.stop_bit` | `lin_frame_fsm.rx_stop_bit` |
| `tx_done` | 1 | `lin_tx.done` | `lin_frame_fsm.tx_done` |
| `bit_err` | 1 | `lin_tx.bit_err` | `lin_frame_fsm.bit_err` |
| `break_det` | 1 | `lin_brk.break_det` | `lin_frame_fsm.break_det` |
| `pid_err` | 1 | `lin_pid.pid_err` | `lin_frame_fsm.pid_err` |
| `cksum_err` | 1 | `lin_checksum.cksum_err` | `lin_frame_fsm.cksum_err` |
| `bit_start` | 1 | `lin_baud.bit_start` | `lin_frame_fsm.bit_start`, `lin_tx.bit_start` |
| `bit_end` | 1 | `lin_baud.bit_end` | `lin_frame_fsm.bit_end`, `lin_tx.bit_end` |
| `sample_h_q` | 1 | `lin_baud.sample_h_q` | `lin_tx.sample_h_q` |
| `sample_h` | 1 | `lin_baud.sample_h` | `lin_tx.sample_h` |
| `sample_h_plus_q`| 1 | `lin_baud.sample_h_plus_q`| `lin_tx.sample_h_plus_q` |
| `tx_byte` | 8 | `lin_frame_fsm.tx_byte` | `lin_tx.data_in` |
| `tx_start` | 1 | `lin_frame_fsm.tx_start` | `lin_tx.start` |
| `tx_mode` | 2 | `lin_frame_fsm.tx_mode` | `lin_tx.mode` |
| `tx_timer_rst`| 1 | `lin_frame_fsm.tx_timer_rst`| `lin_baud.restart`, `lin_tx.restart` |
| `rx_en` | 1 | `lin_frame_fsm.rx_en` | `lin_rx.enable` |
| `cksum_load_seed`| 1| `lin_frame_fsm.cksum_load_seed`| `lin_checksum.load_seed` |
| `cksum_seed` | 8 | `lin_frame_fsm.cksum_seed` | `lin_checksum.seed` |
| `cksum_accumulate`|1| `lin_frame_fsm.cksum_accumulate`| `lin_checksum.accumulate` |
| `cksum_data` | 8 | `lin_frame_fsm.cksum_data` | `lin_checksum.data_in` |
| `cksum_out` | 8 | `lin_checksum.cksum_out` | `lin_frame_fsm.cksum_out` |

## 3. Storage Inventory (rev 3)

| Register / Counter | Module | Width | Reset | Requirement IDs | Update Conditions |
|---|---|---|---|---|---|
| `ctrl.EN`, `MODE`, `TX_RESP`, `DLEN` | `lin_regs` | 7 | `0` | LIN-GEN-03, LIN-REG-02..04 | `ctrl.EN` uses `wen` masking without `wr_protect`; other fields use `~wr_protect` where `wr_protect = fsm_busy | start_pending`. Unused bits read 0, not stored. |
| `status[7:1]` | `lin_regs` | 7 | `0` | LIN-STAT-01..04, LIN-REG-04 | `w1c_en = wen & (addr == 0x04) & strobe[0]; status[7:1] <= (status[7:1] & ~(w1c_en ? wdata[7:1] : '0)) \| fsm_set_flags[7:1];` |
| `baud` | `lin_regs` | 16 | `DEFAULT_DIV` | LIN-BAUD-02, LIN-REG-04 | Let `next_baud` apply `strobe` masking to current `baud`. `if (wen && addr==0x08 && ~wr_protect) baud <= (next_baud < 16) ? 16 : next_baud;` |
| `pid.ID`, `CKSUM_TYPE`| `lin_regs` | 7 | `ID:0`, `CKSUM_TYPE:0`| LIN-PROT-04, LIN-REG-04 | `if (wen && addr==0x0C && ~wr_protect) ...` masked by `strobe`. `P0` and `P1` are derived combinationally. |
| `txdata0` | `lin_regs` | 32 | `0` | LIN-REG-04 | `if (wen && addr==0x10 && ~wr_protect)` applied per byte lane via `strobe`. |
| `txdata1` | `lin_regs` | 32 | `0` | LIN-REG-04 | `if (wen && addr==0x14 && ~wr_protect)` applied per byte lane via `strobe`. |
| `rxdata0`, `rxdata1`| `lin_regs` | 64 | `0` | LIN-REG-06 | `if (rx_data_clr) {rxdata1, rxdata0} <= 0; else for (i=0;i<8;i++) if (rx_data_wen[i]) rxdata[i] <= rx_byte_in;` |
| `irq_en[7:1]` | `lin_regs` | 7 | `0` | LIN-IRQ-01 | `if (wen && addr==0x20 && strobe[0]) irq_en[7:1] <= wdata[7:1];` |
| `irq` | `lin_regs` | 1 | `0` | LIN-IRQ-01, LIN-IRQ-02 | `irq <= \|(status[7:1] & irq_en[7:1]);` |
| `tx_timer` | `lin_baud` | 16 | `0` | LIN-RTL-09, LIN-BAUD-01 | `if (restart) tx_timer <= 0; else if (tx_timer == DIV-1) tx_timer <= 0; else tx_timer <= tx_timer + 1;` |
| `rx_timer` | `lin_rx` | 16 | `0` | LIN-RX-01 | Restarted on `rx_sync` falling edge (start bit). `if (restart_rx) rx_timer <= 0; else if (rx_timer == DIV-1) rx_timer <= 0; else rx_timer <= rx_timer + 1;` |
| `break_counter`| `lin_brk` | 20 | `0` | LIN-RTL-09, LIN-RX-06 | Increments when `rx_sync == 0`. Saturates at `11 * DIV`. Cleared to 0 when `rx_sync == 1`. `break_det` pulses for 1 cycle when count reaches threshold. |
| `response_timer`| `lin_frame_fsm`| 7 | `0` | LIN-RTL-09, LIN-PROT-08 | Increments on `bit_end`. `if (DATA_ENTRY) response_timer <= 0; else if (bit_end && response_timer < 14*(N+1)) response_timer <= response_timer + 1;` Saturates at threshold. |
| `header_timer`| `lin_frame_fsm`| 5 | `0` | LIN-RTL-09, LIN-PROT-09 | Increments on `bit_end`. `if (SYNC_ENTRY) header_timer <= 0; else if (bit_end && header_timer < 28) header_timer <= header_timer + 1;` Saturates at threshold. |
| `byte_counter`| `lin_frame_fsm`| 4 | `0` | LIN-REG-06 | `if (DATA_ENTRY) byte_counter <= 0; else if ((TX_RESP==1 && tx_done) || (TX_RESP==0 && rx_done)) byte_counter <= byte_counter + 1;` |
| `fsm_state` | `lin_frame_fsm`| 3 | `IDLE` | LIN-FSM-01 | Next-state logic per LIN-FSM-03..06. |
| `tx` | `lin_tx` | 1 | `1` | LIN-BAUD-05, LIN-RTL-06 | Shift register out or FSM mode out. |
| `tx_en` | `lin_regs` | 1 | `0` | LIN-RTL-06 | `tx_en <= ctrl.EN;` |

## 4. FSM Implementation (rev 4)

### State Encoding
```systemverilog
typedef enum logic [2:0] {IDLE=0, BREAK=1, DELIM=2, SYNC=3, PID=4, DATA=5, CKSUM=6, DONE=7} lin_state_t;
```

### Next-State Logic
Evaluated every cycle in the exact priority order from LIN-FSM-03 to LIN-FSM-06:
1. **Priority 1 (LIN-FSM-03):** If `CTRL.EN == 0`, `next_state = IDLE`.
2. **Priority 2 (LIN-FSM-04):** If `bit_err == 1`, `next_state = IDLE`.
3. **Priority 3 (LIN-FSM-05):** In Slave mode & (SYNC, PID, DATA, CKSUM): if `break_det == 1`, `next_state = DELIM`.
4. **Priority 4 (LIN-FSM-06 / Table 10.1):**
   - **IDLE**: to BREAK if Master & `(MODE==0 && start_pending)`; to DELIM if Slave & `break_det` & EN=1.
   - **BREAK**: to DELIM if Master & 13 T_bit elapsed.
   - **DELIM**: to SYNC if Master & 1 T_bit elapsed; to SYNC if Slave & `rx_sync == 1`.
   - **SYNC**: to PID if Master & byte sent, or Slave & `rx_byte == 0x55` & valid stop; to IDLE if Slave & (`rx_byte != 0x55` or bad stop) (sets SYNC_ERR); to IDLE if Slave header timer expired (sets TIMEOUT).
   - **PID**: to DATA if Master & byte sent, or Slave & valid stop & parity OK & ID match; to IDLE if Slave & bad stop (sets FRAME_ERR), or parity mismatch (sets PID_ERR), or header timer expired (sets TIMEOUT). To IDLE (silent) if parity OK but ID mismatch.
   - **DATA**: to CKSUM if byte N-1 completed; to IDLE if TX_RESP=0 & bad stop (sets FRAME_ERR), or TX_RESP=0 & response timer expired (sets TIMEOUT).
   - **CKSUM**: to DONE if TX & byte sent, or RX & checksum matches & valid stop; to IDLE if TX_RESP=0 & bad stop (sets FRAME_ERR), or RX & checksum mismatch (sets CKSUM_ERR), or response timer expired (sets TIMEOUT).
   - **DONE**: Unconditional to IDLE next cycle (sets DONE).

*(Conflict tie-breakers from LIN-FSM-06: byte completion wins over timer expiry; bad stop wins over sync/parity/ID/cksum checks; parity mismatch wins over ID mismatch.)*

### Moore Outputs per State
| State | `tx` Drive | Receiver Activity | Timers Active |
|---|---|---|---|
| IDLE | 1 | Break detector | None |
| BREAK | 0 | Bit-error monitor | TX Timer |
| DELIM | 1 | M: Bit-error, S: Wait rx=1 | M: TX Timer |
| SYNC | M: byte, S: 1 | M: Bit-error, S: RX byte | S: Header timer (from TX timer) |
| PID | M: byte, S: 1 | M: Bit-error, S: RX byte | S: Header timer (from TX timer) |
| DATA | M/S TX: bytes, else 1| M/S TX: Bit-error, else RX byte| RX: Response timer (from TX timer) |
| CKSUM | M/S TX: byte, else 1 | M/S TX: Bit-error, else RX byte| RX: Response timer (from TX timer) |
| DONE | 1 | None | None |

### Flag-Set Timing
Each STATUS flag-set pulse fires in the exact cycle the triggering event completes:
- `BIT_ERR`: Cycle where `tx` is driven but the 3-sample majority of `rx_sync` (at $h-q, h, h+q$) differs from `tx` (evaluated at `h+q` strobe of the TX timer).
- `FRAME_ERR`: Cycle where stop bit is sampled at 0 (evaluated at `h+q` strobe of the RX timer stop bit - LIN-RX-05).
- `SYNC_ERR`: Cycle where SYNC stop bit is sampled, if byte != 0x55 or stop bit is 0.
- `PID_ERR`: Cycle where PID stop bit is sampled, if parity fails.
- `TIMEOUT`: Cycle where the TX timer-based response/header timer reaches the expiry threshold limit.
- `CKSUM_ERR`: Cycle where CKSUM stop bit is sampled (at `h+q`), if checksum mismatch.
- `DONE`: Cycle when FSM transitions from DONE to IDLE.

## 5. Bit Timing (rev 4)

The design uses separated timers for TX and RX to prevent drifting and self-interference:
- **(a) TX/Timeout Timer (`lin_baud`):** Restarted exactly on the following FSM transitions: IDLE$->$BREAK, slave DELIM$->$SYNC, and PID$->$DATA. It is *never* restarted between back-to-back bytes or on DATA$->$CKSUM. A restart asserted in cycle `t` gives `tx_timer = 0` in cycle `t+1`. It provides two outputs: `bit_start = (tx_timer == 0)` and `bit_end = (tx_timer == DIV-1)`. The `tx` flip-flop loads the next bit value in any cycle where `(bit_end | restart)` is true, so the new bit is visible in the cycle where `tx_timer == 0`. This matches tables (a) and (c) and keeps `tx` driven directly from a flop (LIN-BAUD-05). The response and header timers increment only on `bit_end`, and their counters clear on the state entry that restarts the TX timer. Cycle accounting at a byte boundary: after 10 $T_{bit}$ of transmission, exactly $10 \times DIV$ cycles have elapsed. The next byte's start bit begins exactly on the next `bit_start`, maintaining exactly $DIV$ cycles per bit (LIN-BAUD-04).
- **(b) RX Sampling Timer (inside `lin_rx`):** Restarted on each falling edge of `rx_sync` that marks a valid start bit (LIN-RX-01). It generates internal sample strobes ($h-q, h, h+q$) for byte reception. Per LIN-RX-05, `done`, `data_out`, and `stop_bit` are valid precisely in the cycle of the $h+q$ stop-bit sample (offset $9 \cdot DIV + h + q$). The stop-bit majority is computed combinationally from the two registered earlier samples plus the current `rx_sync`.

**Bit-Error Monitoring:** `lin_tx` monitors `rx_sync` against the driven `tx` value using the 3-sample majority at $h-q, h, h+q$ of each driven bit (LIN-RX-07). It is excluded during the response space, checking only the frame fields listed in LIN-RX-07. It is timed entirely by the TX timer. The loop-delay tolerance is safely bounded by $h-q = DIV/2 - DIV/16 = 7 \cdot DIV/16$ cycles.

## 6. Register Block (rev 3)

- **Address Decode & Byte Strobes:** Write assignments are masked by `busif.strobe[3:0]`. Reserved bits are not stored and read back as 0 (LIN-REG-02). P0/P1 are derived directly from PID.ID and are not stored (LIN-PROT-04).
- **START Pulse Equation & Write Protection:**
  `start_set     = wen & (addr[5:2]==0) & strobe[0] & wdata[2] & wdata[0] & ~wdata[1] & ~(fsm_busy | start_pending);`
  `start_pending <= start_set;   // registered 1-cycle pulse, no other set/clear terms`
  `wr_protect    = fsm_busy | start_pending;   // used for BAUD, PID, TXDATA0/1, and CTRL fields other than EN`
  This registers the START pulse so the FSM takes IDLE$
rightarrow$BREAK when `start_pending=1` (with `CTRL.EN` and `MODE` already updated in that cycle). A 2-cycle `wen` hold produces one frame: `start_pending` goes high in cycle 2, safely masking the second write cycle's `start_set`.
- **W1C with Set-Wins:**
  `w1c_en = wen & (addr == 0x04) & strobe[0];`
  `status[7:1] <= (status[7:1] & ~(w1c_en ? wdata[7:1] : '0)) | fsm_set_flags[7:1];`
  Hardware set pulses explicitly take bitwise OR precedence over software clears in the same cycle (LIN-STAT-03).
- **Byte counting & Checksum Input:**
  - `byte_counter` counts `tx_done` when `TX_RESP=1` and `rx_done` when `TX_RESP=0`. Echoed bytes from `lin_rx` during transmission are completely ignored by the counter.
  - `RXDATA` is explicitly cleared upon DATA entry (`TX_RESP=0`), and bytes are written into it only when `TX_RESP=0` and state is DATA.
  - `lin_checksum` accumulates the transmitted byte when `TX_RESP=1` and the received byte when `TX_RESP=0` (excluding echoes). `cksum_err` is a combinational compare valid exactly in the cycle `rx_done` fires while in CKSUM state.
- **Response Space (LIN-PROT-12):**
  When `TX_RESP=1`, the first response start bit begins exactly 1 $T_{bit}$ after the PID byte completes. To implement this, when transitioning PID $
rightarrow$ DATA, the FSM restarts the TX timer. For a master publisher, this occurs at the end of its own PID stop bit. For a slave publisher, this occurs at the `lin_rx` byte completion of the PID byte (which happens at $h+q$ of the stop bit). The TX mode is set to `resp_space` (driving 1) for exactly 1 $T_{bit}$, after which byte 0 begins.
- **lin_rx Enable/Clear:** The FSM strictly enables `lin_rx` in specific states to wait for traffic. Master mode: SYNC, PID, DATA (if TX_RESP=0), CKSUM (if TX_RESP=0). Slave mode: DELIM, SYNC, PID, DATA, CKSUM. Idle states, aborts, and `CTRL.EN=0` leave it disabled.
- **lin_brk threshold:** `11 * DIV` is computed cleanly as `(DIV << 3) + (DIV << 1) + DIV`. `break_det` is a 1-cycle pulse firing when `break_counter == 11 * DIV`.

## 7. Cycle Tables (rev 4)

*(At `DIV=16`, $h=8$, $q=1$)*

**(a) TX of first 2 bits + stop bit & boundary**
| Cycle | `tx_timer` | `bit_start` | Mode | `tx` out | Note |
|---|---|---|---|---|---|
| 0 | 0 | 1 | Byte | 0 | Start bit begins (Start byte) |
| ... | ... | 0 | Byte | 0 | ... |
| 15 | 15 | 0 | Byte | 0 | Start bit ends |
| 16 | 0 | 1 | Byte | X | Bit 0 begins |
| ... | ... | 0 | Byte | X | ... |
| 144 | 0 | 1 | Byte | 1 | Stop bit begins |
| ... | ... | 0 | Byte | 1 | ... |
| 159 | 15 | 0 | Byte | 1 | Stop bit ends |
| 160 | 0 | 1 | Byte | 0 | Next byte Start bit begins immediately |

**(b) RX of one byte (samples & done)**
| Cycle | `rx_timer` | Strobe | `rx_sync` | Note |
|---|---|---|---|---|
| 0 | 0 | - | 0 | Falling edge detected, timer restarted |
| 7 | 7 | `h-q` | 0 | Sample 1 (Start bit) |
| 8 | 8 | `h` | 0 | Sample 2 (Start bit) |
| 9 | 9 | `h+q` | 0 | Sample 3 (Start bit) |
| ... | ... | ... | ... | Data bits sampled at 23, 24, 25 ... 135, 136, 137 |
| 151 | 7 | `h-q` | 1 | Sample 1 (Stop bit) |
| 152 | 8 | `h` | 1 | Sample 2 (Stop bit) |
| 153 | 9 | `h+q` | 1 | Sample 3 (Stop bit), `done` fires (combinational majority) |

**(c) Break end, Delimiter, and Sync Start bit**
| Cycle | State | `tx_timer` | `bit_start` | `tx` out | Note |
|---|---|---|---|---|---|
| 0 | BREAK | 0 | 1 | 0 | 13th break bit begins |
| ... | ... | ... | 0 | 0 | ... |
| 15 | BREAK | 15 | 0 | 0 | Break ends |
| 16 | DELIM | 0 | 1 | 1 | Delimiter begins |
| ... | ... | ... | 0 | 1 | ... |
| 31 | DELIM | 15 | 0 | 1 | Delimiter ends |
| 32 | SYNC | 0 | 1 | 0 | SYNC Start bit begins |

**(d) PID Stop $->$ Response Space $->$ First Resp Start bit**
| Cycle | Master/Slave State | Timer Event | `tx` out | Note |
|---|---|---|---|---|
| 0 | PID | `bit_start` (M) / `done` (S) | 1 | PID stop bit finishes |
| 1 | DATA | Timer Restarted | 1 | Response space begins (1 $T_{bit}$ delay) |
| ... | DATA | ... | 1 | ... |
| 17 | DATA | `bit_start` | 0 | DATA0 Start bit begins |

**(e) W1C colliding with HW set**
| Cycle | `status` | `wen` (addr=04, data=1) | `hw_set` | Next `status` |
|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 0 (Cleared by SW) |
| 1 | 0 | 0 | 1 | 1 (Set by HW) |
| 2 | 1 | 1 | 1 | 1 (HW Set wins over W1C) |

**(f) 2-cycle START write**
| Cycle | `wen` | `start_set` | `start_pending` | `fsm_busy` | FSM State |
|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 0 | IDLE |
| 1 | 1 | 1 | 0 | 0 | IDLE (EN/MODE updated) |
| 2 | 1 | 0 | 1 | 0 | IDLE (start_set masked by start_pending=1) |
| 3 | 0 | 0 | 0 | 1 | BREAK (FSM evaluates IDLE$->$BREAK via start_pending=1 from cycle 2) |
| 4 | 0 | 0 | 0 | 1 | BREAK |

## 8. Traceability Table

| Requirement ID | Implementing Module(s) | Verifying Test(s) |
|---|---|---|
| LIN-BAUD-01 | `lin_baud` | T04, T21 |
| LIN-BAUD-02 | `lin_regs` | T21 |
| LIN-BAUD-03 | `lin_regs` | T03 |
| LIN-BAUD-04 | `lin_baud`, `lin_tx` | T04 |
| LIN-BAUD-05 | `lin_tx` | T04 |
| LIN-FSM-01 | `lin_frame_fsm` | T01 |
| LIN-FSM-02 | `lin_frame_fsm` | T04 |
| LIN-FSM-03 | `lin_frame_fsm` | T17 |
| LIN-FSM-04 | `lin_frame_fsm` | T15 |
| LIN-FSM-05 | `lin_frame_fsm` | T18 |
| LIN-FSM-06 | `lin_frame_fsm` | T04, T05, T06, T07, T09, T10, T11, T12, T13, T14, T16 |
| LIN-FSM-07 | `lin_frame_fsm` | T04, T06 |
| LIN-GEN-01 | `lin_frame_fsm`, `lin_tx` | T04, T05 |
| LIN-GEN-02 | `lin_frame_fsm`, `lin_rx`, `lin_pid` | T06, T07 |
| LIN-GEN-03 | `lin_regs`, `lin_frame_fsm` | T04, T06 |
| LIN-GEN-04 | `lin_baud`, `lin_regs` | T21 |
| LIN-GEN-05 | `lin_pid`, `lin_checksum` | T04, T07, T10, T12 |
| LIN-GEN-06 | `lin_regs` | T20 |
| LIN-GEN-07 | `lin_wrapper` | None (Flow/lint requirement) |
| LIN-GEN-08 | `lin_wrapper` | T08 |
| LIN-IF-01 | `lin_wrapper` | T01 |
| LIN-IF-02 | `lin_regs` | T02 |
| LIN-IF-03 | `lin_regs` | T02 |
| LIN-IF-04 | `lin_regs` | T02 |
| LIN-IF-05 | `lin_regs` | T02 |
| LIN-IF-06 | `lin_regs` | T02 |
| LIN-IF-07 | `lin_regs` | T02 |
| LIN-IF-08 | `lin_regs` | T02 |
| LIN-IF-09 | `lin_wrapper` | T04 |
| LIN-IF-10 | `lin_regs` | T23 |
| LIN-IF-11 | `lin_wrapper` | T01 |
| LIN-INT-01 | `lin_wrapper` | None (Integration) |
| LIN-INT-02 | `lin_wrapper` | None (Integration) |
| LIN-INT-03 | `lin_wrapper` | None (Integration) |
| LIN-INT-04 | `lin_wrapper` | None (Integration) |
| LIN-INT-05 | `lin_wrapper` | None (Integration) |
| LIN-INT-06 | `lin_wrapper` | None (Integration) |
| LIN-INT-07 | `lin_wrapper` | None (Integration) |
| LIN-INT-08 | `lin_wrapper` | None (Integration) |
| LIN-INT-09 | `lin_wrapper` | None (Integration) |
| LIN-INT-10 | `lin_wrapper` | None (Integration) |
| LIN-INT-11 | Software | None (Software requirement) |
| LIN-INT-12 | Build system | None (Flow requirement) |
| LIN-INT-13 | Build system | None (Flow requirement) |
| LIN-INT-14 | Build system | None (Flow requirement) |
| LIN-INT-15 | Build system | T08 |
| LIN-INT-16 | Build system | T08 |
| LIN-INT-17 | Build system | None (Integration) |
| LIN-INT-18 | Build system | None (Integration) |
| LIN-INT-19 | Software | None (Software requirement) |
| LIN-INT-20 | Software | None (Software requirement) |
| LIN-IRQ-01 | `lin_regs` | T20 |
| LIN-IRQ-02 | `lin_regs` | T20 |
| LIN-IRQ-03 | Software | None (Software integration) |
| LIN-PROT-01 | `lin_frame_fsm` | T14 |
| LIN-PROT-02 | `lin_frame_fsm` | T18 |
| LIN-PROT-03 | `lin_baud` | None (Baseline feature omission) |
| LIN-PROT-04 | `lin_pid` | T04, T10 |
| LIN-PROT-05 | `lin_checksum` | T04, T12 |
| LIN-PROT-06 | `lin_frame_fsm`, `lin_checksum` | T12 |
| LIN-PROT-07 | `lin_checksum` | T04, T07 |
| LIN-PROT-08 | `lin_frame_fsm` | T13 |
| LIN-PROT-09 | `lin_frame_fsm` | T14 |
| LIN-PROT-10 | `lin_frame_fsm` | T13 |
| LIN-PROT-11 | `lin_frame_fsm` | T13 |
| LIN-PROT-12 | `lin_tx`, `lin_frame_fsm` | T07 |
| LIN-REG-01 | `lin_regs` | T01 |
| LIN-REG-02 | `lin_regs` | T02 |
| LIN-REG-03 | `lin_regs` | T02 |
| LIN-REG-04 | `lin_regs` | T03 |
| LIN-REG-05 | `lin_regs`, `lin_frame_fsm` | T04 |
| LIN-REG-06 | `lin_regs`, `lin_frame_fsm` | T05, T06 |
| LIN-REG-07 | `lin_regs` | T05, T06 |
| LIN-RTL-01 | All modules | None (Flow/lint requirement) |
| LIN-RTL-02 | All modules | None (Flow/lint requirement) |
| LIN-RTL-03 | All modules | None (Flow/lint requirement) |
| LIN-RTL-04 | `lin_wrapper` | None (Flow requirement) |
| LIN-RTL-05 | All modules | T01 |
| LIN-RTL-06 | `lin_tx`, `lin_regs` | T01 |
| LIN-RTL-07 | All modules | None (Flow requirement) |
| LIN-RTL-08 | All modules | None (Flow requirement) |
| LIN-RTL-09 | `lin_baud`, `lin_brk`, `lin_frame_fsm` | T13, T14 |
| LIN-RTL-10 | All modules | None (Flow requirement) |
| LIN-RX-01 | `lin_rx` | T06 |
| LIN-RX-02 | `lin_baud`, `lin_rx` | T04, T22 |
| LIN-RX-03 | `lin_rx` | T22 |
| LIN-RX-04 | `lin_rx` | T06 |
| LIN-RX-05 | `lin_rx` | T06, T16 |
| LIN-RX-06 | `lin_brk` | T06 |
| LIN-RX-07 | `lin_tx` | T15 |
| LIN-STAT-01 | `lin_regs` | T02, T19 |
| LIN-STAT-02 | `lin_regs` | T19 |
| LIN-STAT-03 | `lin_regs` | T19 |
| LIN-STAT-04 | `lin_regs` | T04 |
| LIN-VER-01 | Unit testbench | T01-T23 |
| LIN-VER-02 | Unit testbench | T01-T23 |
| LIN-VER-03 | Unit testbench | T05, T06, T10, T12, T15, T16 |
| LIN-VER-04 | Unit testbench | T23 |

## 9. Worked Checks (rev 4)

### (a) Vectors Step-by-Step
**Checksum (Classic, bytes: `4A 55 93 E5`):**
- Seed `s = 0x00`.
- + `0x4A` = `0x4A`.
- + `0x55` = `0x9F`.
- + `0x93` = `0x9F + 0x93 = 0x132`. End-around: `0x132 - 0xFF = 0x33`.
- + `0xE5` = `0x33 + 0xE5 = 0x118`. End-around: `0x118 - 0xFF = 0x19`.
- Checksum = `~0x19 = 0xE6`.

**Checksum (Enhanced, PID: `0xA3`, bytes: `4A 55 93 E5`):**
- Seed `s = 0xA3`.
- + `0x4A` = `0xA3 + 0x4A = 0xED`.
- + `0x55` = `0xED + 0x55 = 0x142`. End-around: `0x142 - 0xFF = 0x43`.
- + `0x93` = `0x43 + 0x93 = 0xD6`.
- + `0xE5` = `0xD6 + 0xE5 = 0x1BB`. End-around: `0x1BB - 0xFF = 0xBC`.
- Checksum = `~0xBC = 0x43`.

**PID Byte (ID 0x23):**
- ID: `0x23` = `6'b100011` (ID5=1, ID4=0, ID3=0, ID2=0, ID1=1, ID0=1).
- P0: `ID0 ^ ID1 ^ ID2 ^ ID4` = `1 ^ 1 ^ 0 ^ 0 = 0`.
- P1: `~(ID1 ^ ID3 ^ ID4 ^ ID5)` = `~(1 ^ 0 ^ 0 ^ 1) = ~(0) = 1`.
- PID = `{P1, P0, 6'b100011}` = `8'b10100011 = 0xA3`.

### (b) Timer Windows at DIV=16
- **TIMEOUT Response Timer (N=1):** With the PID$->$DATA restart in cycle `t`, DATA is entered in cycle `t+1`. The 28th `bit_end` is in cycle `t+448`, and TIMEOUT fires in cycle `t+449 = 448` cycles after entry (N=1).
- **TIMEOUT Response Timer (N=8):** With the PID$->$DATA restart in cycle `t`, DATA is entered in cycle `t+1`. The 126th `bit_end` is in cycle `t+2016`, and TIMEOUT fires in cycle `t+2017 = 2016` cycles after entry (N=8).
- **Slave Header Timer:** With the DELIM$->$SYNC restart in cycle `t`, SYNC is entered in cycle `t+1`. The 28th `bit_end` is in cycle `t+448`, and TIMEOUT fires in cycle `t+449 = 448` cycles after entry.

## 10. Spec Issues

None. All registers, bit offsets, and enumerations in `lin_regmap.yaml` strictly match Section 7 of the specification.
