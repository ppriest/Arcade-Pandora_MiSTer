// SPDX-License-Identifier: GPL-3.0-or-later
// The SemiCom sound board: Z80 at 16 MHz / 4, YM2151 at 16 MHz / 4, M6295 at 16 MHz / 16 with
// pin 7 high (snowbros.cpp semicom, 1993-2019).
//
//   hyperpac_sound_map (358-365)   0000-CFFF ROM, D000-D7FF RAM, F000-F001 YM2151,
//                                  F002 M6295, F008 r: the 68000's latch
//
// The latch raises nothing (data_pending set_nop, 2007): the Z80 reads it when it likes. The
// YM2151's IRQ is the Z80's INT (2013). Mono: the YM2151's two outputs at 0.10 each, the M6295 at
// 1.0 (2011-2018). jt6295 is scaled by 16 to MAME's full scale (the Vamphalf core's vh_ymoki),
// and 0.10 is 1/16 + 1/32 + 1/256 + 1/512 (0.0996), by shifts.
//
// The Z80 side is toaplan_sound's. The YM2151's write strobe is the whole Z80 write: jt51 takes the
// register on any clk (a repeat is the same write) but sets its busy flag only on cen, which the
// driver polls. The M6295's is one clk, on the first of the write: a command is taken once.

module semicom_sound (
	input  logic        clk,           // 48 MHz
	input  logic        reset,
	input  logic        cen_z80,       // 4 MHz, 1/12
	input  logic        cen_ym,        // 4 MHz, 1/12
	input  logic        cen_ym_p1,     // 2 MHz, every other cen_ym
	input  logic        cen_oki,       // 1 MHz, 1/48

	input  logic        finalttr,      // 3.579545 MHz board: routes 0.08 and 0.4 (2141-2151)

	input  logic [7:0]  latch_data,
	input  logic        latch_write,

	output logic        rom_req,
	output logic [15:0] rom_addr,
	input  logic        rom_valid,
	input  logic [7:0]  rom_data,

	// M6295 samples, req held until valid (sample_cache in snowbros_sdram_top)
	output logic        oki_req,
	output logic [17:0] oki_addr,
	input  logic        oki_valid,
	input  logic [7:0]  oki_data,

	output logic signed [15:0] audio
);
	logic m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n;
	logic [15:0] a;
	logic [7:0]  di, d_out;
	logic        int_n, wait_n;

	T80se #(.Mode(0), .T2Write(0), .IOWait(1)) u_cpu (
		.RESET_n(~reset), .CLK_n(clk), .CLKEN(cen_z80), .WAIT_n(wait_n),
		.INT_n(int_n), .NMI_n(1'b1), .BUSRQ_n(1'b1),
		.M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n),
		.RD_n(rd_n), .WR_n(wr_n), .RFSH_n(rfsh_n), .HALT_n(halt_n), .BUSAK_n(busak_n),
		.A(a), .DI(di), .DO(d_out)
	);

	wire is_rom = a < 16'hD000;
	wire is_ram = a[15:11] == 5'b11010;          // D000-D7FF
	wire is_ym  = a[15:1] == 15'h7800;           // F000-F001
	wire is_oki = a == 16'hF002;
	wire is_lat = a == 16'hF008;
	assign rom_addr = a;

	logic [7:0] ram [0:2047];
	logic [7:0] ram_q;
	always_ff @(posedge clk) ram_q <= ram[a[10:0]];

	wire mem_rd = !mreq_n && !rd_n;
	wire mem_wr = !mreq_n && !wr_n;
	wire rom_rd = mem_rd && is_rom;

	// ---- latch ----
	logic [7:0] latch_in;
	always_ff @(posedge clk) begin
		if (reset) latch_in <= 8'd0;
		else if (latch_write) latch_in <= latch_data;
	end

	// ---- one-clk write strobes ----
	logic wr_d;
	always_ff @(posedge clk) wr_d <= mem_wr;
	wire wr_now = mem_wr && !wr_d;

	// ---- YM2151 ----
	logic [7:0] ym_dout;
	logic signed [15:0] ym_l, ym_r;
	jt51 u_ym (
		.rst(reset), .clk(clk), .cen(cen_ym), .cen_p1(cen_ym_p1),
		.cs_n(~(mem_wr && is_ym)), .wr_n(~(mem_wr && is_ym)), .a0(a[0]), .din(d_out), .dout(ym_dout),
		.ct1(), .ct2(), .irq_n(int_n), .sample(),
		.left(ym_l), .right(ym_r), .xleft(), .xright()
	);

	// ---- M6295 ----
	logic [17:0] oki_rom_addr;
	logic [7:0]  oki_rom_data, oki_dout;
	logic        oki_rom_ok;
	logic signed [13:0] oki_snd;
	jt6295 #(.INTERPOL(0)) u_oki (
		.rst(reset), .clk(clk), .cen(cen_oki), .ss(1'b1),
		.wrn(~(wr_now && is_oki)), .din(d_out), .dout(oki_dout),
		.rom_addr(oki_rom_addr), .rom_data(oki_rom_data), .rom_ok(oki_rom_ok),
		.sound(oki_snd), .sample()
	);
	logic [19:0] br_addr;
	oki_rom_bridge u_bridge (
		.clk(clk), .reset(reset),
		.rom_addr(oki_rom_addr), .rom_data(oki_rom_data), .rom_ok(oki_rom_ok), .bank(2'd0),
		.req(oki_req), .addr(br_addr), .valid(oki_valid), .data(oki_data)
	);
	assign oki_addr = br_addr[17:0];

	// ---- read mux, ROM handshake, WAIT_n (toaplan_sound's) ----
	logic       rom_done, rom_pending, access_started;
	logic [7:0] rom_hold;

	always_comb begin
		if (mem_rd)
			di = is_rom ? rom_hold : is_ram ? ram_q : is_ym ? ym_dout : is_oki ? oki_dout :
			     is_lat ? latch_in : 8'hFF;
		else di = 8'hFF;
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

	// ---- mix ----
	logic signed [16:0] ym_sum;
	logic signed [20:0] ym_10, mix;
	always_ff @(posedge clk) begin
		ym_sum <= 17'(ym_l) + 17'(ym_r);
		// 0.10 = 1/16 + 1/32 + 1/256 + 1/512; finalttr's 0.08 = 1/16 + 1/64 + 1/512
		ym_10  <= finalttr ? (21'(ym_sum) >>> 4) + (21'(ym_sum) >>> 6) + (21'(ym_sum) >>> 9)
		                   : (21'(ym_sum) >>> 4) + (21'(ym_sum) >>> 5) + (21'(ym_sum) >>> 8) + (21'(ym_sum) >>> 9);
		// x16 (full scale); finalttr's 0.4 of it is x6.4 = 4 + 2 + 1/4 + 1/8 + 1/64
		mix    <= ym_10 + (finalttr ? (21'(oki_snd) <<< 2) + (21'(oki_snd) <<< 1) + (21'(oki_snd) >>> 2)
		                              + (21'(oki_snd) >>> 3) + (21'(oki_snd) >>> 6)
		                            : (21'(oki_snd) <<< 4));
		audio  <= mix > 21'sd32767 ? 16'sd32767 : mix < -21'sd32768 ? 16'sh8000 : mix[15:0];
	end
endmodule
