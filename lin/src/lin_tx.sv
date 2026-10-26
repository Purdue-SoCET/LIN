// lin_tx
// Implements: LIN-BAUD-04, LIN-BAUD-05, LIN-GEN-01, LIN-PROT-12, LIN-RTL-06, LIN-RX-07
module lin_tx (
    input  logic       CLK,
    input  logic       nRST,
    input  logic       bit_start,
    input  logic       bit_end,
    input  logic       restart,
    input  logic       sample_h_q,
    input  logic       sample_h,
    input  logic       sample_h_plus_q,
    input  logic       start,
    input  logic [1:0] mode,
    input  logic [7:0] data_in,
    input  logic       rx_sync,
    input  logic       abort,
    output logic       tx_out,
    output logic       done,
    output logic       bit_err
);
    logic [3:0] bit_cnt;
    logic       is_active;
    logic [1:0] current_mode;
    logic [7:0] shift_reg;
    
    logic samp1, samp2;
    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            samp1 <= 1'b0;
            samp2 <= 1'b0;
        end else if (is_active && current_mode != 2'd3) begin
            if (sample_h_q) samp1 <= rx_sync;
            if (sample_h)   samp2 <= rx_sync;
        end
    end
    
    logic current_majority;
    assign current_majority = (samp1 & samp2) | (samp1 & rx_sync) | (samp2 & rx_sync);
    assign bit_err = is_active && (current_mode != 2'd3) && sample_h_plus_q && (current_majority != tx_out);

    logic next_tx;
    always_comb begin
        next_tx = 1'b1;
        if (is_active) begin
            case (current_mode)
                2'd0: begin
                    if (bit_cnt == 0) next_tx = 1'b0;
                    else if (bit_cnt == 9) next_tx = 1'b1;
                    else next_tx = shift_reg[0];
                end
                2'd1: next_tx = 1'b0;
                2'd2: next_tx = 1'b1;
                2'd3: next_tx = 1'b1;
            endcase
        end else if (start) begin
            case (mode)
                2'd0: next_tx = 1'b0;
                2'd1: next_tx = 1'b0;
                2'd2: next_tx = 1'b1;
                2'd3: next_tx = 1'b1;
            endcase
        end
    end

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) tx_out <= 1'b1;
        else if (abort) tx_out <= 1'b1;
        else if (bit_end | restart | start) tx_out <= next_tx;
    end

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            is_active <= 1'b0;
            bit_cnt   <= 4'd0;
            current_mode <= 2'd0;
            shift_reg <= 8'd0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                is_active <= 1'b1;
                bit_cnt <= 4'd0;
                current_mode <= mode;
                shift_reg <= data_in;
            end else if (is_active && (bit_end | restart)) begin
                bit_cnt <= bit_cnt + 4'd1;
                if (current_mode == 2'd0) begin
                    if (bit_cnt >= 1 && bit_cnt <= 8) shift_reg <= {1'b0, shift_reg[7:1]};
                    if (bit_cnt == 9) begin
                        is_active <= 1'b0;
                        done <= 1'b1;
                    end
                end else if (current_mode == 2'd1) begin
                    if (bit_cnt == 12) begin
                        is_active <= 1'b0;
                        done <= 1'b1;
                    end
                end else if (current_mode == 2'd2 || current_mode == 2'd3) begin
                    if (bit_cnt == 0) begin
                        is_active <= 1'b0;
                        done <= 1'b1;
                    end
                end
            end
        end
    end

    // bit_start from baud generator is not used because bit_end governs bit timing
    // Reason: bit_start from baud generator is not used because bit_end governs bit timing
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused_ports = &{1'b0, bit_start};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
