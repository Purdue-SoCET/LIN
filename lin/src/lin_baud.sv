// lin_baud
// Implements: LIN-BAUD-01, LIN-RTL-09, LIN-BAUD-04
module lin_baud (
    input  logic        CLK,
    input  logic        nRST,
    input  logic [15:0] div,
    input  logic        restart,
    output logic        bit_start,
    output logic        bit_end,
    output logic        sample_h_q,
    output logic        sample_h,
    output logic        sample_h_plus_q
);
    logic [15:0] tx_timer;
    assign bit_start = (tx_timer == 16'd0);
    assign bit_end   = (tx_timer == div - 16'd1);

    logic [15:0] h, q;
    assign h = div >> 1;
    assign q = div >> 4;

    assign sample_h_q      = (tx_timer == (h - q));
    assign sample_h        = (tx_timer == h);
    assign sample_h_plus_q = (tx_timer == (h + q));

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) tx_timer <= 16'd0;
        else if (restart | bit_end) tx_timer <= 16'd0;
        else tx_timer <= tx_timer + 16'd1;
    end
endmodule
