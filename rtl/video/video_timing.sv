// SPDX-License-Identifier: GPL-3.0-or-later
// Raster: 354 x 262 at 48 MHz / 9 = 5.333 MHz (the roadmap's clock plan). MAME gives 57.5 Hz,
// 262 lines and rows 16-239 visible (snowbros.cpp 1945-1948) and no horizontal timing; the
// total of 354 makes 57.50 Hz from 16 MHz / 3. Active pixels are hcnt 0-255. Sync positions are
// not in MAME (docs/HACKS.md).
//
// Line numbers are MAME's: the interrupts fire at the start of lines 32, 128 and 240
// (snowbros.cpp 127-139), vblank starts at line 240.
//
// State: the raster position is written through ss_we as a line, a pixel and the divider's
// phase; a state file's clock within the line (0-3185) is pixel * 9 + phase, converted by
// whoever loads it.

module video_timing (
	input  logic        clk,          // 48 MHz
	input  logic        reset,

	output logic        ce_pix,       // one clk in nine
	output logic [8:0]  hcnt,         // 0-353
	output logic [8:0]  vcnt,         // 0-261
	output logic        hblank, vblank, hsync, vsync,
	output logic        irq4, irq3, irq2, // one-clk pulses at the start of lines 32, 128, 240
	output logic        vb_start,     // one-clk pulse at the start of line 240

	input  logic        ss_we,
	input  logic [8:0]  ss_line,
	input  logic [8:0]  ss_hcnt,
	input  logic [3:0]  ss_div,
	output logic [11:0] hclk          // clocks since the line started
);
	localparam int HTOTAL = 354, VTOTAL = 262;
	localparam int HSYNC0 = 276, HSYNC1 = 304, VSYNC0 = 248, VSYNC1 = 251;

	logic [3:0] div;
	wire        line_end = div == 4'd8 && hcnt == 9'(HTOTAL - 1);

	always_ff @(posedge clk) begin
		if (reset) begin
			div <= 4'd0; hcnt <= 9'd0; vcnt <= 9'd0; hclk <= 12'd0;
		end else if (ss_we) begin
			div <= ss_div; hcnt <= ss_hcnt; vcnt <= ss_line;
			hclk <= 12'({ss_hcnt, 3'd0} + ss_hcnt + ss_div);
		end else begin
			div  <= div == 4'd8 ? 4'd0 : div + 4'd1;
			hclk <= line_end ? 12'd0 : hclk + 12'd1;
			if (div == 4'd8) begin
				hcnt <= line_end ? 9'd0 : hcnt + 9'd1;
				if (line_end) vcnt <= vcnt == 9'(VTOTAL - 1) ? 9'd0 : vcnt + 9'd1;
			end
		end
	end

	assign ce_pix   = div == 4'd0;
	assign hblank   = hcnt >= 9'd256;
	assign vblank   = vcnt < 9'd16 || vcnt >= 9'd240;
	assign hsync    = hcnt >= 9'(HSYNC0) && hcnt < 9'(HSYNC1);
	assign vsync    = vcnt >= 9'(VSYNC0) && vcnt < 9'(VSYNC1);
	wire   line0    = hclk == 12'd0 && !reset;
	assign irq4     = line0 && vcnt == 9'd32;
	assign irq3     = line0 && vcnt == 9'd128;
	assign irq2     = line0 && vcnt == 9'd240;
	assign vb_start = irq2;
endmodule
