// SPDX-License-Identifier: GPL-3.0-or-later
// The SDRAM backend: the burst-4 controller's three ports (rtl/memory/sdram), as in the
// DreamWorld core this is adapted from, with
//   Port 0  unused
//   Port 1  Pandora graphics, dedicated (the per-line engine's deadline)
//   Port 2  sdram_arbiter6: c0 the M6295's samples (ahead of the round robin), c1 the Z80's
//           program, c2 the 68000's program; and the download's write port
// Every write into SDRAM passes dl_xform (the graphics reorder, toto's and 4in1boot's
// transforms). The MCU program and the protdata image are also tapped into block RAM as they
// are written.
//
// A granule's byte k is the byte at its address + k (sdram.sv's capture, sdram_phy's lanes);
// pandora_rom takes that order as it is.
module snowbros_sdram_top (
	input  logic clk,
	input  logic reset,
	input  logic init,

	output logic [12:0] SDRAM_A,
	output logic         SDRAM_DQML,
	output logic         SDRAM_DQMH,
	output logic [1:0]  SDRAM_BA,
	output logic         SDRAM_nCS,
	output logic         SDRAM_nWE,
	output logic         SDRAM_nRAS,
	output logic         SDRAM_nCAS,
	output logic         SDRAM_CLK,
	output logic         SDRAM_CKE,
	inout  wire [15:0]  SDRAM_DQ,

	input  logic         ioctl_download,
	input  logic [15:0] ioctl_index,
	input  logic         ioctl_wr,
	input  logic [24:0] ioctl_addr,
	input  logic [7:0]  ioctl_dout,
	output logic         ioctl_wait,

	input  logic         ldr_active,
	input  logic         ldr_req,
	input  logic [24:0] ldr_addr,
	input  logic [15:0] ldr_data,
	input  logic         ldr_we16,
	output logic         ldr_busy,

	input  logic         gfx_semicom, toto, x4in1,

	// Pandora graphics, granule index in the graphics region (pandora_rom)
	input  logic         g_req,
	input  logic [17:0] g_addr,
	output logic         g_valid,
	output logic [63:0] g_data,

	input  logic         cpu_rom_req,
	input  logic [18:0] cpu_rom_addr,     // word address, 1 MB
	output logic         cpu_rom_valid,
	output logic [15:0] cpu_rom_data,

	input  logic         z80_rom_req,
	input  logic [15:0] z80_rom_addr,
	output logic         z80_rom_valid,
	output logic [7:0]  z80_rom_data,

	input  logic         oki_rom_req,
	input  logic [17:0] oki_rom_addr,
	output logic         oki_rom_valid,
	output logic [7:0]  oki_rom_data,

	// yutnori's music M6295, {bank, address}; it has no Z80, so it takes the Z80's client
	input  logic         yutnori,
	input  logic         okim_rom_req,
	input  logic [18:0] okim_rom_addr,
	output logic         okim_rom_valid,
	output logic [7:0]  okim_rom_data,

	// written to block RAM as the download writes them
	output logic         mcu_rom_we,
	output logic [11:0] mcu_rom_waddr,
	output logic [15:0] mcu_rom_wdata,
	output logic [1:0]  mcu_rom_wbe,
	output logic         prot_we,
	output logic [7:0]  prot_waddr,
	output logic [15:0] prot_wdata,
	output logic [1:0]  prot_wbe
);
	// Byte offsets into the 32 MB SDRAM, each region sized for the largest in-scope set
	// (docs/HARDWARE_NOTES.md). scripts/build_mra.py reads these: the .mra layout.
	localparam logic [24:0] MAINCPU_BASE = 25'h0000000;   // 1 MB, 4in1boot
	localparam logic [24:0] GFX_BASE     = 25'h0100000;   // 2 MB
	localparam logic [24:0] SOUND_BASE   = 25'h0300000;   // 64 KB
	localparam logic [24:0] OKI_BASE     = 25'h0310000;   // 256 KB
	localparam logic [24:0] MCU_BASE     = 25'h0350000;   // 8 KB, also in block RAM
	localparam logic [24:0] PROT_BASE    = 25'h0352000;   // 512 B, also in block RAM
	localparam logic [24:0] ROM_END      = 25'h0352200;
	// yutnori's music ROM, past every other set's image; its OKI_BASE holds the voice ROM
	localparam logic [24:0] OKIM_BASE    = 25'h0360000;   // 512 KB, two banks
	localparam logic [24:0] YUT_END      = 25'h03E0000;

	wire inval = ioctl_download | ldr_active;

	logic [24:1] p0_addr, p1_addr, p2_addr;
	logic         p0_wrl, p0_wrh, p1_wrl, p1_wrh, p2_wrl, p2_wrh;
	logic [15:0] p0_din, p1_din, p2_din;
	logic [63:0] p0_dout, p1_dout, p2_dout;
	logic         p0_req, p1_req, p2_req;
	logic         p0_ack, p1_ack, p2_ack;

	sdram mem_ctrl (
		.SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
		.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .SDRAM_DQ(SDRAM_DQ),
		.init(init), .clk(clk),
		.addr0({1'b0, p0_addr}), .wrl0(p0_wrl), .wrh0(p0_wrh), .din0(p0_din), .dout0(p0_dout), .req0(p0_req), .ack0(p0_ack),
		.addr1({1'b0, p1_addr}), .wrl1(p1_wrl), .wrh1(p1_wrh), .din1(p1_din), .dout1(p1_dout), .req1(p1_req), .ack1(p1_ack),
		.addr2({1'b0, p2_addr}), .wrl2(p2_wrl), .wrh2(p2_wrh), .din2(p2_din), .dout2(p2_dout), .req2(p2_req), .ack2(p2_ack)
	);

	// ---- Port 0: unused ----
	assign p0_addr = '0; assign {p0_wrl, p0_wrh} = 2'b00; assign p0_din = '0; assign p0_req = 1'b0;

	// ---- Port 1: Pandora graphics. sdram_phy wants a pulse; this shim gives the held g_req
	// one (the DreamWorld core's sprite port, which found the bare connection issuing a second
	// transaction on the valid clock).
	typedef enum logic [1:0] {SP_IDLE, SP_ISSUE, SP_WAIT} spstate_t;
	spstate_t sp_st;
	logic sp_phy_req, sp_phy_busy;
	assign sp_phy_req = sp_st == SP_ISSUE && !sp_phy_busy;
	always_ff @(posedge clk or posedge reset) begin
		if (reset) sp_st <= SP_IDLE;
		else case (sp_st)
			SP_IDLE:  if (g_req && !g_valid) sp_st <= SP_ISSUE;
			SP_ISSUE: if (!sp_phy_busy)       sp_st <= SP_WAIT;
			SP_WAIT:  if (g_valid)            sp_st <= SP_IDLE;
			default: ;
		endcase
	end
	sdram_phy phy1 (
		.clk(clk), .reset(reset),
		.port_addr(p1_addr), .port_wrl(p1_wrl), .port_wrh(p1_wrh),
		.port_din(p1_din), .port_dout(p1_dout), .port_req(p1_req), .port_ack(p1_ack),
		.req(sp_phy_req), .we(1'b0), .we16(1'b0), .addr(GFX_BASE + {4'd0, g_addr, 3'd0}), .wdata(16'd0),
		.busy(sp_phy_busy), .valid(g_valid), .rdata(g_data)
	);

	// ---- Port 2: arbiter ----
	logic         p2phy_req, p2phy_we, p2phy_busy, p2phy_valid, p2phy_we16;
	logic [24:0] p2phy_addr;
	logic [15:0] p2phy_wdata;
	logic [63:0] p2phy_rdata;
	sdram_phy phy2 (
		.clk(clk), .reset(reset),
		.port_addr(p2_addr), .port_wrl(p2_wrl), .port_wrh(p2_wrh),
		.port_din(p2_din), .port_dout(p2_dout), .port_req(p2_req), .port_ack(p2_ack),
		.req(p2phy_req), .we(p2phy_we), .we16(p2phy_we16), .addr(p2phy_addr), .wdata(p2phy_wdata),
		.busy(p2phy_busy), .valid(p2phy_valid), .rdata(p2phy_rdata)
	);

	logic         c0_req, c1_req, c2_req;
	logic [24:0] c0_addr, c1_addr, c2_addr;
	logic         c0_valid, c1_valid, c2_valid, c3_valid, c4_valid;
	logic [63:0] c0_data, c1_data, c2_data, c3_data, c4_data;
	logic         arb_req, arb_we16, arb_busy;
	logic [24:0] arb_addr;
	logic [15:0] arb_data;

	sdram_arbiter6 u_arbiter (
		.clk(clk), .reset(reset),
		.phy_req(p2phy_req), .phy_we(p2phy_we), .phy_we16(p2phy_we16), .phy_addr(p2phy_addr), .phy_wdata(p2phy_wdata),
		.phy_busy(p2phy_busy), .phy_valid(p2phy_valid), .phy_rdata(p2phy_rdata),
		.c0_req(c0_req), .c0_addr(c0_addr), .c0_valid(c0_valid), .c0_data(c0_data),
		.c1_req(c1_req), .c1_addr(c1_addr), .c1_valid(c1_valid), .c1_data(c1_data),
		.c2_req(c2_req), .c2_addr(c2_addr), .c2_valid(c2_valid), .c2_data(c2_data),
		.c3_req(1'b0), .c3_addr('0), .c3_valid(c3_valid), .c3_data(c3_data),
		.c4_req(1'b0), .c4_addr('0), .c4_valid(c4_valid), .c4_data(c4_data),
		.dl_req(arb_req), .dl_addr(arb_addr), .dl_data(arb_data),
		.dl_we16(arb_we16), .dl_busy(arb_busy)
	);

	// ---- the write port: the DDR3 copy while it runs, else the byte stream; then dl_xform ----
	logic        dl_req, dl_busy, dl_we16, x_busy;
	logic [24:0] dl_addr;
	logic [15:0] dl_data;
	wire         s_req  = ldr_active ? ldr_req  : dl_req;
	wire  [24:0] s_addr = ldr_active ? ldr_addr : dl_addr;
	wire  [15:0] s_data = ldr_active ? ldr_data : dl_data;
	wire         s_we16 = ldr_active ? ldr_we16 : dl_we16;
	assign dl_busy  = ldr_active ? 1'b0 : x_busy;
	assign ldr_busy = ldr_active ? x_busy : 1'b0;

	dl_xform #(.MAINCPU_BASE(MAINCPU_BASE), .GFX_BASE(GFX_BASE), .SOUND_BASE(SOUND_BASE)) u_xform (
		.clk(clk), .reset(reset), .gfx_semicom(gfx_semicom), .toto(toto), .x4in1(x4in1),
		.s_req(s_req), .s_addr(s_addr), .s_data(s_data), .s_we16(s_we16), .s_busy(x_busy),
		.d_req(arb_req), .d_addr(arb_addr), .d_data(arb_data), .d_we16(arb_we16), .d_busy(arb_busy)
	);

	sdram_download u_download (
		.clk(clk), .reset(reset),
		.ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.ioctl_wait(ioctl_wait),
		.dl_req(dl_req), .dl_addr(dl_addr), .dl_data(dl_data), .dl_we16(dl_we16), .dl_busy(dl_busy)
	);

	// ---- block RAM taps: the rising edge of busy is one accepted write ----
	logic arb_busy_d;
	always_ff @(posedge clk) arb_busy_d <= arb_busy;
	wire        accept = arb_busy & ~arb_busy_d;
	wire [15:0] tap_d  = arb_we16 ? arb_data : {arb_data[7:0], arb_data[7:0]};
	wire [1:0]  tap_be = arb_we16 ? 2'b11 : (arb_addr[0] ? 2'b10 : 2'b01);
	assign mcu_rom_we    = accept && arb_addr >= MCU_BASE && arb_addr < MCU_BASE + 25'h2000;
	assign mcu_rom_waddr = arb_addr[12:1];
	assign mcu_rom_wdata = tap_d;
	assign mcu_rom_wbe   = tap_be;
	assign prot_we       = accept && arb_addr >= PROT_BASE && arb_addr < PROT_BASE + 25'h200;
	assign prot_waddr    = arb_addr[8:1];
	assign prot_wdata    = tap_d;
	assign prot_wbe      = tap_be;

	// ---- read clients ----
	logic [25:0] oki_g_addr;
	sample_cache #(.ENTRIES(8)) u_oki_cache (
		.clk(clk), .reset(reset), .inval(inval),
		.req(oki_rom_req), .addr({1'b0, OKI_BASE + {7'd0, oki_rom_addr}}),
		.valid(oki_rom_valid), .data(oki_rom_data),
		.g_req(c0_req), .g_addr(oki_g_addr), .g_valid(c0_valid), .g_data(c0_data)
	);
	assign c0_addr = oki_g_addr[24:0];

	logic        z_req, m_req;
	logic [24:0] z_addr;
	logic [25:0] m_addr;
	sdram_narrow_bridge #(.WORD_BYTES(1)) u_z80_bridge (
		.clk(clk), .reset(reset), .inval(inval),
		.req(z80_rom_req && !yutnori), .addr(SOUND_BASE + {9'd0, z80_rom_addr}),
		.valid(z80_rom_valid), .data(z80_rom_data),
		.g_req(z_req), .g_addr(z_addr), .g_valid(c1_valid && !yutnori), .g_data(c1_data)
	);
	sample_cache #(.ENTRIES(8)) u_okim_cache (
		.clk(clk), .reset(reset), .inval(inval),
		.req(okim_rom_req && yutnori), .addr({1'b0, OKIM_BASE + {6'd0, okim_rom_addr}}),
		.valid(okim_rom_valid), .data(okim_rom_data),
		.g_req(m_req), .g_addr(m_addr), .g_valid(c1_valid && yutnori), .g_data(c1_data)
	);
	assign c1_req  = yutnori ? m_req : z_req;
	assign c1_addr = yutnori ? m_addr[24:0] : z_addr;

	// the 68000's program is big-endian (ROM_LOAD16_BYTE); the bridge packs words little-endian
	logic [15:0] cpu_le;
	assign cpu_rom_data = {cpu_le[7:0], cpu_le[15:8]};
	sdram_narrow_bridge #(.WORD_BYTES(2)) u_cpu_bridge (
		.clk(clk), .reset(reset), .inval(inval),
		.req(cpu_rom_req), .addr(MAINCPU_BASE + {5'd0, cpu_rom_addr, 1'b0}),
		.valid(cpu_rom_valid), .data(cpu_le),
		.g_req(c2_req), .g_addr(c2_addr), .g_valid(c2_valid), .g_data(c2_data)
	);
endmodule
