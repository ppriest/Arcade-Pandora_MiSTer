// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// A sound board against MAME: the 68000's latch writes replayed at MAME's times
// (sim/sound_tb/latch.txt, from scripts/mame_sndtrace.py), the Z80 program and the samples from
// the set's image; every chip write is logged to <OUT> as "<ns> Y <a0> <byte>" or "<ns> O <byte>"
// for scripts/mame_sndtrace.py compare. ROM and samples answer after a few clocks, as the SDRAM's
// caches do on a hit.
//
// RUN FROM THE REPOSITORY ROOT:
//     python sim/sound_tb/gen_fixture.py snowbros
//     scripts/run_sim.sh sound_tb +OUT=debug/snowbros-snd/rtl.txt +MS=3000
//     scripts/run_sim.sh sound_tb +SEMICOM +OUT=debug/hyperpac-snd/rtl.txt +MS=3000
//     scripts/run_sim.sh sound_tb +SEMICOM +FINALTTR +OUT=debug/finalttr-snd/rtl.txt +MS=3000
module tb_sound;
	localparam real HALF = 10.41667;   // 48 MHz
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic reset = 1, semicom = 0, finalttr = 0;

	logic [7:0] z80rom [0:65535], okirom [0:262143];
	initial begin
		$readmemh("sim/sound_tb/z80.hex", z80rom);
		$readmemh("sim/sound_tb/oki.hex", okirom);
	end

	// clock enables, as snowbros_core makes them
	logic [5:0] div = 0;
	logic       t_z80, t_ym, s_z80, s_ym, s_ymp1, s_oki, ymh = 0;
	always_ff @(posedge clk) begin
		div <= div == 6'd47 ? 6'd0 : div + 6'd1;
		t_z80 <= div[2:0] == 3'd0;
		t_ym  <= div[3:0] == 4'd0;
		s_z80 <= div == 6'd0 || div == 6'd12 || div == 6'd24 || div == 6'd36;
		s_ym  <= div == 6'd6 || div == 6'd18 || div == 6'd30 || div == 6'd42;
		if (div == 6'd6 || div == 6'd18 || div == 6'd30 || div == 6'd42) ymh <= ~ymh;
		s_ymp1 <= (div == 6'd6 || div == 6'd30);
		s_oki <= div == 6'd0;
	end
	logic [31:0] ft_acc = 0;
	logic        ft_cen = 0, ft_half = 0;
	always_ff @(posedge clk) begin
		{ft_cen, ft_acc} <= {1'b0, ft_acc} + 33'h0_1317_45A9;
		if (ft_cen) ft_half <= ~ft_half;
	end
	wire sz80 = finalttr ? ft_cen : s_z80, sym = finalttr ? ft_cen : s_ym;
	wire symp1 = finalttr ? ft_cen && ft_half : s_ymp1;

	logic [7:0]  latch_d = 0;
	logic        latch_we = 0;
	logic        rom_req, rom_valid = 0, oki_req, oki_valid = 0;
	logic [15:0] rom_addr;
	logic [14:0] t_rom_addr;
	logic [17:0] oki_addr;
	logic [7:0]  rom_data, oki_data;
	logic        t_rom_req, s_rom_req;
	logic [15:0] s_rom_addr;
	logic signed [15:0] t_audio, s_audio;

	toaplan_sound u_toa (
		.clk(clk), .reset(reset || semicom), .cen_z80(t_z80), .cen_ym(t_ym),
		.latch_data(latch_d), .latch_write(latch_we && !semicom), .reply(),
		.rom_req(t_rom_req), .rom_addr(t_rom_addr), .rom_valid(rom_valid && !semicom), .rom_data(rom_data),
		.audio(t_audio)
	);
	semicom_sound u_semi (
		.clk(clk), .reset(reset || !semicom), .cen_z80(sz80), .cen_ym(sym), .cen_ym_p1(symp1),
		.cen_oki(s_oki), .finalttr(finalttr),
		.latch_data(latch_d), .latch_write(latch_we && semicom),
		.rom_req(s_rom_req), .rom_addr(s_rom_addr), .rom_valid(rom_valid && semicom), .rom_data(rom_data),
		.oki_req(oki_req), .oki_addr(oki_addr), .oki_valid(oki_valid), .oki_data(oki_data),
		.audio(s_audio)
	);
	assign rom_req  = semicom ? s_rom_req : t_rom_req;
	assign rom_addr = semicom ? s_rom_addr : {1'b0, t_rom_addr};

	// ROM: a pulse in, data 4 clk later; samples: req held, data 6 clk later
	int rc = -1, oc = -1;
	logic [15:0] ra;
	always_ff @(posedge clk) begin
		rom_valid <= 1'b0; oki_valid <= 1'b0;
		if (rom_req) begin rc <= 4; ra <= rom_addr; end
		else if (rc > 0) rc <= rc - 1;
		else if (rc == 0) begin rom_valid <= 1'b1; rom_data <= z80rom[ra]; rc <= -1; end
		if (oki_req && oc < 0 && !oki_valid) oc <= 6;
		else if (oc > 0) oc <= oc - 1;
		else if (oc == 0) begin oki_valid <= 1'b1; oki_data <= okirom[oki_addr]; oc <= -1; end
	end

	// ---- the chip writes, as the chips take them ----
	string out = "debug/snd_rtl.txt";
	int    fd;
	logic  tw_d = 0, sy_d = 0, so_d = 0;
	wire   t_wr = !u_toa.iorq_n && !u_toa.wr_n && u_toa.io_ym;
	wire   s_wy = u_semi.mem_wr && u_semi.is_ym;
	wire   s_wo = u_semi.wr_now && u_semi.is_oki;
	always @(posedge clk) begin
		tw_d <= t_wr; sy_d <= s_wy;
		if (!semicom && t_wr && !tw_d) $fwrite(fd, "%0d Y %0d %02x\n", longint'($realtime), u_toa.a[0], u_toa.d_out);
		if (semicom && s_wy && !sy_d) $fwrite(fd, "%0d Y %0d %02x\n", longint'($realtime), u_semi.a[0], u_semi.d_out);
		if (semicom && s_wo) $fwrite(fd, "%0d O %02x\n", longint'($realtime), u_semi.d_out);
	end

	initial begin
		int lf, ms = 3000;
		longint t;
		int b;
		void'($value$plusargs("OUT=%s", out));
		void'($value$plusargs("MS=%d", ms));
		if ($test$plusargs("SEMICOM")) semicom = 1;
		if ($test$plusargs("FINALTTR")) finalttr = 1;
		fd = $fopen(out, "w");
		if (fd == 0) $fatal(1, "cannot write %s", out);
		lf = $fopen("sim/sound_tb/latch.txt", "r");
		repeat (4) @(posedge clk);
		reset = 0;
		fork
			while ($fscanf(lf, "%d %h", t, b) == 2) begin
				if (t > longint'(ms) * 1000000) break;
				#(t - longint'($realtime));
				@(negedge clk) begin latch_d = b[7:0]; latch_we = 1; end
				@(negedge clk) latch_we = 0;
			end
			#(longint'(ms) * 1ms);
		join_any
		disable fork;
		// the latch branch ends early when the next byte is past the end: run out the time
		// (a wait on $realtime never wakes)
		if (longint'($realtime) < longint'(ms) * 1000000) #(longint'(ms) * 1000000 - longint'($realtime));
		$fclose(fd);
		$display("%0d ms simulated", ms);
		$finish;
	end
endmodule
