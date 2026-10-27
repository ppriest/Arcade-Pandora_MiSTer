// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// A set's boot on maincpu, against MAME. Program ROM from sim/boot_tb/gen_fixture.py; RAMs are
// block-RAM models; inputs held at the values MAME's CPU read (debug/<set>-boot/<set>_boot.trace);
// interrupts from a 354 x 262 raster at 48 MHz / 9.
//
// No Z80: 0x300000 reads +SND (MAME's Z80 answers 0x03 on snowbros, read once).
//
// Writes every access the 68000 completes, as "seq rw addr mask data" with a word-aligned
// address and a 16-bit lane mask, to debug/<set>-boot/<set>_rtl.trace for
// scripts/compare_boot_trace.py, up to +MAXACC accesses or +MS milliseconds.
//
// RUN FROM THE REPOSITORY ROOT, after python sim/boot_tb/gen_fixture.py <set>:
//     scripts/run_sim.sh boot_tb +SET=snowbros +IN1=7ffe +IN2=7fff +IN3=ff00 +SND=03
//     scripts/run_sim.sh boot_tb +SET=hyperpac +SEMICOM +IN1=00fe +IN2=0000 +IN3=f000
module tb_boot;
	localparam real HALF = 10.41667;   // 48 MHz
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic reset = 1;

	// ---- raster: 3186 clk a line, 262 lines; IRQ lines 32, 128, 240 ----
	int unsigned hc = 0, vc = 0;
	logic irq4, irq3, irq2;
	always_ff @(posedge clk) begin
		if (hc == 3185) begin
			hc <= 0;
			vc <= (vc == 261) ? 0 : vc + 1;
		end else hc <= hc + 1;
		irq4 <= hc == 0 && vc == 32;
		irq3 <= hc == 0 && vc == 128;
		irq2 <= hc == 0 && vc == 240;
	end

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
	logic [7:0]  snd = 8'h00;
	logic        semicom = 0;
	logic        snd_we, flip_we, flip_wdata;
	logic [7:0]  snd_wdata;

	maincpu dut (
		.clk(clk), .reset(reset),
		.semicom(semicom), .wram64(semicom), .cpu12(semicom), .yutnori(1'b0),
		.const_en(1'b0), .const_at_500006(1'b0), .const_val(16'h0000),
		.rom_req(rom_req), .rom_addr(rom_addr), .rom_valid(rom_valid), .rom_data(rom_data),
		.wram_addr(wram_addr), .wram_wel(wram_wel), .wram_weh(wram_weh),
		.wram_wdata(wram_wdata), .wram_rdata(wram_rdata),
		.pal_addr(pal_addr), .pal_wel(pal_wel), .pal_weh(pal_weh),
		.pal_wdata(pal_wdata), .pal_rdata(pal_rdata),
		.spr_addr(spr_addr), .spr_we(spr_we), .spr_wdata(spr_wdata), .spr_rdata(spr_rdata),
		.in_dsw1(in1), .in_dsw2(in2), .in_system(in3),
		.snd_we(snd_we), .snd_wdata(snd_wdata), .snd_rdata(snd),
		.flip_we(flip_we), .flip_wdata(flip_wdata),
		.irq4_line(irq4), .irq3_line(irq3), .irq2_line(irq2),
		.pause(1'b0)
	);

	// ---- trace ----
	string set = "snowbros";
	int    fd, nacc = 0, maxacc = 4500000, iacks = 0;
	wire   consume = dut.cpu_clkena && (dut.busstate != 2'b01);
	always @(posedge clk) if (!reset && consume) begin
		logic [15:0] mask, w;
		logic        wr;
		if (dut.fc == 3'b111) iacks++;
		else if (nacc < maxacc) begin
			wr   = dut.busstate == 2'b11;
			w    = wr ? dut.cpu_dout : dut.acc_data;
			mask = {(dut.nUDS ? 8'h00 : 8'hff), (dut.nLDS ? 8'h00 : 8'hff)};
			if (!wr && dut.nUDS && dut.nLDS) mask = 16'hffff;
			nacc++;
			$fwrite(fd, "%0d\t%s\t%06X\t%04X\t%04X\n", nacc, wr ? "w" : "r",
			        {dut.a32[23:1], 1'b0}, mask, w & mask);
		end
	end

	int ms = 3000;
	initial begin
		void'($value$plusargs("MS=%d", ms));
		void'($value$plusargs("MAXACC=%d", maxacc));
		void'($value$plusargs("SET=%s", set));
		void'($value$plusargs("IN1=%h", in1));
		void'($value$plusargs("IN2=%h", in2));
		void'($value$plusargs("IN3=%h", in3));
		void'($value$plusargs("SND=%h", snd));
		if ($test$plusargs("SEMICOM")) semicom = 1;
		fd = $fopen($sformatf("debug/%s-boot/%s_rtl.trace", set, set), "w");
		if (fd == 0) $fatal(1, "cannot open debug/%s-boot/%s_rtl.trace (run mame_boot_trace.py first)", set, set);
		$fwrite(fd, "# RTL bus accesses from reset (sim/boot_tb), seq rw addr mask data\n");
		repeat (20) @(posedge clk);
		reset = 0;
		fork
			begin wait (nacc >= maxacc); end
			begin #(longint'(ms) * 1ms); end
		join_any
		disable fork;
		$fclose(fd);
		$display("%s: %0d accesses traced, %0d interrupt acknowledges, %0t", set, nacc, iacks, $time);
		$finish;
	end
endmodule
