// lin_brk
// Implements: LIN-RTL-09, LIN-RX-06
module lin_brk (
    input  logic        CLK,
    input  logic        nRST,
    input  logic [15:0] div,
    input  logic        rx_sync,
    output logic        break_det
);
    logic [19:0] break_counter;
    logic [19:0] threshold;
    assign threshold = {1'b0, div, 3'd0} + {3'd0, div, 1'b0} + {4'd0, div}; // 8*div + 2*div + div = 11*div

    assign break_det = (break_counter == threshold);

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            break_counter <= 20'd0;
        end else begin
            if (rx_sync == 1'b1) begin
                break_counter <= 20'd0;
            end else if (break_counter < threshold) begin
                break_counter <= break_counter + 20'd1;
            end
        end
    end
endmodule
