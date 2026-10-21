// lin_rx
// Implements: LIN-RX-01, LIN-RX-02, LIN-RX-03, LIN-RX-04, LIN-RX-05
module lin_rx (
    input  logic        CLK,
    input  logic        nRST,
    input  logic [15:0] div,
    input  logic        rx_sync,
    input  logic        enable,
    output logic [7:0]  data_out,
    output logic        stop_bit,
    output logic        done
);

    logic [15:0] rx_timer;
    logic [3:0]  bit_cnt;
    logic        is_active;

    logic [15:0] h, q;
    assign h = div >> 1;
    assign q = div >> 4;
    
    logic sample_h_q, sample_h, sample_h_plus_q;
    assign sample_h_q      = (rx_timer == (h - q));
    assign sample_h        = (rx_timer == h);
    assign sample_h_plus_q = (rx_timer == (h + q));

    logic rx_sync_d;
    logic start_edge;
    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) rx_sync_d <= 1'b1;
        else       rx_sync_d <= rx_sync;
    end
    assign start_edge = (rx_sync_d == 1'b1 && rx_sync == 1'b0);

    logic samp1, samp2;
    logic current_majority;
    
    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            samp1 <= 1'b0;
            samp2 <= 1'b0;
        end else if (enable && is_active) begin
            if (sample_h_q) samp1 <= rx_sync;
            if (sample_h)   samp2 <= rx_sync;
        end
    end
    
    assign current_majority = (samp1 & samp2) | (samp1 & rx_sync) | (samp2 & rx_sync);

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            rx_timer  <= 16'd0;
            bit_cnt   <= 4'd0;
            is_active <= 1'b0;
            data_out  <= 8'd0;
        end else begin
            if (!enable) begin
                is_active <= 1'b0;
                rx_timer  <= 16'd0;
            end else if (!is_active) begin
                if (start_edge) begin
                    is_active <= 1'b1;
                    rx_timer  <= 16'd1; // Next cycle will be 1, timer restarted to 0 combinationally
                    bit_cnt   <= 4'd0;
                end
            end else begin
                if (rx_timer == div - 16'd1) begin
                    rx_timer <= 16'd0;
                    bit_cnt  <= bit_cnt + 4'd1;
                end else begin
                    rx_timer <= rx_timer + 16'd1;
                end
                
                // Done on stop bit (bit_cnt == 9) at h+q
                if (bit_cnt == 4'd9 && sample_h_plus_q) begin
                    is_active <= 1'b0; // finished
                end
                
                // Sample data on h+q
                if (sample_h_plus_q) begin
                    if (bit_cnt == 4'd0) begin
                        if (current_majority == 1'b1) begin
                            // False start
                            is_active <= 1'b0;
                        end
                    end else if (bit_cnt >= 1 && bit_cnt <= 8) begin
                        data_out[bit_cnt - 1] <= current_majority;
                    end
                end
            end
        end
    end

    assign stop_bit = current_majority;
    assign done     = enable && is_active && (bit_cnt == 4'd9) && sample_h_plus_q;

endmodule
