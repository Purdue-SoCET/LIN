// lin_wrapper
// Implements: LIN-GEN-07, LIN-GEN-08, LIN-IF-01, LIN-IF-09, LIN-IF-11, LIN-RTL-04, LIN-INT-01..10
module lin_wrapper #(
    parameter int unsigned DEFAULT_DIV = 521
) (
    input  logic CLK,
    input  logic nRST,
    bus_protocol_if.peripheral_vital busif,
    lin_if.peripheral linif
);
    logic rx_sync;
    
    lin_synchronizer #(
        .STAGES(2),
        .RESET_STATE(1'b1)
    ) u_sync (
        .CLK(CLK),
        .nRST(nRST),
        .async_in(linif.rx),
        .sync_out(rx_sync)
    );

    logic [7:0]  fsm_set_flags;
    logic        fsm_busy;
    logic [7:0]  rx_data_wen;
    logic        rx_data_clr;
    logic [31:0] ctrl;
    logic [15:0] baud_div;
    logic [31:0] pid;
    logic [31:0] tx_data0;
    logic [31:0] tx_data1;
    logic        start_pending;
    logic [7:0]  rx_byte_in;

    logic [31:0] status;
    logic [31:0] irq_en;
    logic [7:0] pid_out;

    lin_regs #(
        .DEFAULT_DIV(DEFAULT_DIV)
    ) u_regs (
        .CLK(CLK),
        .nRST(nRST),
        .busif(busif),
        .fsm_set_flags(fsm_set_flags),
        .fsm_busy(fsm_busy),
        .rx_data_wen(rx_data_wen),
        .rx_data_clr(rx_data_clr),
        .ctrl(ctrl),
        .status(status),
        .baud_div(baud_div),
        .pid(pid),
        .tx_data0(tx_data0),
        .tx_data1(tx_data1),
        .irq_en(irq_en),
        .irq(linif.irq),
        .start_pending(start_pending),
        .rx_byte_in(rx_byte_in),
        .tx_en(linif.tx_en)
    );

    logic [7:0] rx_byte;
    logic       rx_done;
    logic       rx_stop_bit;
    logic       tx_done;
    logic       bit_err;
    logic       break_det;
    logic       pid_err;
    logic       cksum_err;
    logic       bit_start;
    logic       bit_end;
    
    logic [7:0] tx_byte;
    logic       tx_start;
    logic [1:0] tx_mode;
    logic       tx_timer_rst;
    logic       rx_en;
    
    logic       cksum_load_seed;
    logic [7:0] cksum_seed;
    logic       cksum_accumulate;
    logic [7:0] cksum_data;
    logic [7:0] cksum_out;

    lin_frame_fsm u_fsm (
        .CLK(CLK),
        .nRST(nRST),
        .ctrl(ctrl),
        .baud_div(baud_div),
        .pid(pid),
        .tx_data0(tx_data0),
        .tx_data1(tx_data1),
        .start_pending(start_pending),
        .rx_byte(rx_byte),
        .rx_done(rx_done),
        .rx_stop_bit(rx_stop_bit),
        .tx_done(tx_done),
        .bit_err(bit_err),
        .break_det(break_det),
        .pid_err(pid_err),
        .cksum_err(cksum_err),
        .bit_start(bit_start),
        .bit_end(bit_end),
        .rx_sync(rx_sync),
        .cksum_out(cksum_out),
        .fsm_set_flags(fsm_set_flags),
        .busy(fsm_busy),
        .rx_data_wen(rx_data_wen),
        .rx_data_clr(rx_data_clr),
        .rx_byte_out(rx_byte_in),
        .tx_byte(tx_byte),
        .tx_start(tx_start),
        .tx_mode(tx_mode),
        .tx_timer_rst(tx_timer_rst),
        .rx_en(rx_en),
        .cksum_load_seed(cksum_load_seed),
        .cksum_seed(cksum_seed),
        .cksum_accumulate(cksum_accumulate),
        .cksum_data(cksum_data)
    );

    logic sample_h_q, sample_h, sample_h_plus_q;

    lin_baud u_baud (
        .CLK(CLK),
        .nRST(nRST),
        .div(baud_div),
        .restart(tx_timer_rst),
        .bit_start(bit_start),
        .bit_end(bit_end),
        .sample_h_q(sample_h_q),
        .sample_h(sample_h),
        .sample_h_plus_q(sample_h_plus_q)
    );

    lin_tx u_tx (
        .CLK(CLK),
        .nRST(nRST),
        .bit_start(bit_start),
        .bit_end(bit_end),
        .restart(tx_timer_rst),
        .sample_h_q(sample_h_q),
        .sample_h(sample_h),
        .sample_h_plus_q(sample_h_plus_q),
        .start(tx_start),
        .mode(tx_mode),
        .data_in(tx_byte),
        .rx_sync(rx_sync),
        .abort(1'b0),
        .tx_out(linif.tx),
        .done(tx_done),
        .bit_err(bit_err)
    );

    lin_rx u_rx (
        .CLK(CLK),
        .nRST(nRST),
        .div(baud_div),
        .rx_sync(rx_sync),
        .enable(rx_en),
        .data_out(rx_byte),
        .stop_bit(rx_stop_bit),
        .done(rx_done)
    );

    lin_brk u_brk (
        .CLK(CLK),
        .nRST(nRST),
        .div(baud_div),
        .rx_sync(rx_sync),
        .break_det(break_det)
    );
    
    lin_pid u_pid (
        .id_in(pid[5:0]),
        .pid_in(rx_byte),
        .pid_out(pid_out),
        .pid_err(pid_err)
    );

    lin_checksum u_checksum (
        .CLK(CLK),
        .nRST(nRST),
        .seed(cksum_seed),
        .load_seed(cksum_load_seed),
        .data_in(cksum_data),
        .accumulate(cksum_accumulate),
        .rx_checksum_in(rx_byte),
        .cksum_err(cksum_err),
        .cksum_out(cksum_out)
    );

    // status and irq_en are exposed purely via the bus; pid_out is output-only from lin_pid
    // Reason: status and irq_en are exposed purely via the bus; pid_out is output-only from lin_pid
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused_ports = &{1'b0, status, irq_en, pid_out};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
