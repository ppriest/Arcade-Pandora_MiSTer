// SPDX-License-Identifier: GPL-3.0-or-later
// The board's picture: raster, Pandora sprite RAM, list resolve at vblank start, line engine,
// palette, RGB. snowbros.cpp screen_update (102-108) fills the screen with pen 0xF0 and copies
// the Pandora's bitmap over it with pen 0 transparent; the Pandora clears its bitmap to
// bg_pen (0, or 0xC0 for pzlbreak, init_pzlbreak 3290), which shows where nothing draws when
// it is not 0.
//
// Palette: 256 x xBGR_555 (1951), 0x600000-0x6001FF.
//
// Output: every output is registered on ce_pix, two pixels after the counters (one for the
// line buffer read, one for the palette); out_x/out_y are the counters delayed the same.

module snowbros_video (
	input  logic        clk,           // 48 MHz
	input  logic        reset,

	// 68000 side, one cycle of read latency
	input  logic [11:0] spr_addr,
	input  logic        spr_we,
	input  logic [7:0]  spr_wdata,
	output logic [7:0]  spr_rdata,
	input  logic [7:0]  pal_addr,
	input  logic        pal_wel, pal_weh,
	input  logic [15:0] pal_wdata,
	output logic [15:0] pal_rdata,

	input  logic        flip,          // the Pandora's flip
	input  logic [7:0]  bg_pen,
	input  logic [14:0] ntiles,

	// graphics, row-linear (pandora_rom)
	output logic        g_req,
	output logic [17:0] g_addr,
	input  logic        g_valid,
	input  logic [63:0] g_data,

	output logic        ce_pix,
	output logic [7:0]  r, g, b,
	output logic        hblank_o, vblank_o, hsync_o, vsync_o,
	output logic [8:0]  out_x, out_y,
	output logic        irq4, irq3, irq2,
	output logic [15:0] overruns,

	// raster position (docs/STATE.md)
	input  logic        ss_we,
	input  logic [8:0]  ss_line, ss_hcnt,
	input  logic [3:0]  ss_div,
	output logic [8:0]  vcnt,
	output logic [11:0] hclk
);
	logic [8:0] hcnt;
	logic       hblank, vblank, hsync, vsync, vb_start;

	video_timing u_timing (
		.clk(clk), .reset(reset), .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
		.hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync),
		.irq4(irq4), .irq3(irq3), .irq2(irq2), .vb_start(vb_start),
		.ss_we(ss_we), .ss_line(ss_line), .ss_hcnt(ss_hcnt), .ss_div(ss_div), .hclk(hclk)
	);

	// ---- sprite RAM: the 68000's port and the resolver's ----
	logic [7:0]  spr_ram [0:4095];
	logic [11:0] rs_addr;
	logic [7:0]  rs_q;
	always_ff @(posedge clk) begin
		if (spr_we) spr_ram[spr_addr] <= spr_wdata;
		spr_rdata <= spr_ram[spr_addr];
	end
	always_ff @(posedge clk) rs_q <= spr_ram[rs_addr];

	// ---- the resolved list ----
	logic        l_we;
	logic [8:0]  l_waddr, l_raddr;
	logic [40:0] l_d, l_q;
	logic [40:0] list_ram [0:511];
	always_ff @(posedge clk) if (l_we) list_ram[l_waddr] <= l_d;
	always_ff @(posedge clk) l_q <= list_ram[l_raddr];


	pandora_resolve u_resolve (
		.clk(clk), .reset(reset), .start(vb_start), .flip(flip), .ntiles(ntiles),
		.spr_addr(rs_addr), .spr_q(rs_q),
		.list_we(l_we), .list_addr(l_waddr), .list_d(l_d), .busy()
	);

	logic [18:0] rom_addr;
	logic        rom_cs, rom_ok;
	logic [31:0] rom_data;
	logic [7:0]  pxl;

	pandora_line u_line (
		.clk(clk), .reset(reset), .ce_pix(ce_pix), .hsync(hsync), .hcnt(hcnt), .vcnt(vcnt),
		.list_addr(l_raddr), .list_q(l_q),
		.rom_addr(rom_addr), .rom_cs(rom_cs), .rom_ok(rom_ok), .rom_data(rom_data),
		.pxl(pxl), .overruns(overruns)
	);

	pandora_rom u_rom (
		.clk(clk), .reset(reset),
		.rom_addr(rom_addr), .rom_cs(rom_cs), .rom_ok(rom_ok), .rom_data(rom_data),
		.g_req(g_req), .g_addr(g_addr), .g_valid(g_valid), .g_data(g_data)
	);

	// ---- palette: the 68000's port and the video's ----
	logic [7:0]  pal_lo [0:255], pal_hi [0:255];
	logic [7:0]  vp_addr;
	logic [15:0] vp_q;
	always_ff @(posedge clk) begin
		if (pal_wel) pal_lo[pal_addr] <= pal_wdata[7:0];
		pal_rdata[7:0] <= pal_lo[pal_addr];
	end
	always_ff @(posedge clk) begin
		if (pal_weh) pal_hi[pal_addr] <= pal_wdata[15:8];
		pal_rdata[15:8] <= pal_hi[pal_addr];
	end
	always_ff @(posedge clk) vp_q <= {pal_hi[vp_addr], pal_lo[vp_addr]};

	// ---- output: pixel h-1 is on pxl at the ce of h ----
	logic [3:0] fl_l, fl_1;
	logic [8:0] x_l, y_l, x_1, y_1;
	function automatic [7:0] ex5(input [4:0] v);
		ex5 = {v, v[4:2]};
	endfunction
	always_ff @(posedge clk) if (ce_pix) begin
		vp_addr <= pxl[3:0] != 4'd0 ? pxl : (bg_pen != 8'd0 ? bg_pen : 8'hF0);
		fl_1 <= fl_l;  x_1 <= x_l;  y_1 <= y_l;
		fl_l <= {hblank, vblank, hsync, vsync};
		x_l  <= hcnt;  y_l  <= vcnt;
		// vp_q is the colour of the index registered at the previous ce
		{hblank_o, vblank_o, hsync_o, vsync_o} <= fl_1;
		out_x <= x_1; out_y <= y_1;
		r <= ex5(vp_q[4:0]); g <= ex5(vp_q[9:5]); b <= ex5(vp_q[14:10]);
	end
endmodule
