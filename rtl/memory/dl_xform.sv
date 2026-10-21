// SPDX-License-Identifier: GPL-3.0-or-later
// The download's ROM transforms, on every write into SDRAM (the byte stream and the DDR3
// copy both pass here, ahead of the arbiter's write port):
//
//   graphics   row-linear (scripts/gfx_layout_check.py): within each 128-byte tile the byte
//              address bits are permuted, and SemiCom's layout also swaps nibbles
//                Toaplan  dst = {s6, s4, s3, s2, s5, s1, s0}
//                SemiCom  dst = {s4, s6, s2, s3, s0, s1, s5}, nibbles swapped
//   toto       bits 3 and 4 of every byte of maincpu, gfx1 and soundcpu (init_toto, 3295-3320)
//   4in1boot   bits 6 and 7 of the even maincpu bytes, the 68000's high byte (MAME's `i & 1`
//              indexes a region byte-swapped onto a little-endian host); the sound ROM at
//              address ^ 0x4000 (init_4in1boot, 3193-3217)
//
// A two-byte write whose bytes stay adjacent and in order stays one write; otherwise it is
// split into two single-byte writes (a single-byte write carries its byte in the low lane, the
// lane chosen by address bit 0, sdram_phy).
//
// Both sides use the arbiter's write contract: req held until busy rises, then busy falls when
// the write is done; addr and data are held throughout.

module dl_xform #(
	parameter logic [24:0] MAINCPU_BASE = 25'h0000000,
	parameter logic [24:0] GFX_BASE     = 25'h0100000,
	parameter logic [24:0] SOUND_BASE   = 25'h0300000
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        gfx_semicom,
	input  logic        toto,
	input  logic        x4in1,

	input  logic        s_req,
	input  logic [24:0] s_addr,
	input  logic [15:0] s_data,
	input  logic        s_we16,
	output logic        s_busy,

	output logic        d_req,
	output logic [24:0] d_addr,
	output logic [15:0] d_data,
	output logic        d_we16,
	input  logic        d_busy
);
	function automatic logic [7:0] swap34(input logic [7:0] b);
		swap34 = {b[7:5], b[3], b[4], b[2:0]};
	endfunction

	// one byte: where it goes and what it becomes
	function automatic logic [32:0] xbyte(input logic [24:0] a, input logic [7:0] b,
	                                      input logic semi, input logic tt, input logic x4);
		logic [24:0] o;
		logic [7:0]  v;
		logic [6:0]  s;
		o = a; v = b;
		if (a >= MAINCPU_BASE && a < MAINCPU_BASE + 25'h0100000) begin
			if (tt) v = swap34(v);
			if (x4 && !a[0]) v = {v[6], v[7], v[5:0]};
		end else if (a >= GFX_BASE && a < GFX_BASE + 25'h0200000) begin
			if (tt) v = swap34(v);
			s = a[6:0];
			if (semi) begin
				o[6:0] = {s[4], s[6], s[2], s[3], s[0], s[1], s[5]};
				v = {v[3:0], v[7:4]};
			end else
				o[6:0] = {s[6], s[4], s[3], s[2], s[5], s[1], s[0]};
		end else if (a >= SOUND_BASE && a < SOUND_BASE + 25'h0010000) begin
			if (tt) v = swap34(v);
			if (x4) o[14] = ~o[14];
		end
		xbyte = {o, v};
	endfunction

	logic [32:0] x0, x1;
	logic        two;
	logic [1:0]  st;           // 0 idle, 1 first write, 2 second write, 3 wait for the source to drop
	logic        phase;        // 0: req out, 1: waiting for busy to fall

	wire [32:0] c0 = xbyte(s_addr, s_data[7:0], gfx_semicom, toto, x4in1);
	wire [32:0] c1 = xbyte(s_addr + 25'd1, s_data[15:8], gfx_semicom, toto, x4in1);
	// the two bytes are still an aligned pair, in order
	wire        pair_ok = !c0[8] && c0[32:9] == c1[32:9] && c1[8];

	always_ff @(posedge clk) begin
		if (reset) begin
			st <= 2'd0; phase <= 1'b0; s_busy <= 1'b0; d_req <= 1'b0;
		end else case (st)
			2'd0: if (s_req) begin
				x0 <= c0; x1 <= c1; s_busy <= 1'b1;
				two    <= s_we16 && !pair_ok;
				st     <= 2'd1; phase <= 1'b0;
				d_req  <= 1'b1;
				d_addr <= c0[32:8];
				d_data <= (s_we16 && pair_ok) ? {c1[7:0], c0[7:0]} : {8'd0, c0[7:0]};
				d_we16 <= s_we16 && pair_ok;
			end
			2'd1, 2'd2: begin
				if (!phase) begin
					if (d_busy) begin d_req <= 1'b0; phase <= 1'b1; end
				end else if (!d_busy) begin
					phase <= 1'b0;
					if (st == 2'd1 && two) begin
						st <= 2'd2; d_req <= 1'b1;
						d_addr <= x1[32:8]; d_data <= {8'd0, x1[7:0]}; d_we16 <= 1'b0;
					end else begin
						st <= 2'd3; s_busy <= 1'b0;
					end
				end
			end
			2'd3: if (!s_req) st <= 2'd0;      // the source drops req on busy's rise; settle
		endcase
	end
endmodule
