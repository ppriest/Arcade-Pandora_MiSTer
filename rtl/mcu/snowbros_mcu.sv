// SPDX-License-Identifier: GPL-3.0-or-later
// The SemiCom protection MCU of hyperpac and cookbib2: an AT89C52 / 87C52 at 16 MHz (jt8052)
// running its own 8 KB program, writing the 68000's work RAM through its ports
// (snowbros.cpp prot_p0_w, prot_p1_w, prot_p2_w, 218-237):
//
//   P2 write   the word offset
//   P0 write   the low byte of work RAM word base + offset
//   P1 write   the high byte
//
// base is 0x7000 (hyperpac, 0x10E000) or 0x7800 (cookbib2, 0x10F000) words. MAME connects no
// port inputs or interrupts; they read idle here. The ROM is written by the download's tap,
// and read a byte at a time on cen with one cen of latency, as in the DreamWorld core's
// semicom_mcu.sv. Held in reset with the rest of the core.
module snowbros_mcu (
	input  logic         clk,          // 48 MHz
	input  logic         reset,
	input  logic         base_f000,    // base 0x10F000, else 0x10E000

	input  logic         rom_we,
	input  logic [11:0] rom_waddr,
	input  logic [15:0] rom_wdata,
	input  logic [1:0]  rom_wbe,

	output logic         wram_wel, wram_weh,
	output logic [14:0] wram_addr,
	output logic [15:0] wram_wdata
);
	// 16 MHz: one clk in three
	logic [1:0] div;
	wire        cen = div == 2'd0;
	always_ff @(posedge clk) div <= (reset || div == 2'd2) ? 2'd0 : div + 2'd1;

	logic [7:0]  rom_even [0:4095], rom_odd [0:4095];
	logic [7:0]  q_even, q_odd;
	logic        rom_hi;
	logic [15:0] rom_addr;
	always_ff @(posedge clk) begin
		if (rom_we && rom_wbe[0]) rom_even[rom_waddr] <= rom_wdata[7:0];
		if (cen) q_even <= rom_even[rom_addr[12:1]];
	end
	always_ff @(posedge clk) begin
		if (rom_we && rom_wbe[1]) rom_odd[rom_waddr] <= rom_wdata[15:8];
		if (cen) q_odd <= rom_odd[rom_addr[12:1]];
	end
	always_ff @(posedge clk) if (cen) rom_hi <= rom_addr[0];
	wire [7:0] rom_data = rom_hi ? q_odd : q_even;

	logic [7:0] ram [0:255];
	logic [7:0] ram_q, ram_dout, ram_addr;
	logic       ram_we;
	always_ff @(posedge clk) if (cen) begin
		if (ram_we) ram[ram_addr] <= ram_dout;
		ram_q <= ram[ram_addr];
	end

	logic [7:0] p0_o, p1_o, p2_o;
	logic       p0_we, p1_we, p2_we, p0_d, p1_d;

	jt8052 u_mcu (
		.rst(reset), .clk(clk), .cen(cen), .int0n(1'b1), .int1n(1'b1),
		.p0_i(8'hff), .p1_i(8'hff), .p2_i(8'hff), .p3_i(8'hff),
		.p0_o(p0_o), .p1_o(p1_o), .p2_o(p2_o), .p3_o(),
		.rom_data(rom_data), .rom_addr(rom_addr),
		.ram_din(ram_q), .ram_dout(ram_dout), .ram_addr(ram_addr), .ram_we(ram_we),
		.x_din(8'hff), .x_dout(), .x_addr(), .x_wr(), .x_acc(),
		.p3_we(), .p3_latch(), .p1_we(p1_we), .p2_we(p2_we), .p0_we(p0_we)
	);

	// the strobes are high for one cen period, the port already the new value: act on the
	// first clk. The offset is P2 as last written (p2_o).
	always_ff @(posedge clk) begin
		p0_d <= p0_we; p1_d <= p1_we;
	end
	assign wram_wel   = p0_we && !p0_d;
	assign wram_weh   = p1_we && !p1_d;
	assign wram_addr  = (base_f000 ? 15'h7800 : 15'h7000) + {7'd0, p2_o};
	assign wram_wdata = {p1_o, p0_o};
endmodule
