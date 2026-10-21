// SPDX-License-Identifier: GPL-3.0-or-later
// jtframe_draw's 32-bit graphics port served from 64-bit granules.
//
// The download stores each tile row-linear (scripts/gfx_layout_check.py, "row-linear"):
// tile t, row r at byte t*128 + r*8, eight bytes of two pixels each, the left pixel in the high
// nibble. One granule is one row, so the two halves jtframe_draw asks for one after the other
// come from one fetch. It wants pixel p of a half in rom_data[4p+3:4p] (PACKED).
//
// g_* is a req/valid granule port: g_req held until g_valid; g_data byte k is the byte at
// g_addr*8 + k.

module pandora_rom (
	input  logic        clk,
	input  logic        reset,

	input  logic [18:0] rom_addr,      // {code[13:0], half, row[3:0]}
	input  logic        rom_cs,
	output logic        rom_ok,
	output logic [31:0] rom_data,

	output logic        g_req,
	output logic [17:0] g_addr,        // granule index within the graphics region: {code, row}
	input  logic        g_valid,
	input  logic [63:0] g_data
);
	wire [17:0] want = {rom_addr[18:5], rom_addr[3:0]};
	wire        half = rom_addr[4];
	logic [17:0] tag;
	logic        tag_ok;
	logic [63:0] gran;

	assign rom_ok = rom_cs && tag_ok && tag == want;
	assign g_addr = want;

	always_ff @(posedge clk) begin
		if (reset) begin
			g_req <= 1'b0; tag_ok <= 1'b0;
		end else if (g_req) begin
			if (g_valid) begin
				g_req <= 1'b0; gran <= g_data; tag <= want; tag_ok <= 1'b1;
			end
		end else if (rom_cs && !(tag_ok && tag == want)) begin
			g_req <= 1'b1;
		end
	end

	// byte 4*half + k holds pixels 2k (high nibble) and 2k + 1
	always_comb
		for (int k = 0; k < 4; k++) begin
			logic [7:0] b;
			b = gran[8 * (4 * half + k) +: 8];
			rom_data[8 * k +: 8] = {b[3:0], b[7:4]};
		end
endmodule
