// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// snowbros_top end to end: the set's image through the real download path (ioctl, sdram_download,
// dl_xform, the arbiter, sdram.sv) into the SDRAM chip model, then the board out of reset.
//
// 1. The image's non-zero regions (sim/top_tb/segs.txt) are streamed as hps_io does, a byte per
//    ioctl_wr, held off by ioctl_wait. The chip model starts at zero, as MAME's regions do.
// 2. The SDRAM is compared word for word with expect.hex over those regions: the download
//    transforms as computed independently in Python. With +LIMIT=n only the first n bytes of
//    each region go through the download (it costs about 50 clk a byte); the whole of
//    expect.hex is then written into the model directly, so the boot runs on the full image.
// 3. The core is released and every 68000 access is written to debug/<SET>-boot/<SET>_top.trace
//    (scripts/compare_boot_trace.py --rtl), up to +MAXACC.
//
// RUN FROM THE REPOSITORY ROOT:
//     python sim/top_tb/gen_fixture.py snowbros
//     scripts/run_sim.sh top_tb +SET=snowbros +IN1=7ffe +IN2=7fff +IN3=ff00 +MAXACC=200000
module tb_top;
	localparam real HALF = 10.41667;   // 48 MHz
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic reset = 1;

	wire  [15:0] SDRAM_DQ;
	logic [12:0] SDRAM_A;
	logic [1:0]  SDRAM_BA;
	logic        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_DQML, SDRAM_DQMH, SDRAM_CKE, SDRAM_CLK;
	sdram_chip_model #(.ROWBITS(12)) u_chip (
		.clk(clk), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
		.SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS)
	);

	logic        ioctl_download = 0, ioctl_wr = 0, ioctl_wait;
	logic [24:0] ioctl_addr = 0;
	logic [7:0]  ioctl_dout = 0;
	logic [7:0]  mods [0:7];
	logic [15:0] in1 = 16'hffff, in2 = 16'hffff, in3 = 16'hffff;
	logic        ce_pix, hb, vb, hs, vs;
	logic [7:0]  r, g, b;
	logic signed [15:0] audio;

	snowbros_top dut (
		.clk(clk), .reset(reset), .init(1'b0), .pause(1'b0),
		.SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA),
		.SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .SDRAM_DQ(SDRAM_DQ),
		.ioctl_download(ioctl_download), .ioctl_index(16'd0), .ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
		.ldr_active(1'b0), .ldr_req(1'b0), .ldr_addr(25'd0), .ldr_data(16'd0), .ldr_we16(1'b0), .ldr_busy(),
		.mod0(mods[0]), .mod1(mods[1]), .const_val({mods[2], mods[3]}), .bg_pen(mods[4]),
		.ntiles({mods[5][6:0], mods[6]}), .flip_osd(1'b0),
		.in_dsw1(in1), .in_dsw2(in2), .in_system(in3),
		.ce_pix(ce_pix), .r(r), .g(g), .b(b), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs),
		.audio(audio)
	);

	// ---- trace ----
	string set = "snowbros";
	int    fd, nacc = 0, maxacc = 200000;
	logic  tracing = 0;
	wire   consume = dut.u_core.u_cpu.cpu_clkena && dut.u_core.u_cpu.busstate != 2'b01 && !dut.u_core.u_cpu.ss_hit;
	always @(posedge clk) if (tracing && consume && dut.u_core.u_cpu.fc != 3'b111 && nacc < maxacc) begin
		logic [15:0] mask, w;
		logic        wr;
		wr   = dut.u_core.u_cpu.busstate == 2'b11;
		w    = wr ? dut.u_core.u_cpu.cpu_dout : dut.u_core.u_cpu.acc_data;
		mask = {(dut.u_core.u_cpu.nUDS ? 8'h00 : 8'hff), (dut.u_core.u_cpu.nLDS ? 8'h00 : 8'hff)};
		if (!wr && dut.u_core.u_cpu.nUDS && dut.u_core.u_cpu.nLDS) mask = 16'hffff;
		nacc++;
		$fwrite(fd, "%0d\t%s\t%06X\t%04X\t%04X\n", nacc, wr ? "w" : "r",
		        {dut.u_core.u_cpu.a32[23:1], 1'b0}, mask, w & mask);
	end

	// sized for the longest image, yutnori's (snowbros_sdram_top YUT_END); the others' end is 0
	logic [7:0]  image [0:4063231];
	logic [15:0] expect_w [0:2031615];

	initial begin
		int f, nseg, bad, ms, lim, waited;
		int seg_a [16], seg_l [16];
		ms = 2000; lim = 0;
		void'($value$plusargs("LIMIT=%h", lim));   // download only this many bytes of each segment
		void'($value$plusargs("SET=%s", set));
		void'($value$plusargs("MAXACC=%d", maxacc));
		void'($value$plusargs("MS=%d", ms));
		void'($value$plusargs("IN1=%h", in1));
		void'($value$plusargs("IN2=%h", in2));
		void'($value$plusargs("IN3=%h", in3));
		$readmemh("sim/top_tb/image.hex", image);
		$readmemh("sim/top_tb/expect.hex", expect_w);
		f = $fopen("sim/top_tb/cfg.txt", "r");
		for (int i = 0; i < 8; i++) void'($fscanf(f, "%h", mods[i]));
		$fclose(f);
		f = $fopen("sim/top_tb/segs.txt", "r");
		nseg = 0;
		while ($fscanf(f, "%h %h", seg_a[nseg], seg_l[nseg]) == 2) nseg++;
		$fclose(f);

		// ---- 1: download ----
		repeat (20) @(posedge clk);
		ioctl_download = 1;
		for (int s = 0; s < nseg; s++) begin
			if (lim != 0 && seg_l[s] > lim) seg_l[s] = lim;
			for (int i = 0; i < seg_l[s]; i++) begin
				@(posedge clk);
				waited = 0;
				while (ioctl_wait) begin
					@(posedge clk);
					if (++waited == 100000) $fatal(1, "ioctl_wait held 100000 clk at byte 0x%06x", seg_a[s] + i);
				end
				if (i % 65536 == 0) $display("%t: segment %0d, byte 0x%06x", $time, s, seg_a[s] + i);
				ioctl_addr = 25'(seg_a[s] + i); ioctl_dout = image[seg_a[s] + i]; ioctl_wr = 1;
				@(posedge clk) ioctl_wr = 0;
			end
		end
		repeat (50) @(posedge clk);
		ioctl_download = 0;
		repeat (200) @(posedge clk);
		$display("%t: download done, %0d segments", $time, nseg);

		// ---- 2: the SDRAM against the transforms computed in Python ----
		bad = 0;
		for (int s = 0; s < nseg; s++)
			for (int w0 = seg_a[s] / 2; w0 < (seg_a[s] + seg_l[s]) / 2; w0++) begin
				// 4in1boot's sound ROM lands at address ^ 0x4000: compare where the bytes sent went
				automatic int w = (mods[0][5] && seg_a[s] == 'h300000) ? w0 ^ 'h2000 : w0;
				if (u_chip.peek_word_addr(24'(w)) !== expect_w[w]) begin
					bad++;
					if (bad <= 5) $display("FAIL SDRAM byte 0x%06x: %04x, expected %04x", 2 * w,
					                       u_chip.peek_word_addr(24'(w)), expect_w[w]);
				end
			end
		$display("SDRAM: %0d words differ from expect.hex", bad);
		// the rest of each region straight into the model (bank 0: the word address is the index)
		for (int w = 0; w < 2031616; w++) u_chip.mem[w] = expect_w[w];

		// ---- 3: boot ----
		fd = $fopen($sformatf("debug/%s-boot/%s_top.trace", set, set), "w");
		if (fd == 0) $fatal(1, "cannot open debug/%s-boot/%s_top.trace", set, set);
		$fwrite(fd, "# RTL bus accesses from reset (sim/top_tb), seq rw addr mask data\n");
		tracing = 1;
		@(negedge clk) reset = 0;
		// the protdata copy (snowbros_core), against the image's protdata region
		if (mods[0][7]) begin
			int pbad = 0, base;
			repeat (2) @(posedge clk);
			wait (!dut.u_core.copying);
			repeat (4) @(posedge clk);
			base = mods[1][0] ? 16'h1000 : 16'h7800;
			for (int i = 0; i < 256; i++)
				if ({dut.u_core.wram_hi[base + i], dut.u_core.wram_lo[base + i]} !==
				    {image[25'h352000 + 2 * i], image[25'h352000 + 2 * i + 1]}) begin
					pbad++;
					if (pbad <= 3) $display("FAIL protdata word %0d: %02x%02x, image %02x%02x", i,
						dut.u_core.wram_hi[base + i], dut.u_core.wram_lo[base + i],
						image[25'h352000 + 2 * i], image[25'h352000 + 2 * i + 1]);
				end
			$display("protdata copy: %0d of 256 words differ from the image", pbad);
		end
		fork
			begin wait (nacc >= maxacc); end
			begin #(longint'(ms) * 1ms); end
		join_any
		disable fork;
		$fclose(fd);
		$display("%0d accesses traced; %0d SDRAM words differed", nacc, bad);
		$finish;
	end
endmodule
