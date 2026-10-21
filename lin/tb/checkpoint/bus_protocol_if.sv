// Standalone-simulation stand-in for AFTx07's bus_protocol_if (spec Appendix B.8).
// Signals and the peripheral_vital modport match the repository interface that
// lin_wrapper connects to. When building inside the AFTx07 repo, use the repo's
// own bus_protocol_if.sv instead of this file.
interface bus_protocol_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
);
    logic                      wen, ren, request_stall, error;
    // Only addr[5:2] selects a LIN register (LIN-IF-02); the remaining bits are
    // legitimately unused by lin_wrapper, so this harness-only waiver is paired.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [ADDR_WIDTH-1:0]     addr;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [DATA_WIDTH-1:0]     wdata, rdata;
    logic [DATA_WIDTH/8-1:0]   strobe;

    modport peripheral_vital (
        input  wen, ren, addr, wdata, strobe,
        output rdata, error, request_stall
    );
    modport protocol (
        input  rdata, error, request_stall,
        output wen, ren, addr, wdata, strobe
    );
endinterface
