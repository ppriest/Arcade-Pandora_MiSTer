`timescale 1ns/1ps
// jt6295 playing one phrase from dreamwld's oki1 ROM: the shortest valid phrase in the
// table, on channel 1 at full volume, with pin 7 low (ss = 0) and bank 0, as dreamwld.cpp
// configures the chip (lines 398-414, 826). A smoke test of the vendored copy, not a check
// against MAME's audio (Phase 4): pass when the status bit rises, samples reach the
// output, and the status bit falls again within the phrase's length.
//
// RUN FROM THE REPOSITORY ROOT, after python sim/oki_tb/gen_fixture.py:
//     scripts/run_sim.sh oki_tb [+PHRASE=n]
module tb_oki;
	localparam real HALF = 9.2593;          // 54 MHz clk_sys
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic rst = 1;

	// 1 MHz chip clock enable: 1 in 54
	logic [5:0] div = 0;
	wire cen = (div == 6'd0);
	always_ff @(posedge clk) div <= (div == 6'd53) ? 6'd0 : div + 6'd1;

	logic [7:0] rom [0:524287];
	initial $readmemh("sim/oki_tb/oki.hex", rom);

	logic [17:0] rom_addr;
	logic [7:0]  rom_q;
	// bank 0: the chip's 0x30000-0x3FFFF window is ROM 0x30000-0x3FFFF
	always_ff @(posedge clk) rom_q <= rom[{1'b0, rom_addr}];

	logic        wrn = 1;
	logic [7:0]  din = 0, dout;
	logic signed [13:0] sound;
	logic        sample;

	jt6295 #(.INTERPOL(0)) u_oki (
		.rst(rst), .clk(clk), .cen(cen), .ss(1'b0),
		.wrn(wrn), .din(din), .dout(dout),
		.rom_addr(rom_addr), .rom_data(rom_q), .rom_ok(1'b1),
		.sound(sound), .sample(sample)
	);

	task automatic write(input [7:0] d);
		@(posedge clk) begin din = d; wrn = 0; end
		repeat (200) @(posedge clk);
		wrn = 1;
		repeat (200) @(posedge clk);
	endtask

	int phrase = 0, start, stop, nonzero = 0, peak = 0, errors = 0;
	logic rose = 0, fell = 0;
	always @(posedge clk) if (sample && sound != 0) begin
		nonzero++;
		if ((sound < 0 ? -sound : sound) > peak) peak = sound < 0 ? -sound : sound;
	end

	initial begin
		// the shortest valid phrase, the same choice as gen_fixture.py
		for (int n = 1; n < 128; n++) begin
			int s, e;
			s = {rom[n*8], rom[n*8+1], rom[n*8+2]} & 18'h3ffff;
			e = {rom[n*8+3], rom[n*8+4], rom[n*8+5]} & 18'h3ffff;
			if (s >= 'h400 && s < e && (phrase == 0 || e - s < stop - start)) begin
				phrase = n; start = s; stop = e;
			end
		end
		if ($value$plusargs("PHRASE=%d", phrase)) begin
			start = {rom[phrase*8], rom[phrase*8+1], rom[phrase*8+2]} & 18'h3ffff;
			stop  = {rom[phrase*8+3], rom[phrase*8+4], rom[phrase*8+5]} & 18'h3ffff;
		end
		$display("phrase %0d: 0x%05x-0x%05x", phrase, start, stop);
		repeat (100) @(posedge clk);
		rst = 0;
		repeat (100) @(posedge clk);
		write(8'h80 | phrase[6:0]);
		write(8'h10);                           // channel 1, attenuation 0
		// 2 samples a byte at 1 MHz / 165: a byte lasts 330 us; allow twice that
		fork
			begin wait (dout[0]); rose = 1; wait (!dout[0]); fell = 1; end
			begin #(((stop - start + 1) * 330 * 2 + 2000) * 1us); end
		join_any
		disable fork;
		if (!rose)        begin errors++; $display("FAIL: channel 1 status never rose"); end
		if (!fell)        begin errors++; $display("FAIL: channel 1 status never fell"); end
		if (nonzero == 0) begin errors++; $display("FAIL: no non-zero sample"); end
		$display("%0d non-zero samples, peak |%0d|", nonzero, peak);
		if (errors == 0) $display("PASS: phrase %0d played and stopped", phrase);
		$finish;
	end
endmodule
