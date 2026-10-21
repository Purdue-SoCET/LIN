// lin_synchronizer
// Implements: LIN-RTL-05
module lin_synchronizer #(
    parameter int STAGES = 2,
    parameter logic RESET_STATE = 1'b0
)(
    input  logic CLK,
    input  logic nRST,
    input  logic async_in,
    output logic sync_out
);
    logic [STAGES-1:0] sync_regs;
    
    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            sync_regs <= {STAGES{RESET_STATE}};
        end else begin
            sync_regs <= {sync_regs[STAGES-2:0], async_in};
        end
    end
    
    assign sync_out = sync_regs[STAGES-1];
endmodule
