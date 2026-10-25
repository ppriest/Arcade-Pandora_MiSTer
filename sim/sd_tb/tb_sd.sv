`timescale 1ns/1ps
// The video output path under the framework's scandoubler (issue #1): the core's raster
// (rtl/video/video_timing.sv) with a test pattern, R = the pixel's column, G = its line, through
// crt_chain (CRT Adjust off) and sys/arcade_video with the OSD's Scandoubler Fx (+FX=0-4).
// Logged to <OUT>, one line per output line that has enabled pixels:
//     <out line> <pixels> <first R> <last R> <G> <R steps that are not +1 (hq2x: 0 or +1)>
// A source line at native rate is 256 pixels R 0-255; doubled, each source line twice.
//
// RUN FROM THE REPOSITORY ROOT:
//     scripts/run_verilator.sh sd_tb +FX=2 +OUT=debug/sd/fx2.txt
module tb_sd;
	localparam real HALF = 10.41667;   // 48 MHz
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic reset = 1;

	logic       ce_pix, hblank, vblank, hsync, vsync;
	logic [8:0] hcnt, vcnt;
	video_timing u_timing (
		.clk(clk), .reset(reset), .ce_pix(ce_pix), .hcnt(hcnt), .vcnt(vcnt),
		.hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync),
		.irq4(), .irq3(), .irq2(), .vb_start(),
		.ss_we(1'b0), .ss_line(9'd0), .ss_hcnt(9'd0), .ss_div(4'd0), .hclk()
	);

	// registered on ce_pix, as snowbros_video's output
	logic [7:0] r, g, b;
	logic       hb_o, vb_o, hs_o, vs_o;
	always_ff @(posedge clk) if (ce_pix) begin
		r <= hcnt[7:0]; g <= vcnt[7:0]; b <= 8'h55;
		{hb_o, vb_o, hs_o, vs_o} <= {hblank, vblank, hsync, vsync};
	end

	logic [2:0] fx = 3'd0;
	logic       adj = 1'b0;           // +ADJ: CRT Adjust on, H-Position +3
	logic       crt_ce, crt_hs, crt_vs, crt_hb, crt_vb;
	logic [7:0] crt_r, crt_g, crt_b;
	crt_chain #(.HTOTAL(354), .VTOTAL(262), .ACTIVE_W(256), .RD_BASE(36)) u_crt (
		.clk(clk), .ce_pix(ce_pix),
		.active(adj), .scale_en(fx == 3'd0),
		.hoffset(adj ? 9'sd3 : 9'sd0), .voffset(6'sd0), .hsize(5'sd0), .vsize_step(4'sd0), .vsize_cabinet(1'b0),
		.r_in(r), .g_in(g), .b_in(b),
		.hs_in(hs_o), .vs_in(vs_o), .hb_in(hb_o), .vb_in(vb_o),
		.ce_out(crt_ce), .r_out(crt_r), .g_out(crt_g), .b_out(crt_b),
		.hs_out(crt_hs), .vs_out(crt_vs), .hb_out(crt_hb), .vb_out(crt_vb)
	);

	wire [21:0] gamma_bus;
	assign gamma_bus[20:0] = 21'd0;    // gamma off
	wire        CLK_VIDEO, CE_PIXEL, VGA_HS, VGA_VS, VGA_DE;
	wire [7:0]  VGA_R, VGA_G, VGA_B;
	wire [1:0]  VGA_SL;
	arcade_video #(.WIDTH(256), .DW(24), .GAMMA(1)) u_av (
		.clk_video(clk), .ce_pix(crt_ce),
		.RGB_in({crt_r, crt_g, crt_b}),
		.HBlank(crt_hb), .VBlank(crt_vb), .HSync(crt_hs), .VSync(crt_vs),
		.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL),
		.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
		.VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE), .VGA_SL(VGA_SL),
		.fx(fx), .forced_scandoubler(1'b0), .gamma_bus(gamma_bus)
	);

	// sys_top's VGA_scanlines, which also feeds the HDMI scaler (sys_top.v: hr_out = vga_data_sl)
	wire        vs_fix, hs_fix;
	sync_fix u_sfv(clk, VGA_VS, vs_fix);
	sync_fix u_sfh(clk, VGA_HS, hs_fix);
	wire [23:0] sl_d;
	wire        sl_hs, sl_vs, sl_de, sl_ce;
	scanlines #(0) u_sl (
		.clk(clk), .scanlines(VGA_SL), .din(VGA_DE ? {VGA_R, VGA_G, VGA_B} : 24'd0),
		.hs_in(hs_fix), .vs_in(vs_fix), .de_in(VGA_DE), .ce_in(CE_PIXEL),
		.dout(sl_d), .hs_out(sl_hs), .vs_out(sl_vs), .de_out(sl_de), .ce_out(sl_ce)
	);
	// +SL: R of the 101st enabled pixel of each scanlined line (source R 100), one frame
	int sl_n = 0, sl_line = 0;
	logic sl_de_d = 0;
	always_ff @(posedge clk) if (sl_ce) begin
		sl_de_d <= sl_de;
		if (sl_de && !sl_de_d) sl_n <= 1; else if (sl_de) sl_n <= sl_n + 1;
		if (sl_de && sl_n == 100 && frames == 3 && $test$plusargs("SL")) begin
			$fwrite(fd, "SL %0d %0d sl=%0d\n", sl_line, sl_d[23:16], VGA_SL);
			sl_line <= sl_line + 1;
		end
	end

	// arcade_video leaves the mixer's HDMI_FREEZE unconnected; Quartus ties it low
	initial force u_av.video_mixer.HDMI_FREEZE = 1'b0;

	int fd, frames = 0, oline = 0, n = 0, bad = 0;
	logic [7:0] r0, rl, g0;
	logic de_d = 0, hs_d = 0, vs_d = 0;
	string out = "debug/sd/out.txt";
	always_ff @(posedge clk) begin
		hs_d <= VGA_HS; vs_d <= VGA_VS;
		if (VGA_VS && !vs_d) begin frames <= frames + 1; oline <= 0; end
		if (CE_PIXEL) begin
			de_d <= VGA_DE;
			if (VGA_DE) begin
				if (!de_d) begin r0 <= VGA_R; g0 <= VGA_G; n <= 1; bad <= 0; end
				else begin
					n <= n + 1;
					if (fx == 3'd1 ? !(VGA_R == rl || VGA_R == rl + 8'd1) : VGA_R != rl + 8'd1) bad <= bad + 1;
				end
				rl <= VGA_R;
			end else if (de_d) begin
				if (frames == 3) $fwrite(fd, "%0d %0d %0d %0d %0d %0d\n", oline, n, r0, rl, g0, bad);
				oline <= oline + 1;
			end
		end
	end

	// probe: +PROBE prints the path at a few pixels of line 100 of frame 2
	always_ff @(posedge clk) if ($test$plusargs("PROBE") && (frames == 2 || fx != 0) && vcnt == 9'd100 && hcnt < 9'd4 && ce_pix)
		$display("frz %0d frzvs %0d vs_g %0d vs_sd %0d hb_sd %0d rt %0d R_in %0d", u_av.video_mixer.frz, u_av.video_mixer.frz_vs, u_av.video_mixer.vs_g, u_av.video_mixer.vs_sd, u_av.video_mixer.hb_sd, u_av.video_mixer.rt, u_av.video_mixer.R_gamma);
	always_ff @(posedge clk) if ($test$plusargs("PROBE") && (frames == 2 || fx != 0) && vcnt == 9'd100 && hcnt < 9'd4 && ce_pix)
		$display("h %0d r %0d crt_ce %0d crt_r %0d fix %0h vga_r %0d de %0d ce %0d", hcnt, r, crt_ce, crt_r, u_av.RGB_fix, VGA_R, VGA_DE, CE_PIXEL);

	// edge counts along the sync path, printed at the end
	int c_vsg = 0, c_vssd = 0, c_vga = 0, c_ce = 0, c_hsin = 0, c_hsout = 0;
	logic p_vsg = 0, p_vssd = 0, p_vga = 0, p_hsin = 0, p_hsout = 0;
	always_ff @(posedge clk) begin
		p_vsg <= u_av.video_mixer.vs_g;  if (u_av.video_mixer.vs_g && !p_vsg) c_vsg <= c_vsg + 1;
		p_vssd <= u_av.video_mixer.vs_sd; if (u_av.video_mixer.vs_sd && !p_vssd) c_vssd <= c_vssd + 1;
		p_vga <= VGA_VS; if (VGA_VS && !p_vga) c_vga <= c_vga + 1;
		p_hsin <= u_av.video_mixer.hs_g; if (u_av.video_mixer.hs_g && !p_hsin) c_hsin <= c_hsin + 1;
		p_hsout <= u_av.video_mixer.hs_sd; if (u_av.video_mixer.hs_sd && !p_hsout) c_hsout <= c_hsout + 1;
		if (CE_PIXEL) c_ce <= c_ce + 1;
		if ($test$plusargs("VSO") && u_av.video_mixer.vs_g != p_vsg)
			$display("%0t vs_g -> %0d; vso %b hs_g %0d", $realtime, u_av.video_mixer.vs_g, u_av.video_mixer.sd.vso, u_av.video_mixer.hs_g);
		if ($test$plusargs("VSO") && u_av.video_mixer.hs_g && !p_hsin && u_av.video_mixer.vs_g)
			$display("%0t   hs_g rise while vs_g; vso %b hs_start %0d hs_end %0d hde_start %0d hde_end %0d sd_hcnt %0d", $realtime, u_av.video_mixer.sd.vso, u_av.video_mixer.sd.hs_start, u_av.video_mixer.sd.hs_end, u_av.video_mixer.sd.hde_start, u_av.video_mixer.sd.hde_end, u_av.video_mixer.sd.sd_hcnt);
	end
	final $display("edges: vs_g %0d vs_sd %0d VGA_VS %0d hs_g %0d hs_sd %0d CE_PIXEL %0d; sd pixsz %0d", c_vsg, c_vssd, c_vga, c_hsin, c_hsout, c_ce, u_av.video_mixer.sd.pixsz);

	initial begin
		int f;
		void'($value$plusargs("OUT=%s", out));
		if ($value$plusargs("FX=%d", f)) fx = 3'(f);
		adj = $test$plusargs("ADJ");
		fd = $fopen(out, "w");
		if (fd == 0) $fatal(1, "cannot write %s", out);
		repeat (4) @(posedge clk);
		reset = 0;
		fork
			wait (frames == 4);
			begin #(70_000_000); $display("timeout: %0d frames, VGA_VS never reached 4", frames); end
		join_any
		$fclose(fd);
		$display("fx %0d: %s", fx, out);
		$finish;
	end
endmodule
