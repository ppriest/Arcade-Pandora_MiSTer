// SPDX-License-Identifier: GPL-3.0-or-later
// The Pandora's list, resolved once a frame at vblank start: kan_pand.cpp eof() draws the whole
// list there, so the positions it uses are fixed there (draw(), 130-201).
//
// Per entry (bytes 0-2 unused):
//   3  [7:4] palette   [2] relative   [1] Y bit 8   [0] X bit 8
//   4  X   5  Y   6  code low   7  [7] flip X  [6] flip Y  [5:0] code high
// A relative entry adds its 9-bit offsets to the running position. MAME's x and y are ints
// and the drawn position is sext9(pos & 0x1FF) after the flip's 240 - pos, so the running
// position is kept mod 512: 9 bits.
//
// The code is taken mod the tile count, as MAME's gfx element wraps it (drawgfx `code %
// elements()`; docs/MAME_KLUDGES.md), by up to three subtractions: every in-scope set has at
// least 4096 tiles of a 14-bit code.
//
// Out: 512 records, bit 40 xvis (the tile touches columns 0-255), 39:30 sx, 29:20 sy (signed),
// 19:6 code, 5:2 palette, 1 flip X, 0 flip Y. The engine reads them for the next frame's lines.

module pandora_resolve (
	input  logic        clk,
	input  logic        reset,
	input  logic        start,         // vb_start
	input  logic        flip,
	input  logic [14:0] ntiles,

	output logic [11:0] spr_addr,      // sprite RAM read port, data the clk after
	input  logic [7:0]  spr_q,

	output logic        list_we,
	output logic [8:0]  list_addr,
	output logic [40:0] list_d,
	output logic        busy
);
	logic [8:0]  ent;
	logic [2:0]  ph;
	logic [7:0]  b3, b4, b5, b6;
	logic [8:0]  ax, ay;
	logic [13:0] code;
	logic [1:0]  sub;

	wire [8:0] dx = {b3[0], b4};
	wire [8:0] dy = {b3[1], b5};
	wire [8:0] nx = b3[2] ? ax + dx : dx;
	wire [8:0] ny = b3[2] ? ay + dy : dy;
	wire [8:0] fxp = flip ? 9'd240 - nx : nx;
	wire [8:0] fyp = flip ? 9'd240 - ny : ny;
	wire signed [9:0] sx = {fxp[8], fxp};
	wire signed [9:0] sy = {fyp[8], fyp};
	wire xvis = sx > -10'sd16 && sx < 10'sd256;

	logic [8:0]  r_sx, r_sy;
	logic        r_vis;
	logic [3:0]  r_pal;
	logic        r_fx, r_fy;

	always_ff @(posedge clk) begin
		list_we <= 1'b0;
		if (reset) begin
			busy <= 1'b0;
		end else if (start) begin
			busy <= 1'b1; ent <= 9'd0; ph <= 3'd0; ax <= 9'd0; ay <= 9'd0;
			spr_addr <= {9'd0, 3'd3};
		end else if (busy) begin
			ph <= ph + 3'd1;
			case (ph)
				3'd0: spr_addr <= {ent, 3'd4};
				3'd1: begin b3 <= spr_q; spr_addr <= {ent, 3'd5}; end
				3'd2: begin b4 <= spr_q; spr_addr <= {ent, 3'd6}; end
				3'd3: begin b5 <= spr_q; spr_addr <= {ent, 3'd7}; end
				3'd4: b6 <= spr_q;
				3'd5: begin
					// spr_q is byte 7
					ax <= nx; ay <= ny;
					r_sx <= sx[8:0]; r_sy <= sy[8:0]; r_vis <= xvis;
					r_pal <= b3[7:4];
					r_fx <= spr_q[7] ^ flip; r_fy <= spr_q[6] ^ flip;
					code <= {spr_q[5:0], b6};
					sub <= 2'd0;
				end
				3'd6: begin
					// code mod ntiles, a subtraction a clock
					if ({1'b0, code} >= ntiles && sub != 2'd3) begin
						code <= 14'({1'b0, code} - ntiles);
						sub  <= sub + 2'd1;
						ph   <= 3'd6;
					end
				end
				3'd7: begin
					list_we   <= 1'b1;
					list_addr <= ent;
					list_d    <= {r_vis, r_sx[8], r_sx, r_sy[8], r_sy, code, r_pal, r_fx, r_fy};
					ent      <= ent + 9'd1;
					spr_addr <= {ent + 9'd1, 3'd3};
					ph       <= 3'd0;
					if (ent == 9'd511) busy <= 1'b0;
				end
			endcase
		end
	end
endmodule
