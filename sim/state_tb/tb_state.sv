`timescale 1ns/1ps
// maincpu from a state file, against MAME (docs/STATE.md).
//
// Restore: the CPU is taken at its first instruction boundary after reset (gx_ss_m68k), the
// RAMs are loaded from the fixtures while it is held, the registers and pending interrupts are
// written through the state ports, the raster is set to the captured line and clock, and the
// CPU is released. Run: every access is traced to <OUT>/rtl.trace; at the EVERY-th level-4
// interrupt entry after the restore (its vector read) the CPU is taken again and the state is
// written to <OUT>/<section>.hex in scripts/state.py's sim layout.
//
// No Z80: 0x300000 reads the captured Z80-to-68000 latch.
//
// RUN FROM THE REPOSITORY ROOT:
//     python scripts/state.py to-sim debug/snowbros-state/mame_0.sbst debug/snowbros-state/in
//     scripts/run_sim.sh state_tb +IN=debug/snowbros-state/in +OUT=debug/snowbros-state/out \
//         +EVERY=60 +IN1=7ffe +IN2=7fff +IN3=ff00
module tb_state;
	localparam real HALF = 10.41667;   // 48 MHz
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic reset = 1;

	// ---- raster: 3186 clk a line, 262 lines; IRQ lines 32, 128, 240 ----
	int unsigned hc = 0, vc = 0;
	logic irq4, irq3, irq2, raster_run = 0;
	always_ff @(posedge clk) if (raster_run) begin
		if (hc == 3185) begin
			hc <= 0;
			vc <= (vc == 261) ? 0 : vc + 1;
		end else hc <= hc + 1;
	end
	assign irq4 = raster_run && hc == 0 && vc == 32;
	assign irq3 = raster_run && hc == 0 && vc == 128;
	assign irq2 = raster_run && hc == 0 && vc == 240;

	// ---- program ROM: req/valid, 12-cycle latency ----
	logic [15:0] prg [0:524287];
	initial $readmemh("sim/boot_tb/maincpu.hex", prg);
	logic        rom_req, rom_valid;
	logic [18:0] rom_addr, rom_addr_l;
	logic [15:0] rom_data;
	int          rom_cnt = -1;
	always_ff @(posedge clk) begin
		rom_valid <= 1'b0;
		if (rom_req) begin rom_cnt <= 12; rom_addr_l <= rom_addr; end
		else if (rom_cnt > 0) rom_cnt <= rom_cnt - 1;
		else if (rom_cnt == 0) begin rom_valid <= 1'b1; rom_data <= prg[rom_addr_l]; rom_cnt <= -1; end
	end

	// ---- RAMs ----
	logic [14:0] wram_addr;  logic wram_wel, wram_weh; logic [15:0] wram_wdata, wram_rdata;
	logic [7:0]  pal_addr;   logic pal_wel, pal_weh;   logic [15:0] pal_wdata, pal_rdata;
	logic [11:0] spr_addr;   logic spr_we;             logic [7:0]  spr_wdata, spr_rdata;
	logic [15:0] wram [0:32767], pal [0:255];
	logic [7:0]  spr [0:4095];
	always @(posedge clk) begin
		wram_rdata <= wram[wram_addr];
		if (wram_wel) wram[wram_addr][7:0]  <= wram_wdata[7:0];
		if (wram_weh) wram[wram_addr][15:8] <= wram_wdata[15:8];
		pal_rdata <= pal[pal_addr];
		if (pal_wel) pal[pal_addr][7:0]  <= pal_wdata[7:0];
		if (pal_weh) pal[pal_addr][15:8] <= pal_wdata[15:8];
		spr_rdata <= spr[spr_addr];
		if (spr_we) spr[spr_addr] <= spr_wdata;
	end

	logic [15:0] in1 = 16'hffff, in2 = 16'hffff, in3 = 16'hffff;
	logic [7:0]  snd_in = 8'h00, latch_w = 8'h00;
	logic        semicom = 0, flip = 0, const_en = 0, const_5006 = 0, wram16 = 0, yut = 0;
	wire         wbig = (semicom && !wram16) || yut;    // 64 KB of work RAM
	logic [15:0] const_val = 16'h0000;
	logic        snd_we, flip_we, flip_wdata;
	logic [7:0]  snd_wdata;
	always @(posedge clk) begin
		if (snd_we) latch_w <= snd_wdata;
		if (flip_we) flip <= flip_wdata;
	end

	logic        ss_req = 0, ss_go = 0, ss_held, ss_done, ss_bwe = 0, ss_irq_we = 0;
	logic [4:0]  ss_bidx = 0;
	logic [31:0] ss_bd = 0, ss_bq;
	logic [4:2]  ss_irq_d = 0, ss_irq_q;

	maincpu dut (
		.clk(clk), .reset(reset),
		.semicom(semicom), .wram64(semicom && !wram16), .cpu12(semicom), .yutnori(yut),
		.const_en(const_en), .const_at_500006(const_5006), .const_val(const_val),
		.rom_req(rom_req), .rom_addr(rom_addr), .rom_valid(rom_valid), .rom_data(rom_data),
		.wram_addr(wram_addr), .wram_wel(wram_wel), .wram_weh(wram_weh),
		.wram_wdata(wram_wdata), .wram_rdata(wram_rdata),
		.pal_addr(pal_addr), .pal_wel(pal_wel), .pal_weh(pal_weh),
		.pal_wdata(pal_wdata), .pal_rdata(pal_rdata),
		.spr_addr(spr_addr), .spr_we(spr_we), .spr_wdata(spr_wdata), .spr_rdata(spr_rdata),
		.in_dsw1(in1), .in_dsw2(in2), .in_system(in3),
		.snd_we(snd_we), .snd_wdata(snd_wdata), .snd_rdata(snd_in),
		.flip_we(flip_we), .flip_wdata(flip_wdata),
		.irq4_line(irq4), .irq3_line(irq3), .irq2_line(irq2),
		.pause(1'b0),
		.ss_req(ss_req), .ss_go(ss_go), .ss_held(ss_held), .ss_done(ss_done),
		.ss_bidx(ss_bidx), .ss_bwe(ss_bwe), .ss_bd(ss_bd), .ss_bq(ss_bq),
		.ss_irq_we(ss_irq_we), .ss_irq_d(ss_irq_d), .ss_irq_q(ss_irq_q)
	);

	// ---- the state ports ----
	task automatic take();
		int t = 0;
		@(negedge clk) ss_req = 1;
		while (!ss_held) begin @(posedge clk); t++; if (t > 200000) $fatal(1, "never held"); end
		@(negedge clk) ss_req = 0;
	endtask
	task automatic release_cpu();
		int t = 0;
		@(negedge clk) ss_go = 1;
		while (!ss_done) begin @(posedge clk); t++; if (t > 200000) $fatal(1, "never done"); end
		@(negedge clk) ss_go = 0;
	endtask
	task automatic bank_wr(input int i, input logic [31:0] v);
		@(negedge clk) begin ss_bidx = i[4:0]; ss_bd = v; ss_bwe = 1; end
		@(negedge clk) ss_bwe = 0;
	endtask
	task automatic bank_rd(input int i, output logic [31:0] v);
		ss_bidx = i[4:0]; #1;
		v = ss_bq;
	endtask

	// ---- trace, from the release ----
	string indir = "", outdir = "";
	int    fd = 0, nacc = 0, maxacc = 300000, entries = 0, every = 60;
	logic  tracing = 0;
	wire   consume = dut.cpu_clkena && (dut.busstate != 2'b01) && !dut.ss_hit;
	always @(posedge clk) if (tracing && consume && dut.fc != 3'b111 && nacc < maxacc) begin
		logic [15:0] mask, w;
		logic        wr;
		wr   = dut.busstate == 2'b11;
		w    = wr ? dut.cpu_dout : dut.acc_data;
		mask = {(dut.nUDS ? 8'h00 : 8'hff), (dut.nLDS ? 8'h00 : 8'hff)};
		if (!wr && dut.nUDS && dut.nLDS) mask = 16'hffff;
		nacc++;
		$fwrite(fd, "%0d\t%s\t%06X\t%04X\t%04X\n", nacc, wr ? "w" : "r",
		        {dut.a32[23:1], 1'b0}, mask, w & mask);
	end
	// level-4 entries: the read of its autovector
	logic vec_seen = 0;
	always @(posedge clk) if (tracing && consume && dut.a32[23:0] == 24'h000070 && dut.busstate == 2'b10) begin
		entries++;
		if (entries == every) vec_seen <= 1;
	end

	// ---- fixtures ----
	logic [31:0] regs [0:22];
	logic [15:0] board [0:5];
	task automatic dump(input string dir);
		int f;
		logic [31:0] r;
		f = $fopen({dir, "/m68k_regs.hex"}, "w");
		for (int i = 0; i < 23; i++) begin
			bank_rd(i, r);
			if (i == 18) r = r + 6;                  // A7 as the program has it: the stub's frame is 6 bytes
			$fwrite(f, "%08x\n", r);
		end
		$fclose(f);
		f = $fopen({dir, "/board.hex"}, "w");
		$fwrite(f, "%04x\n%04x\n%04x\n%04x\n%04x\n%04x\n", {13'd0, ss_irq_q}, {15'd0, flip}, {8'd0, latch_w},
		        {8'd0, snd_in}, vc[15:0], hc[15:0]);
		$fclose(f);
		f = $fopen({dir, "/wram.hex"}, "w");
		for (int i = 0; i < (wbig ? 32768 : 8192); i++) $fwrite(f, "%04x\n", wram[i]);
		$fclose(f);
		f = $fopen({dir, "/palette.hex"}, "w");
		for (int i = 0; i < 256; i++) $fwrite(f, "%04x\n", pal[i]);
		$fclose(f);
		f = $fopen({dir, "/spriteram.hex"}, "w");
		for (int i = 0; i < 4096; i++) $fwrite(f, "%02x\n", spr[i]);
		$fclose(f);
		f = $fopen({dir, "/state.txt"}, "w");
		$fwrite(f, "m68k_regs 32 23\nboard 16 6\nwram 16 %0d\npalette 16 256\nspriteram 8 4096\n",
		        wbig ? 32768 : 8192);
		$fclose(f);
		f = $fopen({dir, "/event.txt"}, "w");
		$fwrite(f, "{\"kind\":\"irq4_entry\",\"index\":%0d,\"line\":%0d,\"hclk\":%0d}\n", entries, vc, hc);
		$fclose(f);
	endtask

	initial begin
		int ms = 3000;
		void'($value$plusargs("IN=%s", indir));
		void'($value$plusargs("OUT=%s", outdir));
		void'($value$plusargs("EVERY=%d", every));
		void'($value$plusargs("MAXACC=%d", maxacc));
		void'($value$plusargs("MS=%d", ms));
		void'($value$plusargs("IN1=%h", in1));
		void'($value$plusargs("IN2=%h", in2));
		void'($value$plusargs("IN3=%h", in3));
		if ($test$plusargs("SEMICOM")) semicom = 1;
		if ($value$plusargs("CONST=%h", const_val)) const_en = 1;      // the set's constant read
		if ($test$plusargs("CONST500006")) const_5006 = 1;           // ...at 0x500006, else 0x200000
		if ($test$plusargs("WRAM16")) wram16 = 1;                     // finalttr: 16 KB work RAM
		if ($test$plusargs("YUTNORI")) yut = 1;                        // yutnori_map
		if (indir == "" || outdir == "") $fatal(1, "+IN=<fixture dir> +OUT=<dump dir>");
		$readmemh({indir, "/m68k_regs.hex"}, regs);
		$readmemh({indir, "/board.hex"}, board);
		fd = $fopen({outdir, "/rtl.trace"}, "w");
		if (fd == 0) $fatal(1, "cannot write %s/rtl.trace (mkdir it)", outdir);
		$fwrite(fd, "# RTL bus accesses from the restore (sim/state_tb), seq rw addr mask data\n");

		repeat (20) @(posedge clk);
		reset = 0;
		take();
		$readmemh({indir, "/wram.hex"}, wram);
		$readmemh({indir, "/palette.hex"}, pal);
		$readmemh({indir, "/spriteram.hex"}, spr);
		for (int i = 0; i < 23; i++) bank_wr(i, i == 18 ? regs[i] - 6 : regs[i]);
		@(negedge clk) begin ss_irq_d = board[0][2:0]; ss_irq_we = 1; end
		@(negedge clk) ss_irq_we = 0;
		flip = board[1][0]; latch_w = board[2][7:0]; snd_in = board[3][7:0];
		vc = board[4]; hc = board[5];
		raster_run = 1;
		tracing = 1;
		release_cpu();
		$display("%t: restored PC %06x SR %04x A7 %08x pend %03b at line %0d clk %0d",
		         $time, regs[20], regs[19][15:0], regs[18], board[0][2:0], board[4], board[5]);

		fork
			begin wait (vec_seen); end
			begin #(longint'(ms) * 1ms); end
		join_any
		disable fork;
		if (!vec_seen) $fatal(1, "%0d level-4 entries in %0d ms, wanted %0d", entries, ms, every);
		take();
		tracing = 0;
		$fclose(fd);
		dump(outdir);
		begin
			logic [31:0] pc, sr;
			bank_rd(20, pc); bank_rd(19, sr);
			$display("%t: entry %0d taken: PC %06x SR %04x, %0d accesses traced", $time, entries, pc, sr, nacc);
		end
		$finish;
	end
endmodule
