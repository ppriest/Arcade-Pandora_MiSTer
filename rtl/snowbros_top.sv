// SPDX-License-Identifier: GPL-3.0-or-later
// rtl/snowbros_core.sv wired to rtl/memory/snowbros_sdram_top.sv, with the two reset domains
// of the DreamWorld core this follows: MiSTer holds RESET for the whole download, so
//   core_reset   holds the board during the download and the DDR3 copy;
//   sdram_reset  is low during the download, or sdram_download never leaves idle.
module snowbros_top (
	input  logic clk,
	input  logic reset,
	input  logic init,
	input  logic pause,

	output logic [12:0] SDRAM_A,
	output logic         SDRAM_DQML, SDRAM_DQMH,
	output logic [1:0]  SDRAM_BA,
	output logic         SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS,
	output logic         SDRAM_CLK, SDRAM_CKE,
	inout  wire [15:0]  SDRAM_DQ,

	input  logic         ioctl_download,
	input  logic [15:0] ioctl_index,
	input  logic         ioctl_wr,
	input  logic [24:0] ioctl_addr,
	input  logic [7:0]  ioctl_dout,
	output logic         ioctl_wait,

	input  logic         ldr_active, ldr_req, ldr_we16,
	input  logic [24:0] ldr_addr,
	input  logic [15:0] ldr_data,
	output logic         ldr_busy,

	input  logic [7:0]  mod0, mod1,
	input  logic [15:0] const_val,
	input  logic [7:0]  bg_pen,
	input  logic [14:0] ntiles,
	input  logic         flip_osd,
	input  logic [15:0] in_dsw1, in_dsw2, in_system,

	output logic         ce_pix,
	output logic [7:0]  r, g, b,
	output logic         hblank, vblank, hsync, vsync,
	output logic signed [15:0] audio
);
	wire core_reset  = reset | ioctl_download | ldr_active;
	wire sdram_reset = reset & ~ioctl_download;

	logic        cpu_rom_req, cpu_rom_valid, z80_rom_req, z80_rom_valid, g_req, g_valid;
	logic [18:0] cpu_rom_addr;
	logic [15:0] cpu_rom_data;
	logic [15:0] z80_rom_addr;
	logic        oki_rom_req, oki_rom_valid, okim_rom_req, okim_rom_valid;
	logic [17:0] oki_rom_addr;
	logic [18:0] okim_rom_addr;
	logic [7:0]  oki_rom_data, okim_rom_data;
	logic [7:0]  z80_rom_data;
	logic [17:0] g_addr;
	logic [63:0] g_data;
	logic        mcu_rom_we, prot_we;
	logic [11:0] mcu_rom_waddr;
	logic [7:0]  prot_waddr;
	logic [15:0] mcu_rom_wdata, prot_wdata;
	logic [1:0]  mcu_rom_wbe, prot_wbe;

	snowbros_core u_core (
		.clk(clk), .reset(core_reset), .pause(pause),
		.semicom(mod0[0]), .wram64(mod0[1]), .cpu12(mod0[2]),
		.has_mcu(mod0[6]), .mcu_base_f000(mod1[3]),
		.has_protdata(mod0[7]), .prot_at_2000(mod1[0]),
		.const_en(mod1[1]), .const_at_500006(mod1[2]), .const_val(const_val),
		.bg_pen(bg_pen), .ntiles(ntiles), .flip_osd(flip_osd), .finalttr(mod1[6]), .yutnori(mod1[7]),
		.in_dsw1(in_dsw1), .in_dsw2(in_dsw2), .in_system(in_system),
		.cpu_rom_req(cpu_rom_req), .cpu_rom_addr(cpu_rom_addr),
		.cpu_rom_valid(cpu_rom_valid), .cpu_rom_data(cpu_rom_data),
		.z80_rom_req(z80_rom_req), .z80_rom_addr(z80_rom_addr),
		.z80_rom_valid(z80_rom_valid), .z80_rom_data(z80_rom_data),
		.oki_rom_req(oki_rom_req), .oki_rom_addr(oki_rom_addr),
		.oki_rom_valid(oki_rom_valid), .oki_rom_data(oki_rom_data),
		.okim_rom_req(okim_rom_req), .okim_rom_addr(okim_rom_addr),
		.okim_rom_valid(okim_rom_valid), .okim_rom_data(okim_rom_data),
		.g_req(g_req), .g_addr(g_addr), .g_valid(g_valid), .g_data(g_data),
		.mcu_rom_we(mcu_rom_we), .mcu_rom_waddr(mcu_rom_waddr),
		.mcu_rom_wdata(mcu_rom_wdata), .mcu_rom_wbe(mcu_rom_wbe),
		.prot_we(prot_we), .prot_waddr(prot_waddr), .prot_wdata(prot_wdata), .prot_wbe(prot_wbe),
		.ce_pix(ce_pix), .r(r), .g(g), .b(b),
		.hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync),
		.audio(audio), .overruns()
	);

	snowbros_sdram_top u_sdram (
		.clk(clk), .reset(sdram_reset), .init(init),
		.SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
		.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .SDRAM_DQ(SDRAM_DQ),
		.ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.ioctl_wait(ioctl_wait),
		.ldr_active(ldr_active), .ldr_req(ldr_req), .ldr_addr(ldr_addr),
		.ldr_data(ldr_data), .ldr_we16(ldr_we16), .ldr_busy(ldr_busy),
		.gfx_semicom(mod0[3]), .toto(mod0[4]), .x4in1(mod0[5]),
		.g_req(g_req), .g_addr(g_addr), .g_valid(g_valid), .g_data(g_data),
		.cpu_rom_req(cpu_rom_req), .cpu_rom_addr(cpu_rom_addr),
		.cpu_rom_valid(cpu_rom_valid), .cpu_rom_data(cpu_rom_data),
		.z80_rom_req(z80_rom_req), .z80_rom_addr(z80_rom_addr),
		.z80_rom_valid(z80_rom_valid), .z80_rom_data(z80_rom_data),
		.oki_rom_req(oki_rom_req), .oki_rom_addr(oki_rom_addr), .oki_rom_valid(oki_rom_valid), .oki_rom_data(oki_rom_data),
		.yutnori(mod1[7]), .okim_rom_req(okim_rom_req), .okim_rom_addr(okim_rom_addr),
		.okim_rom_valid(okim_rom_valid), .okim_rom_data(okim_rom_data),
		.mcu_rom_we(mcu_rom_we), .mcu_rom_waddr(mcu_rom_waddr),
		.mcu_rom_wdata(mcu_rom_wdata), .mcu_rom_wbe(mcu_rom_wbe),
		.prot_we(prot_we), .prot_waddr(prot_waddr), .prot_wdata(prot_wdata), .prot_wbe(prot_wbe)
	);
endmodule
