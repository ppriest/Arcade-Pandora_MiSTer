// SPDX-License-Identifier: GPL-3.0-or-later
// The Snow Bros sound board: Z80 at 6 MHz, YM3812 at 3 MHz (snowbros.cpp snowbros_base,
// 1931-1964).
//
//   sound_map (200-204)      0000-7FFF ROM, 8000-87FF RAM
//   sound_io_map (206-212)   02-03 YM3812, 04 r: the 68000's latch, w: the latch to the 68000
//
// The 68000's latch raises NMI while it holds unread data (generic_latch_8's data_pending,
// 1957); the Z80's read clears it. The YM3812's IRQ is the Z80's INT (1962). Mono, route 1.0.
//
// The Z80 side (T80se, split WAIT_n, a ROM request per M-cycle) is the Fuuki core's
// fg2_sound.sv, trimmed to this map.

module toaplan_sound (
	input  logic        clk,           // 48 MHz
	input  logic        reset,
	input  logic        cen_z80,       // 6 MHz, 1/8
	input  logic        cen_ym,        // 3 MHz, 1/16

	input  logic [7:0]  latch_data,    // from the 68000
	input  logic        latch_write,
	output logic [7:0]  reply,         // to the 68000

	output logic        rom_req,       // one pulse per access; data valid on rom_valid
	output logic [14:0] rom_addr,
	input  logic        rom_valid,
	input  logic [7:0]  rom_data,

	output logic signed [15:0] audio
);
	logic m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n;
	logic [15:0] a;
	logic [7:0]  di, d_out;
	logic        nmi_n, int_n, wait_n;

	T80se #(.Mode(0), .T2Write(0), .IOWait(1)) u_cpu (
		.RESET_n(~reset), .CLK_n(clk), .CLKEN(cen_z80), .WAIT_n(wait_n),
		.INT_n(int_n), .NMI_n(nmi_n), .BUSRQ_n(1'b1),
		.M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n),
		.RD_n(rd_n), .WR_n(wr_n), .RFSH_n(rfsh_n), .HALT_n(halt_n), .BUSAK_n(busak_n),
		.A(a), .DI(di), .DO(d_out)
	);

	wire is_rom = !a[15];
	wire is_ram = a[15:11] == 5'b10000;          // 8000-87FF
	assign rom_addr = a[14:0];

	logic [7:0] ram [0:2047];
	logic [7:0] ram_q;
	always_ff @(posedge clk) ram_q <= ram[a[10:0]];

	wire io_rd  = !iorq_n && !rd_n && m1_n;
	wire io_wr  = !iorq_n && !wr_n;
	wire io_ym  = a[7:1] == 7'h01;               // 02-03
	wire io_lat = a[7:0] == 8'h04;

	// ---- latches ----
	logic [7:0] latch_in;
	logic       pending, io_rd_d, io_wr_d;
	assign nmi_n = !pending;
	always_ff @(posedge clk) begin
		io_rd_d <= io_rd && io_lat;
		io_wr_d <= io_wr && io_lat;
		if (reset) begin
			pending <= 1'b0; latch_in <= 8'd0; reply <= 8'd0;
		end else begin
			if (latch_write) begin latch_in <= latch_data; pending <= 1'b1; end
			else if (io_rd && io_lat && !io_rd_d) pending <= 1'b0;
			if (io_wr && io_lat && !io_wr_d) reply <= d_out;
		end
	end

	// ---- YM3812 ----
	logic [7:0] ym_dout;
	logic signed [15:0] ym_snd;
	jtopl2 u_ym (
		.rst(reset), .clk(clk), .cen(cen_ym),
		.din(d_out), .addr(a[0]), .cs_n(~(io_ym && !iorq_n)), .wr_n(wr_n),
		.dout(ym_dout), .irq_n(int_n),
		.snd(ym_snd), .sample()
	);
	always_ff @(posedge clk) audio <= ym_snd;

	// ---- read mux, ROM handshake, WAIT_n ----
	wire mem_rd = !mreq_n && !rd_n;
	wire mem_wr = !mreq_n && !wr_n;
	wire rom_rd = mem_rd && is_rom;

	logic       rom_done, rom_pending, access_started;
	logic [7:0] rom_hold;

	always_comb begin
		if (mem_rd)     di = is_rom ? rom_hold : is_ram ? ram_q : 8'hFF;
		else if (io_rd) di = io_lat ? latch_in : io_ym ? ym_dout : 8'hFF;
		else            di = 8'hFF;
	end

	always_ff @(posedge clk) if (mem_wr && is_ram) ram[a[10:0]] <= d_out;

	wire access_now = (!mreq_n || !iorq_n) && (!rd_n || !wr_n);
	always_ff @(posedge clk) begin
		if (reset) access_started <= 1'b0;
		else       access_started <= access_now && !rom_rd;
	end

	always_ff @(posedge clk) begin
		if (reset) rom_pending <= 1'b0;
		else if (rom_rd && !rom_pending && !rom_done) rom_pending <= 1'b1;
		else if (rom_valid) rom_pending <= 1'b0;
	end
	assign rom_req = rom_rd && !rom_pending && !rom_done;

	always_ff @(posedge clk) begin
		if (reset) begin
			rom_done <= 1'b0; rom_hold <= 8'd0;
		end else if (rom_valid) begin
			rom_done <= 1'b1; rom_hold <= rom_data;
		end else if (!rom_rd) rom_done <= 1'b0;
	end

	assign wait_n = rom_rd ? rom_done : (access_now && !rom_rd) ? access_started : 1'b1;
endmodule
