// lin_checksum
// Implements: LIN-GEN-05, LIN-PROT-05, LIN-PROT-06, LIN-PROT-07
module lin_checksum (
    input  logic       CLK,
    input  logic       nRST,
    input  logic [7:0] seed,
    input  logic       load_seed,
    input  logic [7:0] data_in,
    input  logic       accumulate,
    input  logic [7:0] rx_checksum_in,
    output logic       cksum_err,
    output logic [7:0] cksum_out
);
    logic [7:0] acc;
    logic [8:0] sum;
    assign sum = acc + data_in;
    logic [7:0] next_acc;
    assign next_acc = sum[7:0] + {7'd0, sum[8]}; // end-around carry
    
    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) acc <= 8'd0;
        else if (load_seed) acc <= seed;
        else if (accumulate) acc <= next_acc;
    end
    
    assign cksum_out = ~acc;
    assign cksum_err = (rx_checksum_in != cksum_out);
endmodule
