// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) Paul Priest
//
// Save-state access to a 68000-family CPU's registers, through its own bus:
// MODE 1, TG68K.C as the 68EC020; MODE 0, fx68k as the 68000; MODE 2, TG68K.C
// as the 68000. Neither core has a register port.
//
// [SB] Modified for Arcade-Pandora_MiSTer from Arcade-KonamiGX_MiSTer 89124d4: the
// M020 parameter became MODE, and MODE 2 was added. Lines changed are marked [SB].
//
// On `req` this forces a level-7 interrupt and, once it is taken, serves
// the vector and a stub from STUB. The stub stores D0-D7/A0-A6, USP (and on
// the 68020 VBR and CACR) and A7 into a bank at CAP, then loads them all
// back and ends in RTE. The exception frame the entry pushes goes into the
// bank too, and RTE's frame reads come from it. Between the two halves the
// stub's first read of CAP is held: `held` is high, the bank is complete,
// and the engine may read it or overwrite it (a load) through b_*. `go` lets
// the stub continue, and the RTE resumes whatever the bank holds. `done`
// pulses when RTE's last frame read is taken; the next access is the
// resumed program's.
//
// The sequences, measured in sim/gx_ss_cpu_tb (TG68K.C) and sim/gx_ss_fx_tb
// (fx68k):
//   68020 entry: IACK (FC 7, FFFFFFFE), then writes of the format word at
//         A7+6, PC high at A7+2, PC low at A7+4, SR at A7, then the vector
//   68000 entry: a write of PC low at A7+4, then IACK (answered by the
//         board's VPA), then SR at A7, PC high at A7+2, then the vector
//   TG68K.C as 68000 entry: IACK (FC 7, FFFFFFFE), then PC high at A7+2,
//         PC low at A7+4, SR at A7, then the vector (sim/ss_m68k_tb)  [SB]
//   RTE:  SR, PC high, PC low, and on the 68020 the format word
// The 68000's PC-low push comes before anything says the interrupt is this
// one, so it goes to the board: two bytes below the stack pointer, where
// any interrupt writes. It is recorded on the way. Everything else of the
// sequence is answered here and never reaches the board. TG68K.C takes
// level 7 again for as long as it is held, so IPL is released at the
// acknowledge.
//
// A CPU waiting in STOP is woken with PC past the STOP. `stop_in` (TG68K.C:
// its stop flag; fx68k: IRD is STOP) is sampled while the interrupt is
// pending, and when it was set RTE returns to PC - 4, the STOP itself,
// which loads the same SR and waits again. MAME keeps the same convention:
// PC past the STOP and a stopped flag.
//
// Bank, 32-bit words at CAP + 4i:
//   0-7 D0-D7   8-14 A0-A6   15 USP   16 VBR   17 CACR   (68000: 16, 17 unused)
//   18 A7 inside the stub (ISP - 8; 68000: SSP - 6)
//   19 SR   20 PC   21 the 68020's frame format word   22 bit 0: stopped

module gx_ss_m68k #(
    parameter MODE = 1                  // [SB]
) (
    input             clk,
    input             rst,

    // the CPU's bus
    input             acc,          // an access is on the bus (68000: not the IACK)
    input             take,         // ...and completes this clock (68000: is first seen)
    input      [31:0] a32,
    input             wr,
    input      [ 2:0] fc,
    input      [15:0] dout,
    input             iack7,        // 68000: the level-7 acknowledge is on the bus
    input             stop_in,

    input             req,          // take the CPU at its next instruction boundary
    output reg        ipl7,         // force IPL 7
    output            hit,          // this access is answered here; the board ignores it
    output            rdy,          // ...and it completes now (low: held)
    output reg [15:0] din,
    output            held,
    input             go,
    output reg        done,

    input      [ 4:0] b_idx,
    input             b_we,
    input      [31:0] b_d,
    output     [31:0] b_q
);

localparam M020 = MODE == 1;           // [SB]
localparam TG   = MODE != 0;           // [SB] TG68K.C: the IACK is on the bus
localparam [31:0] STUB = M020 ? 32'hFFFF_0000 : 32'h00FF_0000;
localparam [31:0] CAP  = M020 ? 32'hFFFF_8000 : 32'h00FF_8000;
localparam [1:0]  NFR  = M020 ? 2'd3 : 2'd2;   // RTE frame reads, less one

localparam [2:0] S_IDLE = 3'd0, S_ARM = 3'd1, S_ENTRY = 3'd2, S_STUB = 3'd3,
                 S_RUN = 3'd4;

reg  [2:0]  st;
reg  [1:0]  fw, fr;                 // frame writes / RTE frame reads taken
reg         go_l;

// The bank. Words 0-18 are only ever written whole (b_we) or a half at a
// time (the stub's stores), so they are small memories with asynchronous
// reads -- MLABs, not 600 registers -- in two copies, one read by the
// engine (b_idx) and one by the bus (ci), each in high and low halves.
// Words 19-22 (SR, PC, the format word, stopped) are registers: they are
// read and written piecemeal.
(* ramstyle = "MLAB, no_rw_check" *) reg [15:0] ea_h [0:18];
(* ramstyle = "MLAB, no_rw_check" *) reg [15:0] ea_l [0:18];
(* ramstyle = "MLAB, no_rw_check" *) reg [15:0] eb_h [0:18];
(* ramstyle = "MLAB, no_rw_check" *) reg [15:0] eb_l [0:18];
reg  [31:0] f19, f20, f21, f22;
reg         mw_h, mw_l;                 // this clock's memory write
reg  [ 4:0] mw_a;
reg  [15:0] mw_dh, mw_dl;

wire        in_stub = a32[31:8] == STUB[31:8];
wire        in_cap  = a32[31:8] == CAP[31:8];
wire [4:0]  ci      = a32[6:2];
wire        ack7    = TG && fc == 3'd7 && a32[3:1] == 3'd7;   // [SB]

assign hit  = acc && (st == S_ARM ? ack7 : st == S_ENTRY || st == S_STUB || st == S_RUN);
// the stub's first CAP read waits for `go`
wire   hold = st == S_STUB && in_cap && !wr && !go_l;
assign held = hit && hold;
assign rdy  = hit && !hold;
assign b_q  = b_idx == 5'd19 ? f19 : b_idx == 5'd20 ? f20 : b_idx == 5'd21 ? f21 :
              b_idx == 5'd22 ? f22 : { ea_h[b_idx], ea_l[b_idx] };
wire [31:0] cap_q = { eb_h[ci], eb_l[ci] };     // CAP reads are of words 0-18 only

// RTE's PC: back onto the STOP when the CPU was waiting in one
wire [31:0] rte_pc = f22[0] ? f20 - 32'd4 : f20;

// the stub (see the header); NOPs past the RTE cover prefetch. The 68000
// has no MOVEC: those words are NOPs, and its VBR/CACR slots get A0 again.
reg [15:0] stub_w;
always @* begin
    case (a32[6:1])
        6'h00: stub_w = 16'h48F9; 6'h01: stub_w = 16'h7FFF;   // MOVEM.L D0-A6,CAP
        6'h02: stub_w = CAP[31:16]; 6'h03: stub_w = CAP[15:0];
        6'h04: stub_w = 16'h4E68;                             // MOVE USP,A0
        6'h05: stub_w = 16'h23C8; 6'h06: stub_w = CAP[31:16]; 6'h07: stub_w = 16'h803C;  // MOVE.L A0,CAP+60
        6'h08: stub_w = M020 ? 16'h4E7A : 16'h4E71;           // MOVEC VBR,A0
        6'h09: stub_w = M020 ? 16'h8801 : 16'h4E71;
        6'h0A: stub_w = 16'h23C8; 6'h0B: stub_w = CAP[31:16]; 6'h0C: stub_w = 16'h8040;  // MOVE.L A0,CAP+64
        6'h0D: stub_w = M020 ? 16'h4E7A : 16'h4E71;           // MOVEC CACR,A0
        6'h0E: stub_w = M020 ? 16'h8002 : 16'h4E71;
        6'h0F: stub_w = 16'h23C8; 6'h10: stub_w = CAP[31:16]; 6'h11: stub_w = 16'h8044;  // MOVE.L A0,CAP+68
        6'h12: stub_w = 16'h23CF; 6'h13: stub_w = CAP[31:16]; 6'h14: stub_w = 16'h8048;  // MOVE.L A7,CAP+72
        6'h15: stub_w = 16'h2079; 6'h16: stub_w = CAP[31:16]; 6'h17: stub_w = 16'h8044;  // MOVEA.L CAP+68,A0
        6'h18: stub_w = M020 ? 16'h4E7B : 16'h4E71;           // MOVEC A0,CACR
        6'h19: stub_w = M020 ? 16'h8002 : 16'h4E71;
        6'h1A: stub_w = 16'h2079; 6'h1B: stub_w = CAP[31:16]; 6'h1C: stub_w = 16'h8040;  // MOVEA.L CAP+64,A0
        6'h1D: stub_w = M020 ? 16'h4E7B : 16'h4E71;           // MOVEC A0,VBR
        6'h1E: stub_w = M020 ? 16'h8801 : 16'h4E71;
        6'h1F: stub_w = 16'h2079; 6'h20: stub_w = CAP[31:16]; 6'h21: stub_w = 16'h803C;  // MOVEA.L CAP+60,A0
        6'h22: stub_w = 16'h4E60;                             // MOVE A0,USP
        6'h23: stub_w = 16'h2E79; 6'h24: stub_w = CAP[31:16]; 6'h25: stub_w = 16'h8048;  // MOVEA.L CAP+72,A7
        6'h26: stub_w = 16'h4CF9; 6'h27: stub_w = 16'h7FFF;   // MOVEM.L CAP,D0-A6
        6'h28: stub_w = CAP[31:16]; 6'h29: stub_w = CAP[15:0];
        6'h2A: stub_w = 16'h4E73;                             // RTE
        default: stub_w = 16'h4E71;                           // NOP
    endcase
end

always @* begin
    din = 16'h0000;
    if (in_stub)
        din = stub_w;
    else if (in_cap)
        din = a32[1] ? cap_q[15:0] : cap_q[31:16];
    else if (st == S_ENTRY)                                   // the vector
        din = a32[1] ? STUB[15:0] : STUB[31:16];
    else                                                      // RTE's frame
        case (st == S_RUN ? fr : 2'd0)
            2'd0: din = f19[15:0];
            2'd1: din = rte_pc[31:16];
            2'd2: din = rte_pc[15:0];
            2'd3: din = f21[15:0];
        endcase
end

// the memory words' writes: the engine's (while the CPU is held), or the
// stub's stores of its registers
always @* begin
    mw_h = 1'b0; mw_l = 1'b0; mw_a = b_idx; mw_dh = b_d[31:16]; mw_dl = b_d[15:0];
    if (b_we && b_idx < 5'd19) begin
        mw_h = 1'b1; mw_l = 1'b1;
    end else if (st == S_STUB && take && hit && wr && in_cap && ci < 5'd19) begin
        mw_a = ci; mw_dh = dout; mw_dl = dout;
        mw_h = !a32[1]; mw_l = a32[1];
    end
end
always @(posedge clk) begin
    if (mw_h) begin ea_h[mw_a] <= mw_dh; eb_h[mw_a] <= mw_dh; end
    if (mw_l) begin ea_l[mw_a] <= mw_dl; eb_l[mw_a] <= mw_dl; end
end

always @(posedge clk) begin
    done <= 1'b0;
    if (rst) begin
        st <= S_IDLE; ipl7 <= 1'b0; go_l <= 1'b0; fw <= 2'd0; fr <= 2'd0;
    end else begin
        if (b_we)
            case (b_idx)
                5'd19: f19 <= b_d;
                5'd20: f20 <= b_d;
                5'd21: f21 <= b_d;
                5'd22: f22 <= b_d;
                default: ;
            endcase
        if (go) go_l <= 1'b1;
        case (st)
            S_IDLE: if (req) begin
                st <= S_ARM; ipl7 <= 1'b1; go_l <= 1'b0; fw <= 2'd0; fr <= 2'd0;
                f22 <= 32'd0;
            end
            S_ARM: begin
                if (stop_in) f22[0] <= 1'b1;
                // the 68000's last write before its acknowledge is PC low
                if (!TG && acc && take && wr) f20[15:0] <= dout;            // [SB]
                if (TG ? (take && hit) : iack7) begin                       // [SB]
                    st <= S_ENTRY; ipl7 <= 1'b0;
                    f21 <= 32'd0;
                end
            end
            S_ENTRY: if (take && hit) begin
                if (wr && !in_cap) begin
                    fw <= fw + 2'd1;
                    if (M020)
                        case (fw)
                            2'd0: f21 <= {16'd0, dout};
                            2'd1: f20[31:16] <= dout;
                            2'd2: f20[15:0] <= dout;
                            2'd3: f19 <= {16'd0, dout};
                        endcase
                    else if (TG)                                            // [SB]
                        case (fw)
                            2'd0: f20[31:16] <= dout;
                            2'd1: f20[15:0] <= dout;
                            default: f19 <= {16'd0, dout};
                        endcase
                    else
                        case (fw)
                            2'd0: f19 <= {16'd0, dout};
                            default: f20[31:16] <= dout;
                        endcase
                end
                if (!wr && in_stub) st <= S_STUB;
            end
            S_STUB: if (take && hit) begin
                // (its stores into CAP: the memory words, above)
                if (!wr && !in_cap && !in_stub) begin       // after RTE: its frame reads
                    st <= S_RUN; fr <= 2'd1;
                end
            end
            S_RUN: if (take && hit) begin
                fr <= fr + 2'd1;
                if (fr == NFR) begin st <= S_IDLE; done <= 1'b1; end
            end
            default: st <= S_IDLE;
        endcase
    end
end

endmodule
