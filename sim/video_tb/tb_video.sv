// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// snowbros_video against MAME: one frame from a captured sprite list and palette.
//
// The fixtures (sim/video_tb/gen_fixture.py) are loaded into the sprite RAM and the palette;
// the raster starts at line 240, so the list is resolved at once, and the next frame's visible
// lines 16-239 are written to <OUT> as one "rrggbb" line a pixel, 256 x 224, for
// scripts/video_check.py. Graphics come from a granule model with 10 clk of latency.
//
// RUN FROM THE REPOSITORY ROOT:
//     python sim/video_tb/gen_fixture.py debug/snowbros-v/00700
//     scripts/run_sim.sh video_tb +OUT=debug/snowbros-v/00700/rtl.txt
module tb_video;
	localparam real HALF = 10.41667;   // 48 MHz
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic reset = 1;

	logic [63:0] gfx [0:262143];
	logic [15:0] cfg [0:2];
	logic        g_req, g_valid = 0;
	logic [17:0] g_addr;
	logic [63:0] g_data;
	int          g_cnt = -1;
	always_ff @(posedge clk) begin
		g_valid <= 1'b0;
		if (g_req && g_cnt < 0 && !g_valid) g_cnt <= 10;
		else if (g_cnt > 0) g_cnt <= g_cnt - 1;
		else if (g_cnt == 0) begin g_valid <= 1'b1; g_data <= gfx[g_addr]; g_cnt <= -1; end
	end

	logic        ce_pix, hb, vb, hs, vs, ss_we = 0;
	logic [7:0]  r, g, b;
	logic [8:0]  ox, oy, vcnt;
	logic [15:0] overruns;

	snowbros_video dut (
		.clk(clk), .reset(reset),
		.spr_addr(12'd0), .spr_we(1'b0), .spr_wdata(8'd0), .spr_rdata(),
		.pal_addr(8'd0), .pal_wel(1'b0), .pal_weh(1'b0), .pal_wdata(16'd0), .pal_rdata(),
		.flip(cfg[0][0]), .bg_pen(cfg[1][7:0]), .ntiles(cfg[2][14:0]),
		.g_req(g_req), .g_addr(g_addr), .g_valid(g_valid), .g_data(g_data),
		.ce_pix(ce_pix), .r(r), .g(g), .b(b),
		.hblank_o(hb), .vblank_o(vb), .hsync_o(hs), .vsync_o(vs), .out_x(ox), .out_y(oy),
		.irq4(), .irq3(), .irq2(), .overruns(overruns),
		.ss_we(ss_we), .ss_line(9'd240), .ss_hcnt(9'd0), .ss_div(4'd0), .vcnt(vcnt), .hclk()
	);

	string out = "debug/rtl_frame.txt";
	int    fd, npx = 0, frame_started = 0;
	always @(posedge clk) if (ce_pix && frame_started) begin
		if (!hb && !vb && oy >= 16 && oy < 240) begin
			$fwrite(fd, "%02x%02x%02x\n", r, g, b);
			npx++;
		end
	end

	initial begin
		logic [15:0] pal [0:255];
		void'($value$plusargs("OUT=%s", out));
		$readmemh("sim/video_tb/gfx.hex", gfx);
		$readmemh("sim/video_tb/cfg.hex", cfg);
		$readmemh("sim/video_tb/spr.hex", dut.spr_ram);
		$readmemh("sim/video_tb/pal.hex", pal);
		for (int i = 0; i < 256; i++) begin dut.pal_lo[i] = pal[i][7:0]; dut.pal_hi[i] = pal[i][15:8]; end
		fd = $fopen(out, "w");
		if (fd == 0) $fatal(1, "cannot write %s", out);
		repeat (10) @(posedge clk);
		reset = 0;
		@(negedge clk) ss_we = 1;
		@(negedge clk) ss_we = 0;
		// the frame after this vblank: output lines 16-239 arrive two pixels late, so wait for
		// the delayed counter to reach line 0 before counting
		wait (oy == 9'd0 && vcnt == 9'd0);
		frame_started = 1;
		wait (npx == 256 * 224);
		$fclose(fd);
		$display("%0d pixels written to %s; %0d overruns", npx, out, overruns);
		$finish;
	end
endmodule
