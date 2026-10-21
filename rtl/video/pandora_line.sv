// SPDX-License-Identifier: GPL-3.0-or-later
// The Pandora's picture a line at a time, from the list pandora_resolve fixed at vblank start.
// MAME draws the list into a bitmap at vblank start and shows it the next frame (kan_pand.cpp
// eof() 203-211, update() 124-127); drawing each line of that frame from the same list, in the
// same entry order, gives the same pixels. Later entries are drawn over earlier ones, pen 0
// is transparent (transpen).
//
// jtframe_objdraw draws a 16-pixel tile row a request into its double line buffer, which
// swaps on hsync. The scan starts on that edge, for the line two ahead (the buffer written now
// is shown the line after next): every record whose sy covers the line and whose tile touches
// columns 0-255 is a request. The scan runs on while a draw is busy, one record ahead.
//
// A scan still running at the next swap is cut short and counted in overruns: the entries
// not reached are the ones drawn on top. MAME's sets measured at most 73 records on a line
// (docs/sprite_load_mame.txt).
//
// Graphics: rom_* is jtframe_draw's 32-bit port, {code, half, row}; pandora_rom serves it.

module pandora_line (
	input  logic        clk,
	input  logic        reset,
	input  logic        ce_pix,
	input  logic        hsync,
	input  logic [8:0]  hcnt,
	input  logic [8:0]  vcnt,

	output logic [8:0]  list_addr,     // resolved list, data the clk after
	input  logic [40:0] list_q,

	output logic [18:0] rom_addr,      // {code[13:0], half, row[3:0]}
	output logic        rom_cs,
	input  logic        rom_ok,
	input  logic [31:0] rom_data,

	output logic [7:0]  pxl,           // {palette, pen} at hcnt, two clk after ce_pix; pen 0: none
	output logic [15:0] overruns
);
	logic        hs_d, scanning, have, q_valid;
	logic [8:0]  target, q_ent;
	logic [13:0] c_code;
	logic [8:0]  c_x;
	logic [3:0]  c_ysub, c_pal;
	logic        c_fx, c_fy;
	wire         draw_busy;
	wire         hs_rise = hsync && !hs_d;

	// list_q is the record at q_ent, read the clock before
	wire        r_vis  = list_q[40];
	wire [9:0]  r_sx   = list_q[39:30];
	wire [9:0]  r_sy   = list_q[29:20];
	wire [9:0]  dy     = {1'b0, target} - r_sy;      // target - sy, mod 1024
	wire        hit    = q_valid && r_vis && dy[9:4] == 6'd0;
	wire        take   = have && !draw_busy;           // a one-clk draw pulse: objdraw registers it into busy
	// objdraw (LATCH) samples its inputs again the clock after it takes a request, so the next
	// one is loaded only once `have` has dropped
	wire        stall  = hit && have;                  // no room: read the record again
	wire        vis_ln = target >= 9'd16 && target < 9'd240;

	always_ff @(posedge clk) begin
		hs_d  <= hsync;
		q_ent <= list_addr;
		if (reset) begin
			scanning <= 1'b0; have <= 1'b0; q_valid <= 1'b0; overruns <= 16'd0;
			list_addr <= 9'd0;
		end else if (hs_rise) begin
			if (scanning || have || draw_busy) overruns <= overruns + 16'd1;
			target    <= vcnt >= 9'd260 ? vcnt - 9'd260 : vcnt + 9'd2;
			scanning  <= 1'b1;
			have      <= 1'b0;
			list_addr <= 9'd0;
			q_valid   <= 1'b0;
		end else begin
			if (take) have <= 1'b0;
			if (hit && !stall) begin
				have   <= vis_ln;
				c_code <= list_q[19:6];
				c_x    <= r_sx[8:0];
				c_ysub <= dy[3:0];
				c_pal  <= list_q[5:2];
				c_fx   <= list_q[1];
				c_fy   <= list_q[0];
			end
			q_valid <= scanning && !stall && !(q_valid && q_ent == 9'd511);
			if (stall)
				list_addr <= q_ent;
			else if (scanning && list_addr != 9'd511)
				list_addr <= list_addr + 9'd1;
			if (q_valid && q_ent == 9'd511 && !stall) scanning <= 1'b0;
		end
	end

	jtframe_objdraw #(
		.AW(9), .CW(14), .PW(8), .LATCH(1), .PACKED(1), .HFIX(0)
	) u_draw (
		.rst(reset), .clk(clk), .pxl_cen(ce_pix), .hs(hsync), .flip(1'b0), .hdump(hcnt),
		.draw(take), .busy(draw_busy),
		.code(c_code), .xpos(c_x), .ysub(c_ysub),
		.hzoom(6'd0), .hz_keep(1'b0),
		.hflip(c_fx), .vflip(c_fy), .pal(c_pal),
		.rom_addr(rom_addr), .rom_cs(rom_cs), .rom_ok(rom_ok), .rom_data(rom_data),
		.pxl(pxl)
	);
endmodule
