`timescale 1ns/1ps
// jt8052 running dreamwld's MCU ROM (87c51rap.bin) against dreamwld.cpp's port model, with
// the 68020 side played by this bench the way MAME's trace shows it: write C00020, 50 us,
// read C00030, 50 us, 1737 times (docs/boot_trace_mame.txt). Pass: every byte read equals
// MCU ROM 0x3C + n, the stream MAME's 68020 receives.
//
// Port model, dreamwld.cpp 736-794:
//   prot_p1_w  port1 = data
//   prot_p2_w  bit 1 rising -> latch = port1; port2 = data
//   prot_p2_r  returns port2
//   to_prot_w  (68020 writes C00020)  port2 &= ~0x04
//   protdata_r (68020 reads C00030)   port2 &= ~0x08, returns latch
// jt8052 has no P2 write strobe, so a P2 write is seen as a change of p2_o. Every P2 write
// in this program toggles bit 0 or 1, so none is missed here.
//
// RUN FROM THE REPOSITORY ROOT, after python sim/mcu_tb/gen_fixture.py:
//     scripts/run_sim.sh mcu_tb [+BYTES=n]
module tb_mcu;
	localparam real HALF = 9.2593;          // 54 MHz clk_sys
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic rst = 1;

	// 16 MHz oscillator enable from 54 MHz: Bresenham 8/27
	logic [5:0] acc = 0;
	logic       cen = 0;
	always_ff @(posedge clk) begin
		if (acc + 6'd8 >= 6'd27) begin acc <= acc + 6'd8 - 6'd27; cen <= 1'b1; end
		else                     begin acc <= acc + 6'd8;         cen <= 1'b0; end
	end

	logic [7:0] rom [0:8191];
	initial $readmemh("sim/mcu_tb/mcu.hex", rom);

	logic [15:0] rom_addr;
	logic [7:0]  rom_q, ram [0:255], ram_q, ram_dout, ram_addr;
	logic        ram_we;
	always_ff @(posedge clk) if (cen) begin
		rom_q <= rom[rom_addr[12:0]];
		if (ram_we) ram[ram_addr] <= ram_dout;
		ram_q <= ram[ram_addr];
	end

	logic [7:0] p0_o, p1_o, p2_o, p3_o;
	logic [7:0] port2 = 8'h00, latch = 8'h00, p2_prev = 8'hff;

	jt8052 u_mcu (
		.rst(rst), .clk(clk), .cen(cen), .int0n(1'b1), .int1n(1'b1),
		.p0_i(8'hff), .p1_i(8'hff), .p2_i(port2), .p3_i(8'hff),
		.p0_o(p0_o), .p1_o(p1_o), .p2_o(p2_o), .p3_o(p3_o),
		.rom_data(rom_q), .rom_addr(rom_addr),
		.ram_din(ram_q), .ram_dout(ram_dout), .ram_addr(ram_addr), .ram_we(ram_we),
		.x_din(8'hff), .x_dout(), .x_addr(), .x_wr(), .x_acc(),
		.p3_we(), .p3_latch(), .p1_we()
	);

	// 68020-side events, set for one clk by the stimulus below
	logic cpu_wr = 0, cpu_rd = 0;
	always_ff @(posedge clk) begin
		p2_prev <= p2_o;
		if (!rst && p2_o != p2_prev) begin
			if (!port2[1] && p2_o[1]) latch <= p1_o;
			port2 <= p2_o;
		end else begin
			if (cpu_wr) port2 <= port2 & 8'hfb;
			if (cpu_rd) port2 <= port2 & 8'hf7;
		end
	end

	// +TRACE=n prints the first n ROM fetch addresses and port writes
	int trace = 0, ntr = 0;
	logic [15:0] ra_prev = 16'hffff;
	always @(posedge clk) if (!rst && trace > 0 && ntr < trace) begin
		if (cen && rom_addr != ra_prev) begin
			$display("%t rom_addr %04x p1 %02x p2 %02x port2 %02x", $time, rom_addr, p1_o, p2_o, port2);
			ntr++;
		end
		if (cen) ra_prev <= rom_addr;
	end

	int nbytes = 1737, errors = 0;
	logic [7:0] got;
	initial begin
		void'($value$plusargs("BYTES=%d", nbytes));
		void'($value$plusargs("TRACE=%d", trace));
		repeat (20) @(posedge clk);
		rst = 0;
		#30ms;                                   // the program's power-on delay loop
		for (int n = 0; n < nbytes; n++) begin
			@(posedge clk) cpu_wr = 1; @(posedge clk) cpu_wr = 0;
			#50us;
			@(posedge clk) begin got = latch; cpu_rd = 1; end
			@(posedge clk) cpu_rd = 0;
			if (got !== rom[16'h3c + n]) begin
				errors++;
				if (errors <= 10)
					$display("FAIL byte %0d: got %02x expected %02x (ROM %04x)", n, got, rom[16'h3c + n], 16'h3c + n);
			end
			#50us;
		end
		if (errors == 0) $display("PASS: %0d bytes match MCU ROM 0x3C.. (MAME's C00030 stream)", nbytes);
		else             $display("%0d of %0d bytes FAILED", errors, nbytes);
		$finish;
	end
endmodule
