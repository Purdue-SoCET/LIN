// lin_regs
// Implements: LIN-GEN-03, LIN-GEN-04, LIN-GEN-06, LIN-IF-02, LIN-IF-03, LIN-IF-04, LIN-IF-05, LIN-IF-06, LIN-IF-07, LIN-IF-08, LIN-IF-10, LIN-IRQ-01, LIN-IRQ-02, LIN-REG-01, LIN-REG-02, LIN-REG-03, LIN-REG-04, LIN-REG-05, LIN-REG-06, LIN-REG-07, LIN-STAT-01, LIN-STAT-02, LIN-STAT-03, LIN-STAT-04
module lin_regs #(
    parameter int unsigned DEFAULT_DIV = 521
) (
    input  logic CLK,
    input  logic nRST,
    bus_protocol_if.peripheral_vital busif,
    input  logic [7:0]  fsm_set_flags,
    input  logic        fsm_busy,
    input  logic [7:0]  rx_data_wen,
    input  logic        rx_data_clr,
    output logic [31:0] ctrl,
    output logic [31:0] status,
    output logic [15:0] baud_div,
    output logic [31:0] pid,
    output logic [31:0] tx_data0,
    output logic [31:0] tx_data1,
    output logic [31:0] irq_en,
    output logic        irq,
    output logic        start_pending,
    input  logic [7:0]  rx_byte_in,
    output logic        tx_en
);

    logic [31:0] rx_data0_reg;
    logic [31:0] rx_data1_reg;
    
    logic wen, ren;
    assign wen = busif.wen;
    assign ren = busif.ren;
    
    logic [3:0] wstrb;
    assign wstrb = busif.strobe;

    logic wr_protect;
    assign wr_protect = fsm_busy | start_pending;

    logic start_set;
    assign start_set = wen & (busif.addr[5:2] == 4'h0) & wstrb[0] & busif.wdata[2] & busif.wdata[0] & ~busif.wdata[1] & ~wr_protect;

    logic fsm_ack;
    assign fsm_ack = fsm_busy; 

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) start_pending <= 1'b0;
        else if (fsm_ack) start_pending <= 1'b0;
        else if (start_set) start_pending <= 1'b1;
    end

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            ctrl <= '0;
            tx_en <= 1'b0;
        end else begin
            tx_en <= ctrl[0]; // per LIN-RTL-06, tx_en is driven from a flip-flop
            if (wen && busif.addr[5:2] == 4'h0) begin
                if (wstrb[0]) begin
                    ctrl[0] <= busif.wdata[0];
                    if (!wr_protect) begin
                        ctrl[1] <= busif.wdata[1];
                        ctrl[2] <= busif.wdata[2];
                        ctrl[3] <= busif.wdata[3];
                        ctrl[6:4] <= busif.wdata[6:4];
                    end
                end
            end else if (fsm_ack) begin
                ctrl[2] <= 1'b0;
            end
        end
    end

    logic w1c_en;
    assign w1c_en = wen & (busif.addr[5:2] == 4'h1) & wstrb[0];

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) status <= '0;
        else begin
            status[7:1] <= (status[7:1] & ~(w1c_en ? busif.wdata[7:1] : 7'b0)) | fsm_set_flags[7:1];
            status[0]   <= fsm_busy;
        end
    end

    logic [15:0] next_baud;
    always_comb begin
        next_baud = baud_div;
        if (wstrb[0]) next_baud[7:0] = busif.wdata[7:0];
        if (wstrb[1]) next_baud[15:8] = busif.wdata[15:8];
    end

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) baud_div <= DEFAULT_DIV[15:0];
        else if (wen && busif.addr[5:2] == 4'h2 && !wr_protect)
            baud_div <= (next_baud < 16) ? 16'd16 : next_baud;
    end

    logic [5:0] id_reg;
    logic cksum_type_reg;
    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            id_reg <= '0;
            cksum_type_reg <= 1'b0;
        end else if (wen && busif.addr[5:2] == 4'h3 && !wr_protect) begin
            if (wstrb[0]) id_reg <= busif.wdata[5:0];
            if (wstrb[1]) cksum_type_reg <= busif.wdata[8];
        end
    end
    
    logic p0, p1;
    assign p0 = id_reg[0] ^ id_reg[1] ^ id_reg[2] ^ id_reg[4];
    assign p1 = ~(id_reg[1] ^ id_reg[3] ^ id_reg[4] ^ id_reg[5]);
    assign pid = {23'd0, cksum_type_reg, p1, p0, id_reg};

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) tx_data0 <= '0;
        else if (wen && busif.addr[5:2] == 4'h4 && !wr_protect) begin
            if (wstrb[0]) tx_data0[7:0]   <= busif.wdata[7:0];
            if (wstrb[1]) tx_data0[15:8]  <= busif.wdata[15:8];
            if (wstrb[2]) tx_data0[23:16] <= busif.wdata[23:16];
            if (wstrb[3]) tx_data0[31:24] <= busif.wdata[31:24];
        end
    end

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) tx_data1 <= '0;
        else if (wen && busif.addr[5:2] == 4'h5 && !wr_protect) begin
            if (wstrb[0]) tx_data1[7:0]   <= busif.wdata[7:0];
            if (wstrb[1]) tx_data1[15:8]  <= busif.wdata[15:8];
            if (wstrb[2]) tx_data1[23:16] <= busif.wdata[23:16];
            if (wstrb[3]) tx_data1[31:24] <= busif.wdata[31:24];
        end
    end

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            rx_data0_reg <= '0;
            rx_data1_reg <= '0;
        end else if (rx_data_clr) begin
            rx_data0_reg <= '0;
            rx_data1_reg <= '0;
        end else begin
            if (rx_data_wen[0]) rx_data0_reg[7:0]   <= rx_byte_in;
            if (rx_data_wen[1]) rx_data0_reg[15:8]  <= rx_byte_in;
            if (rx_data_wen[2]) rx_data0_reg[23:16] <= rx_byte_in;
            if (rx_data_wen[3]) rx_data0_reg[31:24] <= rx_byte_in;
            if (rx_data_wen[4]) rx_data1_reg[7:0]   <= rx_byte_in;
            if (rx_data_wen[5]) rx_data1_reg[15:8]  <= rx_byte_in;
            if (rx_data_wen[6]) rx_data1_reg[23:16] <= rx_byte_in;
            if (rx_data_wen[7]) rx_data1_reg[31:24] <= rx_byte_in;
        end
    end

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) irq_en <= '0;
        else if (wen && busif.addr[5:2] == 4'h8 && wstrb[0])
            irq_en[7:1] <= busif.wdata[7:1];
    end

    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) irq <= 1'b0;
        else irq <= |(status[7:1] & irq_en[7:1]);
    end

    always_comb begin
        busif.rdata = '0;
        if (ren) begin
            case (busif.addr[5:2])
                4'h0: busif.rdata = {25'd0, ctrl[6:3], 1'b0, ctrl[1:0]};
                4'h1: busif.rdata = status;
                4'h2: busif.rdata = {16'd0, baud_div};
                4'h3: busif.rdata = pid;
                4'h4: busif.rdata = tx_data0;
                4'h5: busif.rdata = tx_data1;
                4'h6: busif.rdata = rx_data0_reg;
                4'h7: busif.rdata = rx_data1_reg;
                4'h8: busif.rdata = irq_en;
                default: busif.rdata = '0;
            endcase
        end
    end
    
    assign busif.error = 1'b0;
    assign busif.request_stall = 1'b0;


    // fsm_set_flags[0] is not mapped to any STATUS register bit
    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused_ports = &{1'b0, fsm_set_flags[0]};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
