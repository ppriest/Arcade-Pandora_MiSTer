// SPDX-License-Identifier: GPL-3.0-or-later
// Copied from Arcade-KonamiGX_MiSTer 89124d4; [SB] the module parameter M020 is now MODE.
//
// rtl/cpu/gx_ss_m68k.sv (M020 = 1) against TG68K.C in 68020 mode: the save-state
// stub's capture and restore, self-checking.
//     scripts/run_verilator.sh gx_ss_cpu_tb             all three tests
//     scripts/run_verilator.sh gx_ss_cpu_tb +LOG=1      and every access
//
// A  capture and resume, at several points of a loop that stores an
//    incrementing D0 through (A1)+: the stores stay one sequence, the bank
//    holds the D0/A1 the stores imply, and no access of the sequence
//    reaches memory.
// B  a load: the bank is overwritten while held (D0, A1, and once PC/SR),
//    and the loop continues from the new values.
// C  STOP: a CPU waiting in STOP #$2000 for a level-1 interrupt is taken,
//    returns to the STOP, waits again, and wakes on the next level 1.
`timescale 1ns/1ps

module tb_gx_ss_cpu;

logic clk = 0, reset = 1;
always #5 clk = ~clk;

byte unsigned mem [0:65535];

logic [31:0] a32;
logic [15:0] cpu_dout, mem_q;
logic [1:0]  busstate;
logic        nWr, nUDS, nLDS, stop;
logic [2:0]  fc;
logic        irq1 = 0;
logic        ready = 0;
wire         mem_needed = busstate != 2'b01;

logic        req = 0, go = 0;
logic [4:0]  b_idx = 0;
logic        b_we = 0;
logic [31:0] b_d = 0, b_q;
wire         ss_hit, ss_rdy, ss_held, ss_done, ss_ipl7;
wire  [15:0] ss_din;
wire         cpu_clkena = !mem_needed || (ss_hit ? ss_rdy : ready);
wire  [2:0]  ipl_n = ss_ipl7 ? 3'b000 : irq1 ? 3'b110 : 3'b111;

TG68KdotC_Kernel #(
    .SR_Read(2), .VBR_Stackframe(2), .extAddr_Mode(2),
    .MUL_Mode(2), .DIV_Mode(2), .BitField(2),
    .BarrelShifter(0), .MUL_Hardware(1)
) u_cpu (
    .clk(clk), .nReset(~reset), .clkena_in(cpu_clkena),
    .data_in(ss_hit ? ss_din : mem_q), .IPL(ipl_n), .IPL_autovector(1'b1), .berr(1'b0),
    .CPU(2'b11),
    .addr_out(a32), .data_write(cpu_dout),
    .nWr(nWr), .nUDS(nUDS), .nLDS(nLDS),
    .busstate(busstate), .longword(), .nResetOut(), .FC(fc),
    .clr_berr(), .skipFetch(), .regin_out(), .CACR_out(), .VBR_out(), .FlagsSR_out(),
    .stop_out(stop)
);

gx_ss_m68k #(.MODE(1)) u_ss (
    .clk(clk), .rst(reset),
    .acc(mem_needed), .take(mem_needed && cpu_clkena), .a32(a32), .wr(busstate == 2'b11),
    .fc(fc), .dout(cpu_dout), .iack7(1'b0), .stop_in(stop),
    .req(req), .ipl7(ss_ipl7), .hit(ss_hit), .rdy(ss_rdy), .din(ss_din),
    .held(ss_held), .go(go), .done(ss_done),
    .b_idx(b_idx), .b_we(b_we), .b_d(b_d), .b_q(b_q)
);

wire [15:0] a = a32[15:0];
assign mem_q = {mem[{a[15:1], 1'b0}], mem[{a[15:1], 1'b1}]};

int log_on = 0, fails = 0, leaks = 0;
// stores the program makes, in order
int unsigned st_a [$], st_d [$];
logic [15:0] hi_w;

always_ff @(posedge clk) begin
    if (reset) ready <= 0;
    else if (cpu_clkena && mem_needed) ready <= 0;
    else if (mem_needed && !ready && !ss_hit) begin
        if (a32[31:16] != 0 && fc != 3'd7) begin
            leaks++;
            $display("LEAK: %s %08x reached memory", busstate == 2'b11 ? "write" : "read", a32);
        end
        if (busstate == 2'b11) begin
            if (!nUDS) mem[{a[15:1], 1'b0}] <= cpu_dout[15:8];
            if (!nLDS) mem[{a[15:1], 1'b1}] <= cpu_dout[7:0];
            if (a >= 16'h2000 && a < 16'h8000 - 16'h100) begin
                if (!a[1]) hi_w <= cpu_dout;
                else begin st_a.push_back({a[15:2], 2'b00}); st_d.push_back({hi_w, cpu_dout}); end
            end
        end
        // level 1 is cleared by its acknowledge
        if (fc == 3'd7 && a32[3:1] == 3'd1) irq1 <= 0;
        ready <= 1;
    end
    if (log_on != 0 && mem_needed && cpu_clkena)
        $display("%s%s fc%0d %08x %04x", ss_hit ? "*" : " ",
            busstate == 2'b00 ? "F" : busstate == 2'b10 ? "R" : "W", fc, a32,
            busstate == 2'b11 ? cpu_dout : ss_hit ? ss_din : mem_q);
end

task automatic w16(input int ad, input int v);
    mem[ad] = v[15:8]; mem[ad + 1] = v[7:0];
endtask
task automatic w32(input int ad, input int v);
    w16(ad, v >>> 16); w16(ad + 2, v & 16'hFFFF);
endtask
function automatic int unsigned r32(input int ad);
    return {mem[ad], mem[ad + 1], mem[ad + 2], mem[ad + 3]};
endfunction

task automatic check(input bit ok, input string what);
    if (!ok) begin fails++; $display("FAIL %s", what); end
endtask

task automatic bank_rd(input int i, output int unsigned v);
    b_idx = i[4:0]; #1; v = b_q;
endtask
task automatic bank_wr(input int i, input int unsigned v);
    @(negedge clk) begin b_idx = i[4:0]; b_d = v; b_we = 1; end
    @(negedge clk) b_we = 0;
endtask

// take the CPU; leaves it held
task automatic take();
    int t = 0;
    @(negedge clk) req = 1;
    @(negedge clk) req = 0;
    while (!ss_held) begin @(posedge clk); t++; if (t > 2000) $fatal(1, "never held"); end
endtask
task automatic release_cpu();
    int t = 0;
    @(negedge clk) go = 1;
    @(negedge clk) go = 0;
    while (!ss_done) begin @(posedge clk); t++; if (t > 2000) $fatal(1, "never done"); end
endtask

// every store continues the one before, from index `from`
task automatic check_run(input int from, input string what);
    for (int i = from + 1; i < st_a.size(); i++)
        if (st_a[i] != st_a[i - 1] + 4 || st_d[i] != st_d[i - 1] + 1) begin
            check(0, $sformatf("%s: store %0d %08x=%08x after %08x=%08x", what, i,
                  st_a[i], st_d[i], st_a[i - 1], st_d[i - 1]));
            break;
        end
endtask

string test;
int unsigned d0, a1, pc, sr, fmt, a7, flags, usp, vbr;

initial begin
    int p, n0;
    void'($value$plusargs("LOG=%d", log_on));
    foreach (mem[i]) mem[i] = 0;
    w32(0, 32'h00008000);                   // SSP
    w32(4, 32'h00000400);                   // PC
    w32(32'h64, 32'h00000620);              // level 1 autovector
    w32(32'h7C, 32'h00000600);              // level 7: must never be used
    w16(32'h600, 16'h4AFC);                 // ILLEGAL
    w16(32'h620, 16'h4E73);                 // level 1 handler: RTE
    p = 32'h400;
    w16(p, 16'h203C); w32(p + 2, 32'h11111111); p += 6;   // MOVE.L #,D0
    w16(p, 16'h227C); w32(p + 2, 32'h00002000); p += 6;   // MOVEA.L #$2000,A1
    w16(p, 16'h46FC); w16(p + 2, 16'h2000); p += 4;       // MOVE #$2000,SR
    w16(p, 16'h5280); p += 2;                              // 410 ADDQ.L #1,D0
    w16(p, 16'h22C0); p += 2;                              // 412 MOVE.L D0,(A1)+
    w16(p, 16'h60FA); p += 2;                              // 414 BRA.S 410
    w16(p, 16'h4E72); w16(p + 2, 16'h0700);                // 416 (never reached)

    repeat (4) @(posedge clk);
    reset = 0;

    // ---- A: capture and resume
    for (int k = 0; k < 6; k++) begin
        repeat (97 + 13 * k) @(posedge clk);
        take();
        n0 = st_a.size();
        repeat (40) @(posedge clk);
        bank_rd(0, d0); bank_rd(9, a1); bank_rd(20, pc); bank_rd(19, sr);
        bank_rd(21, fmt); bank_rd(18, a7); bank_rd(22, flags);
        check(fmt == 32'h007C, $sformatf("A%0d format word %04x", k, fmt));
        check(a7 == 32'h7FF8, $sformatf("A%0d A7 in the stub %08x", k, a7));
        check(sr == 32'h2000, $sformatf("A%0d SR %04x", k, sr));
        check(flags == 0, $sformatf("A%0d stopped %0d", k, flags));
        check(pc >= 32'h410 && pc <= 32'h414, $sformatf("A%0d PC %08x", k, pc));
        // the stores so far end at A1 - 4 with D0 or D0 - 1
        check(st_a.size() == n0, $sformatf("A%0d stores while held: %0d -> %0d, last %08x=%08x", k, n0, st_a.size(), st_a[$], st_d[$]));
        check(st_a[$] == a1 - 4 && (st_d[$] == d0 || st_d[$] == d0 - 1),
              $sformatf("A%0d bank D0 %08x A1 %08x, last store %08x=%08x", k, d0, a1, st_a[$], st_d[$]));
        release_cpu();
    end
    repeat (200) @(posedge clk);
    check_run(0, "A");
    $display("A: %0d stores, 6 captures", st_a.size());

    // ---- B: load D0/A1, then PC/SR too
    take();
    bank_wr(0, 32'h50000000); bank_wr(9, 32'h3000);
    n0 = st_a.size();
    release_cpu();
    repeat (200) @(posedge clk);
    check(st_a[n0] == 32'h3000 && (st_d[n0] == 32'h50000000 || st_d[n0] == 32'h50000001),
          $sformatf("B first store %08x=%08x", st_a[n0], st_d[n0]));
    check_run(n0, "B");
    take();
    bank_wr(0, 32'h70000000); bank_wr(9, 32'h5000); bank_wr(20, 32'h410); bank_wr(19, 32'h2000);
    n0 = st_a.size();
    release_cpu();
    repeat (200) @(posedge clk);
    check(st_a[n0] == 32'h5000 && st_d[n0] == 32'h70000001,
          $sformatf("B PC load: first store %08x=%08x", st_a[n0], st_d[n0]));
    check_run(n0, "B PC");
    $display("B: loads continue from the bank");

    // ---- C: STOP. Reprogram the loop as STOP / store D2 / BRA.
    take();
    p = 32'h500;
    w16(p, 16'h4E72); w16(p + 2, 16'h2000);                // 500 STOP #$2000
    w16(p + 4, 16'h5282);                                  // 504 ADDQ.L #1,D2
    w16(p + 6, 16'h24C2);                                  // 506 MOVE.L D2,(A2)+
    w16(p + 8, 16'h60F6);                                  // 508 BRA.S 500
    bank_wr(2, 32'h0); bank_wr(10, 32'h6000); bank_wr(20, 32'h500); bank_wr(19, 32'h2000);
    release_cpu();
    while (!stop) @(posedge clk);
    repeat (50) @(posedge clk);
    n0 = st_a.size();
    take();
    bank_rd(22, flags); bank_rd(20, pc);
    check(flags == 1, $sformatf("C stopped %0d", flags));
    check(pc == 32'h504, $sformatf("C PC %08x (past the STOP)", pc));
    release_cpu();
    repeat (100) @(posedge clk);
    check(stop == 1, "C back in STOP");
    check(st_a.size() == n0, "C a store without an interrupt");
    @(negedge clk) irq1 = 1;
    repeat (200) @(posedge clk);
    check(st_a.size() == n0 + 1 && st_a[n0] == 32'h6000 && st_d[n0] == 1,
          $sformatf("C level 1 wakes it: %0d stores", st_a.size() - n0));
    check(stop == 1, "C waiting again");
    $display("C: STOP kept across a capture");

    check(leaks == 0, $sformatf("%0d accesses reached memory", leaks));
    if (fails != 0) $fatal(1, "%0d check(s) FAILED", fails);
    $display("ALL PASS");
    $finish;
end

endmodule
