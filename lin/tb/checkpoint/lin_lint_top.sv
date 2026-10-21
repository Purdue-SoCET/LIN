// Lint harness: drives every lin_wrapper input and consumes every output, so
// `verilator --lint-only -Wall` reports only warnings that belong to the RTL.
module lin_lint_top (
    input  logic        CLK,
    input  logic        nRST,
    input  logic        wen,
    input  logic        ren,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic [3:0]  strobe,
    input  logic        rx,
    output logic [31:0] rdata,
    output logic        error,
    output logic        request_stall,
    output logic        tx,
    output logic        tx_en,
    output logic        irq
);
    bus_protocol_if busif ();
    lin_if          linif ();

    assign busif.wen    = wen;
    assign busif.ren    = ren;
    assign busif.addr   = addr;
    assign busif.wdata  = wdata;
    assign busif.strobe = strobe;
    assign rdata         = busif.rdata;
    assign error         = busif.error;
    assign request_stall = busif.request_stall;

    assign linif.rx = rx;
    assign tx       = linif.tx;
    assign tx_en    = linif.tx_en;
    assign irq      = linif.irq;

    lin_wrapper u_lin (.CLK(CLK), .nRST(nRST), .busif(busif), .linif(linif));
endmodule
