// =============================================================================
// LIN checkpoint testbench (black box). DO NOT EDIT -- protected by MANIFEST.sha256.
//
// Drives two lin_wrapper instances only through the spec-fixed interface
// (spec v0.5 sections 6 and 7) and the LIN wire. Every check prints exactly one line:
//     CHECK <CPn.mm> PASS|FAIL <detail>
// run_checkpoints.sh counts these lines. A check that is missing counts as FAIL.
//
// Bus: wired-AND of master tx, slave tx and a testbench driver (bfm_drv),
// fed back to both rx inputs through a 2-cycle loop delay (LIN-VER-01/02).
// =============================================================================
`timescale 1ns/1ps
module tb_checkpoint;
    localparam int DIV  = 16;
    localparam int MAXC = 400000;

    // register offsets (spec 7.1)
    localparam logic [31:0] CTRL = 32'h00, STATUS = 32'h04, BAUD = 32'h08, PID = 32'h0C,
                            TXD0 = 32'h10, TXD1 = 32'h14, RXD0 = 32'h18, RXD1 = 32'h1C,
                            IRQEN = 32'h20;
    // CTRL bits (spec 7.2)
    localparam logic [31:0] EN = 32'h1, MODE = 32'h2, START = 32'h4, TXRESP = 32'h8;
    function automatic logic [31:0] dlen(input int n); return 32'((n - 1) & 7) << 4; endfunction
    // STATUS bits (spec 7.3)
    localparam logic [31:0] S_BUSY = 32'h01, S_DONE = 32'h02, S_CKSUM = 32'h04, S_TIMEOUT = 32'h08,
                            S_BIT = 32'h10, S_FRAME = 32'h20, S_SYNC = 32'h40, S_PID = 32'h80;

    logic CLK = 0, nRST = 0;
    always #5 CLK = ~CLK;

    bus_protocol_if bm ();
    bus_protocol_if bs ();
    lin_if lm ();
    lin_if ls ();

    logic bfm_drv = 1'b1;
    logic bus;
    logic [1:0] dly = 2'b11;
    assign bus = lm.tx & ls.tx & bfm_drv;
    always @(posedge CLK) dly <= {dly[0], bus};
    assign lm.rx = dly[1];
    assign ls.rx = dly[1];

    lin_wrapper                     dut_m (.CLK(CLK), .nRST(nRST), .busif(bm), .linif(lm));
    lin_wrapper #(.DEFAULT_DIV(16)) dut_s (.CLK(CLK), .nRST(nRST), .busif(bs), .linif(ls));

    // ---------------------------------------------------------------- logging
    int cyc = 0;
    bit log_txm [MAXC];
    bit log_txs [MAXC];
    bit log_bus [MAXC];
    bit log_bfm [MAXC];
    bit log_irqm[MAXC];
    bit log_irqs[MAXC];
    always @(posedge CLK) begin
        if (cyc < MAXC) begin
            log_txm[cyc]  <= lm.tx;
            log_txs[cyc]  <= ls.tx;
            log_bus[cyc]  <= bus;
            log_bfm[cyc]  <= bfm_drv;
            log_irqm[cyc] <= lm.irq;
            log_irqs[cyc] <= ls.irq;
        end
        cyc <= cyc + 1;
    end

    // ---------------------------------------------------------------- reporting
    int n_fail = 0;
    task automatic check(input string id, input bit ok, input string detail);
        $display("CHECK %s %s %s", id, ok ? "PASS" : "FAIL", detail);
        if (!ok) n_fail++;
    endtask

    // ---------------------------------------------------------------- bus access
    task automatic idle_bus();
        bm.wen = 0; bm.ren = 0; bm.addr = 0; bm.wdata = 0; bm.strobe = 0;
        bs.wen = 0; bs.ren = 0; bs.addr = 0; bs.wdata = 0; bs.strobe = 0;
    endtask

    // s = 0 master instance, 1 slave instance. wen held for `hold` cycles.
    task automatic wr(input bit s, input logic [31:0] a, input logic [31:0] d,
                      input logic [3:0] stb = 4'hF, input int hold = 1);
        @(negedge CLK);
        if (!s) begin bm.addr = a; bm.wdata = d; bm.strobe = stb; bm.wen = 1; end
        else    begin bs.addr = a; bs.wdata = d; bs.strobe = stb; bs.wen = 1; end
        repeat (hold) @(negedge CLK);
        if (!s) bm.wen = 0; else bs.wen = 0;
    endtask

    // rdata is combinational while ren = 1 (LIN-IF-04); sampled before the next edge.
    task automatic rd(input bit s, input logic [31:0] a, output logic [31:0] d);
        @(negedge CLK);
        if (!s) begin bm.addr = a; bm.ren = 1; end
        else    begin bs.addr = a; bs.ren = 1; end
        #1;
        d = s ? bs.rdata : bm.rdata;
        @(negedge CLK);
        if (!s) bm.ren = 0; else bs.ren = 0;
    endtask

    task automatic reset_all();
        idle_bus();
        bfm_drv = 1'b1;
        @(negedge CLK); nRST = 0;
        repeat (3) @(negedge CLK);
        nRST = 1;
        repeat (2) @(negedge CLK);
    endtask

    // Poll STATUS until an event flag is set and BUSY = 0, or max_cycles pass.
    task automatic wait_event(input bit s, input int max_cycles, output logic [31:0] st);
        int t0 = cyc;
        do begin
            rd(s, STATUS, st);
        end while (!(((st & 32'hFE) != 0) && ((st & S_BUSY) == 0)) && (cyc - t0 < max_cycles));
    endtask

    // ---------------------------------------------------------------- LIN math (spec 9.3, 9.4)
    function automatic logic [7:0] pid_of(input logic [5:0] id);
        logic p0, p1;
        p0 = id[0] ^ id[1] ^ id[2] ^ id[4];
        p1 = ~(id[1] ^ id[3] ^ id[4] ^ id[5]);
        return {p1, p0, id};
    endfunction

    logic [7:0] dat [8];
    function automatic logic [7:0] cksum(input logic [7:0] seed, input int n);
        int s = seed;
        for (int i = 0; i < n; i++) begin
            s = s + dat[i];
            if (s > 255) s = s - 255;
        end
        return ~8'(s);
    endfunction

    // ---------------------------------------------------------------- expected waveform builder
    bit    exp_q [$];
    int    seg_at[$];
    string seg_nm[$];
    task automatic exp_clear(); exp_q.delete(); seg_at.delete(); seg_nm.delete(); endtask
    task automatic exp_bits(input bit v, input int n, input string nm);
        seg_at.push_back(exp_q.size()); seg_nm.push_back(nm);
        repeat (n) exp_q.push_back(v);
    endtask
    task automatic exp_byte(input logic [7:0] b, input string nm);
        seg_at.push_back(exp_q.size()); seg_nm.push_back(nm);
        repeat (DIV) exp_q.push_back(1'b0);
        for (int i = 0; i < 8; i++) repeat (DIV) exp_q.push_back(b[i]);
        repeat (DIV) exp_q.push_back(1'b1);
    endtask
    function automatic string seg_of(input int k);
        string nm = "?";
        int off = 0;
        for (int i = 0; i < seg_at.size(); i++)
            if (seg_at[i] <= k) begin nm = seg_nm[i]; off = k - seg_at[i]; end
        return $sformatf("%s, cycle %0d into it", nm, off);
    endfunction

    // Expected master-publish frame: break, delimiter, sync, PID, response space, data, checksum, idle.
    task automatic exp_publish(input logic [7:0] pidb, input int n, input bit enhanced);
        exp_clear();
        exp_bits(0, 13 * DIV, "break");
        exp_bits(1, DIV, "delimiter");
        exp_byte(8'h55, "sync byte");
        exp_byte(pidb, "PID byte");
        exp_bits(1, DIV, "response space");
        for (int i = 0; i < n; i++) exp_byte(dat[i], $sformatf("data byte %0d", i));
        exp_byte(cksum(enhanced ? pidb : 8'h00, n), "checksum byte");
        exp_bits(1, 4 * DIV, "idle after frame");
    endtask

    function automatic bit sample(input int which, input int i);
        return (which == 0) ? log_txm[i] : (which == 1) ? log_bus[i] : log_bfm[i];
    endfunction

    // Compare a log (0 = master tx, 1 = bus, 2 = testbench driver only) against exp_q starting at the first
    // dominant cycle at or after `from`. Returns the frame start in `i0`.
    task automatic cmp_wave(input string id, input int which, input int from, output int i0);
        int  k, lowrun;
        bit  v, ok;
        string why;
        i0 = -1;
        for (int i = from; i < from + 4000 && i < cyc && i < MAXC; i++) begin
            v = sample(which, i);
            if (!v) begin i0 = i; break; end
        end
        if (i0 < 0) begin check(id, 0, "no frame: line never went dominant"); return; end
        while (cyc < i0 + exp_q.size() + 2) @(posedge CLK);
        lowrun = 0;
        for (int i = i0; i < cyc && i < MAXC; i++) begin
            v = sample(which, i);
            if (v) break;
            lowrun++;
        end
        ok = 1; why = "";
        for (k = 0; k < exp_q.size(); k++) begin
            v = sample(which, i0 + k);
            if (v != exp_q[k]) begin
                ok = 0;
                why = $sformatf("first mismatch %0d cycles after break start (%s): expected %0b, got %0b; break low run = %0d cycles (expected %0d)",
                                k, seg_of(k), exp_q[k], v, lowrun, 13 * DIV);
                break;
            end
        end
        check(id, ok, ok ? $sformatf("frame matches bit-exactly (%0d cycles)", exp_q.size()) : why);
    endtask

    // ---------------------------------------------------------------- testbench-driven node (BFM)
    task automatic bfm_bits(input bit v, input int n);
        @(negedge CLK);
        bfm_drv = v;
        repeat (n) @(posedge CLK);
    endtask
    task automatic bfm_release();
        @(negedge CLK);
        bfm_drv = 1'b1;
    endtask
    task automatic bfm_byte(input logic [7:0] b, input bit stop = 1'b1);
        bfm_bits(0, DIV);
        for (int i = 0; i < 8; i++) bfm_bits(b[i], DIV);
        bfm_bits(stop, DIV);
        if (!stop) bfm_release();
    endtask
    task automatic bfm_header(input logic [7:0] sync_b, input logic [7:0] pid_b);
        bfm_bits(0, 13 * DIV);
        bfm_bits(1, DIV);
        bfm_byte(sync_b);
        bfm_byte(pid_b);
    endtask

    function automatic int first_low_after(input int which, input int from);
        for (int i = from; i < from + 4000 && i < cyc && i < MAXC; i++)
            if (!((which == 0) ? log_txm[i] : log_txs[i])) return i;
        return -1;
    endfunction
    function automatic int first_irq_after(input int which, input int from);
        for (int i = from; i < cyc && i < MAXC; i++)
            if ((which == 0) ? log_irqm[i] : log_irqs[i]) return i;
        return -1;
    endfunction

    // ================================================================= tests
    logic [31:0] r, st, stm, sts;
    int t, i0, t_irq, t_ref, n_brk;
    bit ok;

    initial begin
        idle_bus();
        repeat (3) @(negedge CLK);
        nRST = 1;
        repeat (2) @(negedge CLK);

        // ----------------------------------------------------------- CPT: harness self-test
        ok = (pid_of(6'h00) == 8'h80) && (pid_of(6'h01) == 8'hC1) && (pid_of(6'h10) == 8'h50) &&
             (pid_of(6'h23) == 8'hA3) && (pid_of(6'h3C) == 8'h3C) && (pid_of(6'h3D) == 8'h7D) &&
             (pid_of(6'h3F) == 8'hBF);
        check("CPT.01", ok, "harness PID function matches spec 9.3 vectors");
        dat[0] = 8'h4A; dat[1] = 8'h55; dat[2] = 8'h93; dat[3] = 8'hE5;
        ok = (cksum(8'h00, 4) == 8'hE6) && (cksum(8'hA3, 4) == 8'h43);
        dat[0] = 8'h01;
        ok = ok && (cksum(8'h00, 1) == 8'hFE) && (cksum(8'h50, 1) == 8'hAE);
        dat[0] = 8'hFF; dat[1] = 8'hFF;
        ok = ok && (cksum(8'h00, 2) == 8'h00);
        check("CPT.02", ok, "harness checksum function matches spec 9.4 vectors");
        // The testbench driver produces a full publish frame; the comparator must accept it.
        // Compared on the driver's own output (log 2), so this self-test does not depend on
        // the DUT: a DUT that holds tx low or X is caught by CP1.07 and CP2, not here.
        dat[0] = 8'h4A; dat[1] = 8'h55; dat[2] = 8'h93; dat[3] = 8'hE5;
        exp_publish(8'hA3, 4, 0);
        t = cyc;
        bfm_header(8'h55, 8'hA3);
        bfm_bits(1, DIV);
        for (int i = 0; i < 4; i++) bfm_byte(dat[i]);
        bfm_byte(cksum(8'h00, 4));
        bfm_bits(1, 6 * DIV);
        cmp_wave("CPT.03", 2, t, i0);

        // ----------------------------------------------------------- CP1: reset values and registers
        reset_all();
        rd(0, CTRL, r);   check("CP1.01", r == 0, $sformatf("reset CTRL = 0x%08h (expect 0)", r));
        rd(0, STATUS, r); check("CP1.02", r == 0, $sformatf("reset STATUS = 0x%08h (expect 0)", r));
        rd(0, BAUD, r);   check("CP1.03", r == 521, $sformatf("reset BAUD with default DEFAULT_DIV = %0d (expect 521)", r));
        rd(1, BAUD, r);   check("CP1.04", r == 16, $sformatf("reset BAUD with DEFAULT_DIV=16 = %0d (expect 16)", r));
        rd(0, PID, r);    check("CP1.05", r == 32'h80, $sformatf("reset PID = 0x%08h (expect 0x80)", r));
        ok = 1;
        rd(0, TXD0, r); ok &= (r == 0);
        rd(0, TXD1, r); ok &= (r == 0);
        rd(0, RXD0, r); ok &= (r == 0);
        rd(0, RXD1, r); ok &= (r == 0);
        rd(0, IRQEN, r); ok &= (r == 0);
        check("CP1.06", ok, "reset TXDATA0/1, RXDATA0/1, IRQ_EN all 0");
        check("CP1.07", (lm.tx === 1'b1) && (lm.tx_en === 1'b0) && (lm.irq === 1'b0) &&
                        (bm.error === 1'b0) && (bm.request_stall === 1'b0),
              $sformatf("reset pins: tx=%b tx_en=%b irq=%b error=%b request_stall=%b (expect 1 0 0 0 0)",
                        lm.tx, lm.tx_en, lm.irq, bm.error, bm.request_stall));
        wr(0, CTRL, 32'hFFFF_FFFF); rd(0, CTRL, r);
        check("CP1.08", r == 32'h7B, $sformatf("CTRL after writing all ones = 0x%08h (expect 0x7B: START reads 0, reserved 0)", r));
        repeat (2) @(negedge CLK);
        check("CP1.09", lm.tx_en === 1'b1, $sformatf("tx_en follows CTRL.EN=1: tx_en=%b", lm.tx_en));
        wr(0, CTRL, 0);
        wr(0, PID, 32'hFFFF_FFFF); rd(0, PID, r);
        check("CP1.10", r == 32'h1BF, $sformatf("PID after writing all ones = 0x%08h (expect 0x1BF: parity computed, reserved 0)", r));
        wr(0, PID, 32'h23); rd(0, PID, r);
        check("CP1.11", r == 32'hA3, $sformatf("PID after writing ID 0x23 = 0x%08h (expect 0xA3)", r));
        wr(0, BAUD, 5); rd(0, BAUD, r);
        check("CP1.12", r == 16, $sformatf("BAUD after writing 5 = %0d (expect 16)", r));
        wr(0, BAUD, 32'hFFFF_FFFF); rd(0, BAUD, r);
        check("CP1.13", r == 32'hFFFF, $sformatf("BAUD after writing all ones = 0x%08h (expect 0x0000FFFF)", r));
        wr(0, IRQEN, 32'hFFFF_FFFF); rd(0, IRQEN, r);
        check("CP1.14", r == 32'hFE, $sformatf("IRQ_EN after writing all ones = 0x%08h (expect 0xFE)", r));
        wr(0, IRQEN, 0);
        wr(0, TXD0, 32'hDEAD_BEEF); rd(0, TXD0, r);
        check("CP1.15", r == 32'hDEAD_BEEF, $sformatf("TXDATA0 read-back = 0x%08h", r));
        wr(0, TXD0, 32'h1122_3344, 4'b0010); rd(0, TXD0, r);
        check("CP1.16", r == 32'hDEAD_33EF, $sformatf("byte strobe 0010 wrote only lane 1: 0x%08h (expect 0xDEAD33EF)", r));
        wr(0, RXD0, 32'hFFFF_FFFF); rd(0, RXD0, r);
        check("CP1.17", r == 0, $sformatf("RXDATA0 is read-only: 0x%08h after write (expect 0)", r));
        wr(0, STATUS, 32'hFFFF_FFFF); rd(0, STATUS, r);
        check("CP1.18", r == 0, $sformatf("STATUS after writing all ones while idle = 0x%08h (expect 0)", r));
        wr(0, 32'h24, 32'hFFFF_FFFF); rd(0, 32'h24, r);
        check("CP1.19", r == 0, $sformatf("reserved offset 0x24 = 0x%08h after write (expect 0)", r));
        wr(0, PID, 32'h23); rd(0, 32'h0D, r);
        check("CP1.20", r == 32'hA3, $sformatf("addr[1:0] ignored: read at 0x0D = 0x%08h (expect PID 0xA3)", r));
        @(negedge CLK); bm.addr = PID; bm.ren = 0; #1;
        check("CP1.21", bm.rdata == 0, $sformatf("rdata with ren=0 = 0x%08h (expect 0)", bm.rdata));

        // ----------------------------------------------------------- CP2: master publish, wire-exact (single node, loopback)
        // CP2.01-02: ID 0x23, N=4, classic
        reset_all();
        dat[0] = 8'h4A; dat[1] = 8'h55; dat[2] = 8'h93; dat[3] = 8'hE5;
        wr(0, BAUD, DIV); wr(0, PID, 32'h23); wr(0, TXD0, 32'hE593_554A);
        t = cyc;
        wr(0, CTRL, EN | TXRESP | dlen(4) | START);
        wait_event(0, 6000, st);
        exp_publish(8'hA3, 4, 0);
        cmp_wave("CP2.01", 0, t, i0);
        check("CP2.02", st == S_DONE, $sformatf("STATUS after classic N=4 publish = 0x%02h (expect 0x02 DONE only)", st));
        check("CP2.03", (i0 >= 0) && (i0 - t <= 20), $sformatf("START to break start = %0d cycles (expect <= 20)", i0 - t));
        // CP2.04-05: same data, enhanced
        reset_all();
        wr(0, BAUD, DIV); wr(0, PID, 32'h123); wr(0, TXD0, 32'hE593_554A);
        t = cyc;
        wr(0, CTRL, EN | TXRESP | dlen(4) | START);
        wait_event(0, 6000, st);
        exp_publish(8'hA3, 4, 1);
        cmp_wave("CP2.04", 0, t, i0);
        check("CP2.05", st == S_DONE, $sformatf("STATUS after enhanced N=4 publish = 0x%02h (expect 0x02)", st));
        // CP2.06-07: ID 0x10, N=1 (DLEN=0), classic
        reset_all();
        dat[0] = 8'h01;
        wr(0, BAUD, DIV); wr(0, PID, 32'h10); wr(0, TXD0, 32'h01);
        t = cyc;
        wr(0, CTRL, EN | TXRESP | dlen(1) | START);
        wait_event(0, 6000, st);
        exp_publish(8'h50, 1, 0);
        cmp_wave("CP2.06", 0, t, i0);
        check("CP2.07", st == S_DONE, $sformatf("STATUS after N=1 publish = 0x%02h (expect 0x02)", st));
        // CP2.08-09: ID 0x01, N=8 (DLEN=7), enhanced
        reset_all();
        for (int i = 0; i < 8; i++) dat[i] = 8'(8'h11 * (i + 1));
        wr(0, BAUD, DIV); wr(0, PID, 32'h101);
        wr(0, TXD0, {dat[3], dat[2], dat[1], dat[0]}); wr(0, TXD1, {dat[7], dat[6], dat[5], dat[4]});
        t = cyc;
        wr(0, CTRL, EN | TXRESP | dlen(8) | START);
        wait_event(0, 8000, st);
        exp_publish(pid_of(6'h01), 8, 1);
        cmp_wave("CP2.08", 0, t, i0);
        check("CP2.09", st == S_DONE, $sformatf("STATUS after N=8 publish = 0x%02h (expect 0x02)", st));

        // ----------------------------------------------------------- CP3: two nodes and timeouts
        // CP3.01-04: master subscribes, slave publishes (ID 0x10, N=2, classic)
        reset_all();
        wr(1, BAUD, DIV); wr(1, PID, 32'h10); wr(1, TXD0, 32'h0000_5AA5);
        wr(1, CTRL, EN | MODE | TXRESP | dlen(2));
        wr(0, BAUD, DIV); wr(0, PID, 32'h10);
        wr(0, CTRL, EN | dlen(2) | START);
        wait_event(0, 8000, stm);
        repeat (20) @(negedge CLK);
        rd(1, STATUS, sts);
        rd(0, RXD0, r);
        check("CP3.01", r == 32'h0000_5AA5, $sformatf("master RXDATA0 = 0x%08h (expect 0x00005AA5)", r));
        check("CP3.02", stm == S_DONE, $sformatf("master STATUS = 0x%02h (expect 0x02)", stm));
        check("CP3.03", sts == S_DONE, $sformatf("slave STATUS = 0x%02h (expect 0x02)", sts));
        rd(0, RXD1, r);
        check("CP3.04", r == 0, $sformatf("master RXDATA1 = 0x%08h (expect 0; bytes past N stay 0)", r));
        // CP3.05-07: master publishes, slave subscribes (ID 0x23, N=4, enhanced)
        reset_all();
        wr(1, BAUD, DIV); wr(1, PID, 32'h123); wr(1, CTRL, EN | MODE | dlen(4));
        wr(0, BAUD, DIV); wr(0, PID, 32'h123); wr(0, TXD0, 32'hE593_554A);
        wr(0, CTRL, EN | TXRESP | dlen(4) | START);
        wait_event(0, 8000, stm);
        repeat (20) @(negedge CLK);
        rd(1, STATUS, sts);
        rd(1, RXD0, r);
        check("CP3.05", r == 32'hE593_554A, $sformatf("slave RXDATA0 = 0x%08h (expect 0xE593554A)", r));
        check("CP3.06", sts == S_DONE, $sformatf("slave STATUS = 0x%02h (expect 0x02)", sts));
        check("CP3.07", stm == S_DONE, $sformatf("master STATUS = 0x%02h (expect 0x02)", stm));
        // CP3.08-09: ID mismatch -> slave silent (LIN-FSM-07, T09)
        reset_all();
        wr(1, BAUD, DIV); wr(1, PID, 32'h11); wr(1, CTRL, EN | MODE | dlen(4));
        wr(0, BAUD, DIV); wr(0, PID, 32'h23); wr(0, TXD0, 32'hE593_554A);
        wr(0, CTRL, EN | TXRESP | dlen(4) | START);
        wait_event(0, 8000, stm);
        repeat (40) @(negedge CLK);
        rd(1, STATUS, sts);
        check("CP3.08", sts == 0, $sformatf("slave STATUS after a frame for another ID = 0x%02h (expect 0: silent, not busy)", sts));
        check("CP3.09", stm == S_DONE, $sformatf("master STATUS = 0x%02h (expect 0x02)", stm));
        // CP3.10-11: response timeout, N=1, no responder (LIN-PROT-08: 448 cycles after DATA entry)
        reset_all();
        wr(0, BAUD, DIV); wr(0, PID, 32'h10); wr(0, IRQEN, S_TIMEOUT);
        t = cyc;
        wr(0, CTRL, EN | dlen(1) | START);
        wait_event(0, 6000, st);
        check("CP3.10", st == S_TIMEOUT, $sformatf("STATUS after subscribe with no responder (N=1) = 0x%02h (expect 0x08)", st));
        i0 = first_low_after(0, t);
        t_ref = i0 + 13 * DIV + DIV + 20 * DIV;              // end of the PID stop bit
        t_irq = first_irq_after(0, t_ref);
        check("CP3.11", (i0 >= 0) && (t_irq >= 0) && (t_irq - t_ref >= 446) && (t_irq - t_ref <= 470),
              $sformatf("irq %0d cycles after PID stop bit end (expect 446..470: TIMEOUT at 448 + flag/irq latency)", t_irq - t_ref));
        // CP3.12: response timeout, N=8 (2016 cycles)
        reset_all();
        wr(0, BAUD, DIV); wr(0, PID, 32'h10); wr(0, IRQEN, S_TIMEOUT);
        t = cyc;
        wr(0, CTRL, EN | dlen(8) | START);
        wait_event(0, 6000, st);
        i0 = first_low_after(0, t);
        t_ref = i0 + 13 * DIV + DIV + 20 * DIV;
        t_irq = first_irq_after(0, t_ref);
        check("CP3.12", (st == S_TIMEOUT) && (t_irq - t_ref >= 2014) && (t_irq - t_ref <= 2038),
              $sformatf("N=8 timeout: STATUS=0x%02h, irq %0d cycles after PID end (expect 0x08, 2014..2038)", st, t_irq - t_ref));
        // CP3.13-14: slave header timeout (LIN-PROT-09: 28 T_bit from SYNC entry)
        reset_all();
        wr(1, BAUD, DIV); wr(1, PID, 32'h23); wr(1, IRQEN, S_TIMEOUT); wr(1, CTRL, EN | MODE | dlen(1));
        bfm_bits(0, 13 * DIV);
        t_ref = cyc;                                          // delimiter starts on the bus
        bfm_bits(1, 40 * DIV);
        rd(1, STATUS, sts);
        t_irq = first_irq_after(1, t_ref);
        check("CP3.13", sts == S_TIMEOUT, $sformatf("slave STATUS after break with no sync = 0x%02h (expect 0x08)", sts));
        check("CP3.14", (t_irq >= 0) && (t_irq - t_ref >= 448) && (t_irq - t_ref <= 476),
              $sformatf("slave irq %0d cycles after delimiter start (expect 448..476)", t_irq - t_ref));

        // ----------------------------------------------------------- CP4: error flags and control
        // CP4.01: PID parity error at the slave
        reset_all();
        wr(1, BAUD, DIV); wr(1, PID, 32'h23); wr(1, CTRL, EN | MODE | dlen(1));
        bfm_header(8'h55, 8'h23);                             // ID 0x23 with parity bits 00 (correct: 0xA3)
        bfm_bits(1, 20 * DIV);
        rd(1, STATUS, sts);
        check("CP4.01", sts == S_PID, $sformatf("slave STATUS after bad PID parity = 0x%02h (expect 0x80)", sts));
        // CP4.02: sync error at the slave
        reset_all();
        wr(1, BAUD, DIV); wr(1, PID, 32'h23); wr(1, CTRL, EN | MODE | dlen(1));
        bfm_header(8'h54, 8'hA3);
        bfm_bits(1, 20 * DIV);
        rd(1, STATUS, sts);
        check("CP4.02", sts == S_SYNC, $sformatf("slave STATUS after sync byte 0x54 = 0x%02h (expect 0x40)", sts));
        // CP4.03-04: checksum error at the master (BFM answers with a wrong checksum)
        reset_all();
        wr(0, BAUD, DIV); wr(0, PID, 32'h10);
        t = cyc;
        wr(0, CTRL, EN | dlen(1) | START);
        i0 = -1;
        while (i0 < 0) begin @(posedge CLK); i0 = first_low_after(0, t); end
        while (cyc < i0 + 13 * DIV + DIV + 20 * DIV + DIV) @(posedge CLK);
        bfm_byte(8'h01);
        bfm_byte(8'h00);                                      // correct classic checksum would be 0xFE
        wait_event(0, 3000, st);
        rd(0, RXD0, r);
        check("CP4.03", st == S_CKSUM, $sformatf("master STATUS after wrong checksum = 0x%02h (expect 0x04)", st));
        check("CP4.04", r[7:0] == 8'h01, $sformatf("RXDATA0 byte 0 = 0x%02h (expect 0x01, kept despite the error)", r[7:0]));
        // CP4.05: framing error at the master (data byte with stop bit 0)
        reset_all();
        wr(0, BAUD, DIV); wr(0, PID, 32'h10);
        t = cyc;
        wr(0, CTRL, EN | dlen(1) | START);
        i0 = -1;
        while (i0 < 0) begin @(posedge CLK); i0 = first_low_after(0, t); end
        while (cyc < i0 + 13 * DIV + DIV + 20 * DIV + DIV) @(posedge CLK);
        bfm_byte(8'h01, 1'b0);
        bfm_bits(1, 2 * DIV);
        wait_event(0, 3000, st);
        check("CP4.05", st == S_FRAME, $sformatf("master STATUS after stop bit 0 = 0x%02h (expect 0x20)", st));
        // CP4.06-08: bit error (BFM pulls the bus low during the sync stop bit)
        reset_all();
        wr(0, BAUD, DIV); wr(0, PID, 32'h23); wr(0, TXD0, 32'hE593_554A);
        t = cyc;
        wr(0, CTRL, EN | TXRESP | dlen(4) | START);
        i0 = -1;
        while (i0 < 0) begin @(posedge CLK); i0 = first_low_after(0, t); end
        while (cyc < i0 + 13 * DIV + DIV + 9 * DIV) @(posedge CLK);
        bfm_bits(0, DIV);
        bfm_release();
        wait_event(0, 3000, st);
        check("CP4.06", st == S_BIT, $sformatf("master STATUS after forced bit error = 0x%02h (expect 0x10)", st));
        t = cyc;
        repeat (100) @(posedge CLK);
        ok = 1;
        for (int i = t; i < t + 90; i++) ok &= log_txm[i];
        check("CP4.07", ok, "master tx returns to recessive and stays there after the bit error");
        wr(0, STATUS, S_DONE); rd(0, STATUS, r);
        ok = (r == S_BIT);
        wr(0, STATUS, S_BIT); rd(0, STATUS, st);
        check("CP4.08", ok && (st == 0), $sformatf("W1C: writing DONE leaves 0x%02h (expect 0x10); writing BIT_ERR leaves 0x%02h (expect 0)", r, st));
        // CP4.09-11: interrupt
        reset_all();
        dat[0] = 8'h01;
        wr(0, BAUD, DIV); wr(0, PID, 32'h10); wr(0, TXD0, 32'h01); wr(0, IRQEN, S_DONE);
        wr(0, CTRL, EN | TXRESP | dlen(1) | START);
        wait_event(0, 6000, st);
        repeat (3) @(negedge CLK);
        check("CP4.09", lm.irq === 1'b1, $sformatf("irq with IRQ_EN.DONE after a frame = %b (expect 1)", lm.irq));
        wr(0, STATUS, S_DONE);
        repeat (3) @(negedge CLK);
        check("CP4.10", lm.irq === 1'b0, $sformatf("irq after W1C of DONE = %b (expect 0)", lm.irq));
        wr(0, IRQEN, 0);
        wr(0, CTRL, EN | TXRESP | dlen(1) | START);
        wait_event(0, 6000, st);
        repeat (3) @(negedge CLK);
        check("CP4.11", (st == S_DONE) && (lm.irq === 1'b0), $sformatf("masked: STATUS=0x%02h irq=%b (expect 0x02, 0)", st, lm.irq));
        // CP4.12: EN=0 abort mid-frame (LIN-FSM-03)
        reset_all();
        for (int i = 0; i < 8; i++) dat[i] = 8'(8'h11 * (i + 1));
        wr(0, BAUD, DIV); wr(0, PID, 32'h23);
        wr(0, TXD0, {dat[3], dat[2], dat[1], dat[0]}); wr(0, TXD1, {dat[7], dat[6], dat[5], dat[4]});
        wr(0, CTRL, EN | TXRESP | dlen(8) | START);
        repeat (300) @(negedge CLK);
        wr(0, CTRL, 0);
        repeat (4) @(negedge CLK);
        rd(0, STATUS, st);
        t = cyc;
        repeat (60) @(posedge CLK);
        ok = 1;
        for (int i = t; i < t + 50; i++) ok &= log_txm[i];
        check("CP4.12", (st == 0) && ok, $sformatf("after EN=0 mid-frame: STATUS=0x%02h, tx idle=%b (expect 0x00, 1)", st, ok));
        // CP4.13: START held for 2 cycles starts exactly one frame (LIN-IF-10)
        reset_all();
        dat[0] = 8'h01;
        wr(0, BAUD, DIV); wr(0, PID, 32'h10); wr(0, TXD0, 32'h01);
        t = cyc;
        wr(0, CTRL, EN | TXRESP | dlen(1) | START, 4'hF, 2);
        repeat (4000) @(posedge CLK);
        rd(0, STATUS, st);
        n_brk = 0;
        for (int i = t; i < cyc - 13 * DIV; i++) begin
            if (log_txm[i] && !log_txm[i + 1]) begin
                ok = 1;
                for (int k = 1; k <= 11 * DIV; k++) ok &= !log_txm[i + k];
                if (ok) n_brk++;
            end
        end
        check("CP4.13", (n_brk == 1) && (st == S_DONE), $sformatf("2-cycle START write: %0d break(s) on the wire, STATUS=0x%02h (expect 1, 0x02)", n_brk, st));
        // CP4.14: write protection while BUSY (LIN-REG-04)
        reset_all();
        wr(0, BAUD, DIV); wr(0, PID, 32'h23);
        wr(0, CTRL, EN | TXRESP | dlen(8) | START);
        repeat (50) @(negedge CLK);
        wr(0, BAUD, 100); wr(0, PID, 32'h3F);
        wait_event(0, 8000, st);
        rd(0, BAUD, r);
        rd(0, PID, stm);
        check("CP4.14", (r == DIV) && (stm == 32'hA3), $sformatf("after writes during BUSY: BAUD=%0d PID=0x%02h (expect 16, 0xA3)", r, stm));

        $display("TB_DONE fails=%0d", n_fail);
        $finish;
    end

    // global watchdog
    initial begin
        #(64'd60_000_000);
        $display("TB_WATCHDOG simulation exceeded time limit");
        $finish;
    end
endmodule
