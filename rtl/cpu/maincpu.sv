// SPDX-License-Identifier: GPL-3.0-or-later
// Main CPU: 68000 and its address decode, for snowbros.cpp's snowbros_map (182-198),
// hyperpac_map (341-356), finalttr_map (491-507) and yutnori_map (MAME master).
//
// The kernel is TG68KdotC_Kernel driven directly, as in the DreamWorld core this is adapted
// from: no async-bus wrapper, the CPU is stalled by holding clkena_in low until an access
// completes. Program ROM is req/valid; the RAMs are synchronous with one cycle of read
// latency. Unmapped reads return 0.
//
// Board variants, from the .mra mod byte:
//   semicom  ROM window 1 MB, no flip, no sound-latch read (hyperpac_map); else 256 KB
//   wram64   work RAM 0x100000-0x10FFFF; else 0x100000-0x103FFF (snowbros, finalttr)
//   cpu12    12 MHz; else 8 MHz (snowbros_base 1933, semicom 1998)
//   const_*  one read handler a set installs (3218, 3250, 3261, 3323)
//   yutnori  inputs 0x300000, the sound command byte 0x400001, palette 0x500000, Pandora
//            0x600000, 64 KB of work RAM 0x700000, no flip; the PIC at 0x200000 stands as MAME's
//            yutnori_prot_r: the last byte written, inverted, nibbles swapped
//
// Interrupts are ASSERT_LINE at lines 32 (level 4), 128 (3) and 240 (2) and stay asserted
// until the game writes the level's acknowledge address (snowbros.cpp 119-139); the CPU sees
// the highest pending level, autovectored.
//
// Pandora sprite RAM is 4 KB of bytes, one per word: a write stores the byte of the lane
// written (the low lane when both), a read returns it on both lanes (kan_pand.cpp 248-265).
//
// IPL: the kernel inverts its IPL input, so level n is requested by driving ~n.
//
// State (docs/STATE.md): the registers through gx_ss_m68k (MODE 2), which takes the CPU at
// an instruction boundary with a level-7 interrupt and serves a stub that stores and reloads
// them; none of its accesses reach the board. The pending interrupts are read and written
// through ss_irq_*.

module maincpu (
	input  logic         clk,          // 48 MHz
	input  logic         reset,

	input  logic         semicom,
	input  logic         wram64,
	input  logic         cpu12,
	input  logic         yutnori,
	input  logic         const_en,
	input  logic         const_at_500006,   // else 0x200000
	input  logic [15:0] const_val,

	// program ROM, req/valid: one pulse per access, word address into the 1 MB window
	output logic         rom_req,
	output logic [18:0] rom_addr,
	input  logic         rom_valid,
	input  logic [15:0] rom_data,

	// work RAM, up to 64 KB
	output logic [14:0] wram_addr,
	output logic         wram_wel, wram_weh,
	output logic [15:0] wram_wdata,
	input  logic [15:0] wram_rdata,

	// palette, 0x600000-0x6001FF
	output logic [7:0]  pal_addr,
	output logic         pal_wel, pal_weh,
	output logic [15:0] pal_wdata,
	input  logic [15:0] pal_rdata,

	// Pandora sprite RAM, 0x700000-0x701FFF, a byte per word
	output logic [11:0] spr_addr,
	output logic         spr_we,
	output logic [7:0]  spr_wdata,
	input  logic [7:0]  spr_rdata,

	// 0x500000 / 0x500002 / 0x500004
	input  logic [15:0] in_dsw1, in_dsw2, in_system,

	// sound latches at 0x300001
	output logic         snd_we,           // pulse; byte in snd_wdata
	output logic [7:0]  snd_wdata,
	input  logic [7:0]  snd_rdata,        // the Z80's reply (Toaplan board only)

	// flip, 0x400000 bit 7, inverted by the driver (89-93); Toaplan board only
	output logic         flip_we,
	output logic         flip_wdata,

	input  logic         irq4_line, irq3_line, irq2_line,   // pulses at lines 32, 128, 240
	input  logic         pause,

	// state: req and go held until held and done (gx_ss_m68k)
	input  logic         ss_req, ss_go,
	output logic         ss_held, ss_done,
	input  logic [4:0]  ss_bidx,
	input  logic         ss_bwe,
	input  logic [31:0] ss_bd,
	output logic [31:0] ss_bq,
	input  logic         ss_irq_we,
	input  logic [4:2]  ss_irq_d,
	output logic [4:2]  ss_irq_q
);

	// ---- clock enable: 8 MHz = 1/6, 12 MHz = 1/4 of 48 MHz ----
	logic [2:0] ce_cnt;
	logic       cpu_ce;
	always_ff @(posedge clk) begin
		if (reset) begin
			ce_cnt <= 3'd0;
			cpu_ce <= 1'b0;
		end else if (pause) begin
			cpu_ce <= 1'b0;
		end else begin
			cpu_ce <= ce_cnt == 3'd0;
			ce_cnt <= (ce_cnt == (cpu12 ? 3'd3 : 3'd5)) ? 3'd0 : ce_cnt + 3'd1;
		end
	end

	// ---- kernel ----
	logic [31:0] a32;
	logic [15:0] cpu_din, cpu_dout;
	logic [1:0]  busstate;
	logic        nWr, nUDS, nLDS;
	logic [2:0]  fc, ipl;
	logic        cpu_clkena, cpu_stop;
	logic        ss_hit, ss_rdy, ss_ipl7;
	logic [15:0] ss_din;

	TG68KdotC_Kernel #(
		.SR_Read(0), .VBR_Stackframe(0), .extAddr_Mode(0),
		.MUL_Mode(0), .DIV_Mode(0), .BitField(0),
		.BarrelShifter(0), .MUL_Hardware(1)
	) u_cpu (
		.clk(clk),
		.nReset(~reset),
		.clkena_in(cpu_clkena),
		.data_in(ss_hit ? ss_din : cpu_din),
		.IPL(ipl),
		.IPL_autovector(1'b1),
		.berr(1'b0),
		.CPU(2'b00),
		.addr_out(a32),
		.data_write(cpu_dout),
		.nWr(nWr), .nUDS(nUDS), .nLDS(nLDS),
		.busstate(busstate),
		.longword(),
		.nResetOut(),
		.FC(fc),
		.clr_berr(),
		.skipFetch(),
		.regin_out(), .CACR_out(), .VBR_out(), .FlagsSR_out(),
		.stop_out(cpu_stop)
	);

	// ---- decode ----
	wire [23:0] a = a32[23:0];
	wire is_rom    = semicom ? (a[23:20] == 4'h0) : (a[23:18] == 6'h00);
	wire is_wram   = yutnori ? (a[23:16] == 8'h70) : wram64 ? (a[23:16] == 8'h10) : (a[23:14] == 10'h040);
	// the latch (300000-300001); yutnori's command byte at 400001
	wire is_snd    = yutnori ? a[23:1] == 23'h200000 : a[23:1] == 23'h180000;
	wire is_flip   = !semicom && !yutnori && a[23:1] == 23'h200000; // 400000-400001
	wire is_in     = yutnori ? a[23:3] == 21'h060000 : a[23:3] == 21'h0A0000;   // 300000 / 500000
	wire is_pal    = yutnori ? a[23:9] == 15'h2800 : a[23:9] == 15'h3000;       // 500000 / 600000
	wire is_spr    = yutnori ? a[23:13] == 11'h300 : a[23:13] == 11'h380;       // 600000 / 700000
	wire is_prot   = yutnori && a[23:1] == 23'h100000;              // 200000
	wire is_ack4   = a[23:1] == 23'h400000;                         // 800000
	wire is_ack3   = a[23:1] == 23'h480000;                         // 900000
	wire is_ack2   = a[23:1] == 23'h500000;                         // A00000
	wire is_const  = const_en && (const_at_500006 ? a[23:1] == 23'h280003
	                                              : a[23:1] == 23'h100000);

	assign rom_addr  = a32[19:1];
	assign wram_addr = a32[15:1];
	assign pal_addr  = a32[8:1];
	assign spr_addr  = a32[12:1];

	logic [7:0]  prot_q;           // yutnori's last protection byte
	logic [15:0] read_mux;
	always_comb begin
		if      (is_const)               read_mux = const_val;
		else if (is_prot)                read_mux = {8'h00, ~{prot_q[3:0], prot_q[7:4]}};
		else if (is_wram)                read_mux = wram_rdata;
		else if (is_pal)                 read_mux = pal_rdata;
		else if (is_spr)                 read_mux = {spr_rdata, spr_rdata};
		else if (is_in && a[2:1] == 2'd0) read_mux = in_dsw1;
		else if (is_in && a[2:1] == 2'd1) read_mux = in_dsw2;
		else if (is_in && a[2:1] == 2'd2) read_mux = in_system;
		else if (is_snd && !semicom && !yutnori) read_mux = {8'h00, snd_rdata};
		else                             read_mux = 16'h0000;
	end

	// ---- bus access ----
	// acc_ph 0: address settling; 1: writes commit; 2: read data captured. acc_ready is a
	// level, so the next enable consumes it whenever it comes.
	logic        acc_ready, rom_req_sent;
	logic [15:0] acc_data;
	logic [1:0]  acc_ph;

	wire mem_needed = busstate != 2'b01;
	wire is_write   = busstate == 2'b11;
	assign cpu_clkena = cpu_ce && (!mem_needed || (ss_hit ? ss_rdy : acc_ready));
	assign rom_req = mem_needed && !ss_hit && !is_write && is_rom && !acc_ready && !rom_req_sent;

	always_ff @(posedge clk) begin
		if (reset) begin
			acc_ready    <= 1'b0;
			acc_data     <= 16'h0000;
			acc_ph       <= 2'd0;
			rom_req_sent <= 1'b0;
		end else if (cpu_clkena) begin
			acc_ready    <= 1'b0;
			acc_ph       <= 2'd0;
			rom_req_sent <= 1'b0;
		end else if (mem_needed && !acc_ready && !ss_hit) begin
			if (rom_req) rom_req_sent <= 1'b1;
			if (acc_ph != 2'd3) acc_ph <= acc_ph + 2'd1;
			if (is_rom && !is_write) begin
				if (rom_valid) begin
					acc_data  <= rom_data;
					acc_ready <= 1'b1;
				end
			end else begin
				if (!is_write && acc_ph == 2'd2) acc_data <= read_mux;
				if (is_write ? acc_ph >= 2'd1 : acc_ph >= 2'd2) acc_ready <= 1'b1;
			end
		end
	end
	assign cpu_din = acc_data;

	// ---- writes ----
	wire wr_now = mem_needed && is_write && !acc_ready && acc_ph == 2'd1 && !ss_hit;

	assign wram_wel   = wr_now && is_wram && !nLDS;
	assign wram_weh   = wr_now && is_wram && !nUDS;
	assign wram_wdata = cpu_dout;
	assign pal_wel    = wr_now && is_pal && !nLDS;
	assign pal_weh    = wr_now && is_pal && !nUDS;
	assign pal_wdata  = cpu_dout;
	assign spr_we     = wr_now && is_spr && !(nLDS && nUDS);
	assign spr_wdata  = !nLDS ? cpu_dout[7:0] : cpu_dout[15:8];
	assign snd_we     = wr_now && is_snd && !nLDS;
	assign snd_wdata  = cpu_dout[7:0];
	assign flip_we    = wr_now && is_flip && !nUDS;
	always_ff @(posedge clk) begin
		if (reset) prot_q <= 8'h00;
		else if (wr_now && is_prot && !nLDS) prot_q <= cpu_dout[7:0];
	end
	assign flip_wdata = cpu_dout[15];

	// ---- interrupts ----
	logic [4:2] irq_pend;
	assign ss_irq_q = irq_pend;
	always_ff @(posedge clk) begin
		if (reset) irq_pend <= 3'b000;
		else if (ss_irq_we) irq_pend <= ss_irq_d;
		else begin
			if (wr_now && is_ack4) irq_pend[4] <= 1'b0; else if (irq4_line) irq_pend[4] <= 1'b1;
			if (wr_now && is_ack3) irq_pend[3] <= 1'b0; else if (irq3_line) irq_pend[3] <= 1'b1;
			if (wr_now && is_ack2) irq_pend[2] <= 1'b0; else if (irq2_line) irq_pend[2] <= 1'b1;
		end
	end
	assign ipl = ss_ipl7 ? 3'b000 :
	             irq_pend[4] ? ~3'd4 : irq_pend[3] ? ~3'd3 : irq_pend[2] ? ~3'd2 : 3'b111;

	gx_ss_m68k #(.MODE(2)) u_ss (
		.clk(clk), .rst(reset),
		.acc(mem_needed), .take(cpu_clkena && mem_needed), .a32(a32), .wr(is_write),
		.fc(fc), .dout(cpu_dout), .iack7(1'b0), .stop_in(cpu_stop),
		.req(ss_req), .ipl7(ss_ipl7), .hit(ss_hit), .rdy(ss_rdy), .din(ss_din),
		.held(ss_held), .go(ss_go), .done(ss_done),
		.b_idx(ss_bidx), .b_we(ss_bwe), .b_d(ss_bd), .b_q(ss_bq)
	);

endmodule
