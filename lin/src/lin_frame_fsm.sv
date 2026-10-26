// lin_frame_fsm
// Implements: LIN-FSM-01, LIN-FSM-02, LIN-FSM-03, LIN-FSM-04, LIN-FSM-05, LIN-FSM-06, LIN-FSM-07, LIN-GEN-01, LIN-GEN-02, LIN-GEN-03, LIN-PROT-01, LIN-PROT-02, LIN-PROT-06, LIN-PROT-08, LIN-PROT-09, LIN-PROT-10, LIN-PROT-11, LIN-REG-05, LIN-REG-06, LIN-RTL-09
module lin_frame_fsm (
    input  logic        CLK,
    input  logic        nRST,
    input  logic [31:0] ctrl,
    input  logic [15:0] baud_div,
    input  logic [31:0] pid,
    input  logic [31:0] tx_data0,
    input  logic [31:0] tx_data1,
    input  logic        start_pending,
    input  logic [7:0]  rx_byte,
    input  logic        rx_done,
    input  logic        rx_stop_bit,
    input  logic        tx_done,
    input  logic        bit_err,
    input  logic        break_det,
    input  logic        pid_err,
    input  logic        cksum_err,
    input  logic        bit_start,
    input  logic        bit_end,
    input  logic        rx_sync,
    input  logic [7:0]  cksum_out,
    
    output logic [7:0]  fsm_set_flags,
    output logic        busy,
    output logic [7:0]  rx_data_wen,
    output logic        rx_data_clr,
    output logic [7:0]  rx_byte_out,
    output logic [7:0]  tx_byte,
    output logic        tx_start,
    output logic [1:0]  tx_mode,
    output logic        tx_timer_rst,
    output logic        rx_en,
    output logic        cksum_load_seed,
    output logic [7:0]  cksum_seed,
    output logic        cksum_accumulate,
    output logic [7:0]  cksum_data
);

    typedef enum logic [2:0] {IDLE=0, BREAK=1, DELIM=2, SYNC=3, PID_ST=4, DATA=5, CKSUM=6, DONE=7} state_t;
    state_t state, next_state;

    logic is_master, tx_resp;
    assign is_master = (ctrl[1] == 1'b0); // MODE=0 -> Master
    assign tx_resp   = ctrl[3];

    logic [3:0] dlen_bytes;
    assign dlen_bytes = {1'b0, ctrl[6:4]} + 4'd1;

    logic [6:0] response_timer;
    logic [4:0] header_timer;
    logic [3:0] byte_counter;

    logic [6:0] resp_thresh;
    assign resp_thresh = 7'(7'd14 * (7'(dlen_bytes) + 7'd1));
    
    logic timeout_resp, timeout_head;
    assign timeout_resp = (response_timer >= resp_thresh);
    assign timeout_head = (header_timer >= 28);
    
    logic pid_to_data;
    assign pid_to_data = (state == PID_ST && next_state == DATA);
    logic delim_to_sync;
    assign delim_to_sync = (state == DELIM && next_state == SYNC);

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            response_timer <= '0;
            header_timer <= '0;
        end else begin
            if (pid_to_data) response_timer <= '0;
            else if (bit_end && response_timer < resp_thresh) response_timer <= response_timer + 1;
            
            if (delim_to_sync && !is_master) header_timer <= '0;
            else if (bit_end && header_timer < 28) header_timer <= header_timer + 1;
        end
    end

    logic data_entry;
    assign data_entry = (state != DATA && next_state == DATA);

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) byte_counter <= '0;
        else if (data_entry) byte_counter <= '0;
        else if (state == DATA) begin
            if ((tx_resp == 1'b1 && tx_done) || (tx_resp == 1'b0 && rx_done))
                byte_counter <= byte_counter + 1;
        end
    end

    // Next State Logic per LIN-FSM-03..06
    logic set_frame_err, set_sync_err, set_pid_err, set_timeout, set_cksum_err, set_done;
    
    always_comb begin
        next_state = state;
        set_frame_err = 0; set_sync_err = 0; set_pid_err = 0; set_timeout = 0; set_cksum_err = 0; set_done = 0;
        tx_timer_rst = 0;
        
        if (ctrl[0] == 1'b0) begin
            next_state = IDLE;
        end else if (bit_err) begin
            next_state = IDLE;
        end else if (!is_master && break_det && (state == SYNC || state == PID_ST || state == DATA || state == CKSUM)) begin
            next_state = DELIM;
        end else begin
            case (state)
                IDLE: begin
                    if (is_master && (ctrl[1]==1'b0 && start_pending)) begin
                        next_state = BREAK;
                        tx_timer_rst = 1'b1;
                    end else if (!is_master && break_det && ctrl[0]) begin
                        next_state = DELIM;
                    end
                end
                BREAK: begin
                    if (is_master && tx_done) next_state = DELIM;
                end
                DELIM: begin
                    if (is_master && tx_done) begin
                        next_state = SYNC;
                    end else if (!is_master && rx_sync == 1'b1) begin
                        next_state = SYNC;
                        tx_timer_rst = 1'b1;
                    end
                end
                SYNC: begin
                    if (is_master && tx_done) next_state = PID_ST;
                    else if (!is_master) begin
                        if (rx_done) begin
                            if (rx_byte == 8'h55 && rx_stop_bit) next_state = PID_ST;
                            else begin
                                next_state = IDLE;
                                set_sync_err = 1;
                            end
                        end else if (timeout_head) begin
                            next_state = IDLE;
                            set_timeout = 1;
                        end
                    end
                end
                PID_ST: begin
                    if (is_master && tx_done) begin
                        next_state = DATA;
                        tx_timer_rst = 1'b1;
                    end else if (!is_master) begin
                        if (rx_done) begin
                            if (!rx_stop_bit) begin
                                next_state = IDLE;
                                set_frame_err = 1;
                            end else if (pid_err) begin
                                next_state = IDLE;
                                set_pid_err = 1;
                            end else if (pid[5:0] == rx_byte[5:0]) begin
                                next_state = DATA;
                                tx_timer_rst = 1'b1;
                            end else begin
                                next_state = IDLE;
                            end
                        end else if (timeout_head) begin
                            next_state = IDLE;
                            set_timeout = 1;
                        end
                    end
                end
                DATA: begin
                    if (tx_resp) begin
                        if (tx_done) begin
                            if (byte_counter == (dlen_bytes - 1)) next_state = CKSUM;
                        end
                    end else begin
                        if (rx_done) begin
                            if (!rx_stop_bit) begin
                                next_state = IDLE;
                                set_frame_err = 1;
                            end else if (byte_counter == (dlen_bytes - 1)) begin
                                next_state = CKSUM;
                            end
                        end else if (timeout_resp) begin
                            next_state = IDLE;
                            set_timeout = 1;
                        end
                    end
                end
                CKSUM: begin
                    if (tx_resp) begin
                        if (tx_done) next_state = DONE;
                    end else begin
                        if (rx_done) begin
                            if (!rx_stop_bit) begin
                                next_state = IDLE;
                                set_frame_err = 1;
                            end else if (cksum_err) begin
                                next_state = IDLE;
                                set_cksum_err = 1;
                            end else begin
                                next_state = DONE;
                            end
                        end else if (timeout_resp) begin
                            next_state = IDLE;
                            set_timeout = 1;
                        end
                    end
                end
                DONE: begin
                    next_state = IDLE;
                    set_done = 1;
                end
            endcase
        end
    end
    
    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) state <= IDLE;
        else state <= next_state;
    end
    
    assign busy = (state != IDLE);
    
    // Status flag setting
    assign fsm_set_flags = {
        bit_err,
        set_frame_err,
        set_sync_err,
        set_pid_err,
        set_timeout,
        set_cksum_err,
        set_done,
        1'b0
    };
    
    // TX mode and start control
    always_comb begin
        tx_mode = 2'd0;
        tx_start = 1'b0;
        tx_byte = 8'd0;
        
        case(state)
            IDLE: begin
                if (next_state == BREAK) begin
                    tx_mode = 2'd1;
                    tx_start = 1'b1;
                end
            end
            BREAK: begin
                if (next_state == DELIM && is_master) begin
                    tx_mode = 2'd2;
                    tx_start = 1'b1;
                end
            end
            DELIM: begin
                if (next_state == SYNC && is_master) begin
                    tx_mode = 2'd0;
                    tx_start = 1'b1;
                    tx_byte = 8'h55;
                end
            end
            SYNC: begin
                if (next_state == PID_ST && is_master) begin
                    tx_mode = 2'd0;
                    tx_start = 1'b1;
                    tx_byte = pid[7:0];
                end
            end
            PID_ST: begin
                if (next_state == DATA && tx_resp) begin
                    tx_mode = 2'd3; // Resp space
                    tx_start = 1'b1;
                end
            end
            DATA: begin
                if (tx_resp && state == DATA) begin
                    if ((byte_counter == 0 && tx_done && tx_mode == 2'd3) || (tx_done && tx_mode == 2'd0 && byte_counter < dlen_bytes)) begin
                        tx_mode = 2'd0;
                        tx_start = 1'b1;
                        if (byte_counter < 4) tx_byte = tx_data0[byte_counter*8 +: 8];
                        else                  tx_byte = tx_data1[(byte_counter-4)*8 +: 8];
                    end
                end
            end
            CKSUM: begin
                if (tx_resp && tx_done && state == DATA && next_state == CKSUM) begin
                    tx_mode = 2'd0;
                    tx_start = 1'b1;
                    tx_byte = cksum_out; // Mux cksum out!
                end
            end
            default: ;
        endcase
    end
    
    // RX enable logic
    always_comb begin
        rx_en = 1'b0;
        if (is_master) begin
            if (state == SYNC || state == PID_ST || (state == DATA && !tx_resp) || (state == CKSUM && !tx_resp)) rx_en = 1'b1;
        end else begin
            if (state == DELIM || state == SYNC || state == PID_ST || state == DATA || state == CKSUM) rx_en = 1'b1;
        end
    end
    
    // Checksum integration
    assign cksum_load_seed = pid_to_data;
    assign cksum_seed = pid[8] ? pid[7:0] : 8'd0; // Enhanced = PID, Classic = 0
    assign cksum_data = tx_resp ? tx_byte : rx_byte;
    assign cksum_accumulate = (state == DATA) && ((tx_resp && tx_start && tx_mode == 2'd0) || (!tx_resp && rx_done && rx_stop_bit));
    
    // RXDATA integration
    assign rx_data_clr = data_entry && !tx_resp;
    assign rx_byte_out = rx_byte;
    always_comb begin
        rx_data_wen = 8'd0;
        if (!tx_resp && state == DATA && rx_done && rx_stop_bit) begin
            rx_data_wen[byte_counter[2:0]] = 1'b1;
        end
    end
    

    // Reason: FSM only uses ctrl[6:3] and ctrl[1:0]; baud_div goes to baud gen; pid is 8 bits; bit_start is redundant
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused_ports = &{1'b0, ctrl[31:7], ctrl[2], baud_div, pid[31:9], bit_start};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
