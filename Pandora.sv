// SPDX-License-Identifier: GPL-3.0-or-later
//
// MiSTer glue for the Snow Bros / SemiCom Pandora boards (MAME kaneko/snowbros.cpp), wiring
// rtl/snowbros_top.sv into the framework. Adapted from the DreamWorld core's DreamWorld.sv.
//
// Every in-scope set is ROT0. Orientation CW/CCW turns the HDMI picture for a vertical monitor
// (screen_rotate_two, the HPS framebuffer in DDR3); the analog output stays native. DDR3 is the
// fast ROM load's during the copy and the rotator's the rest of the time.
module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign FB_FORCE_BLANK = 0;   // required with MISTER_FB; the rotator has no blanking need

// The board is mono (one "mono" speaker in every config). Audio mix: status 0 Mono
// (AUDIO_MIX 3), 1 None (0), 2 25% (1), 3 50% (2).
assign AUDIO_S   = 1;
assign AUDIO_MIX = status[80:79] - 2'd1;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

`include "build_id.v"
`ifdef DEBUG_ISSP
localparam DEBUG_MENU_HIDE = 1'b0;
`else
localparam DEBUG_MENU_HIDE = 1'b1;
`endif

localparam CONF_STR = {
	"Pandora;;",
	"-;",
	"H5O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H5O[48:47],Orientation,Off,CW,CCW;",
	"O[49],Flip Screen,Off,On;",
	"H5O[93:91],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;",
	"H5O[94],Vertical crop,Disabled,216p (5x);",
	"H5O[99:95],Crop offset,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H5O[46:44],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"O[80:79],Audio mix,Mono,None,25%,50%;",
	"O[64],CRT Adjust,Off,On;",
	"H2O[71:65],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H2O[77:72],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H2O[85:81],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H2O[89:86],CRT V-Size,0,+1,+2,+3,+4,+5,+6,+7,-7,-6,-5,-4,-3,-2,-1;",
	"H2O[90],CRT V-Size Mode,PVM,Cabinet;",
	"-;",
	"DIP;",
	"-;",
	"R[0],Reset;",
	"J1,Button 1,Button 2,Button 3,Button 4,Button 5,Button 6,Start,Coin,Pause;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler, direct_video;
wire  [21:0] gamma_bus;
wire         video_rotated;
wire  [1:0]  buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [31:0] joystick_0, joystick_1;
wire         ioctl_download, ioctl_wr, ioctl_wait;
wire  [15:0] ioctl_index;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	// H2 CRT Adjust's settings while it is off; H5 the HDMI scaler's options under direct video
	.status_menumask({direct_video, 2'b00, ~status[64], DEBUG_MENU_HIDE, status[5]}),
	.direct_video(direct_video),
	.video_rotated(video_rotated),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	.ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

// clk_sys = 48 MHz; outclk_1 the SDRAM clock, phase-shifted (rtl/pll/pll_0002.v)
wire clk_sys, clk_sdram_shifted, pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram_shifted),
	.locked(pll_locked)
);
assign SDRAM_CLK = clk_sdram_shifted;

// The DDR3 copy is not in `reset`: the loader writes SDRAM through snowbros_top, which holds
// only the core during the copy (the DreamWorld and Psikyo cores).
wire reset = RESET | status[0] | buttons[1] | ~pll_locked;

///////////////////////   CONFIGURATION   ////////////////////////

// .mra mod bytes, <rom index="1"> (scripts/build_mra.py):
//   0  [0] SemiCom map  [1] 64 KB work RAM  [2] 68000 at 12 MHz  [3] SemiCom graphics layout
//      [4] toto's bit swap  [5] 4in1boot's transforms  [6] protection MCU  [7] protdata image
//   1  [0] protdata at 0x102000 (finalttr), else 0x10F000  [1] a constant read
//      [2] ...at 0x500006, else 0x200000  [3] the MCU's base 0x10F000, else 0x10E000
//      [4] active-high inputs (hyperpac's ports), else active low (snowbros', finalttr's,
//      4in1boot's)  [5] suhosong's ports  [6] finalttr's sound clocks  [7] yutnori's board
//   2-3  the constant (high, low)   4  bg_pen   5-6  tile count (high, low)
// Latched, not reset by `reset`: MiSTer holds reset through the download.
reg [7:0] mod [0:7];
always @(posedge clk_sys)
	if (ioctl_wr && ioctl_index == 16'd1 && ioctl_addr[26:3] == 0) mod[ioctl_addr[2:0]] <= ioctl_dout;

// DIP switches: an ioctl download, index 254 (Main_MiSTer arcade_sw_send). Byte 0 DSW1,
// byte 1 DSW2, byte 2 bit 0 the fake Flip Screen switch (not on the boards; read by the core).
reg [63:0] dip_sw;
always @(posedge clk_sys)
	if (ioctl_wr && ioctl_index == 16'd254 && !ioctl_addr[24:3])
		dip_sw[{ioctl_addr[2:0], 3'b000} +: 8] <= ioctl_dout;

wire semicom = mod[0][0];

///////////////////////   INPUTS   ////////////////////////////////

// MiSTer joystick bits: 0 R, 1 L, 2 D, 3 U, 4-9 buttons, 10 Start, 11 Coin, 12 Pause (the J1
// line and every .mra's <buttons>). MAME's default keys beside the pads (rtl/mame_keys.sv).
wire [31:0] key0, key1;
mame_keys #(.BUTTONS(3)) u_mame_keys (
	.clk(clk_sys), .ps2_key(ps2_key), .key0(key0), .key1(key1), .svc_coin()
);
wire [31:0] joy0 = joystick_0 | key0;
wire [31:0] joy1 = joystick_1 | key1;

// Three layouts, from INPUT_PORTS (line numbers in snowbros.cpp):
//   active low (snowbros 565-644, finalttr 1613-1690, 4in1boot): bits 8-14 of DSW1 / DSW2 UP,
//     DOWN, LEFT, RIGHT, B1, B2, B3 of each player, the DSW in bits 7-0; SYSTEM bits 8-11
//     START1, START2, COIN1, COIN2, 12-15 idle high; bit 15 of DSW1/2 "Must be low"
//   active high (hyperpac 907-966 and its kin): the same bits, inverted; SYSTEM 12-15 idle high
//   suhosong: one player, DSW1 bits 8 B4, 9 B1, 10 B2, 11 B3, 13 B6; SYSTEM 8 B5 (its start),
//     10-11 COIN1-2; everything else idle low
wire       act_hi = mod[1][4];
wire       suho   = mod[1][5];
wire [6:0] p1 = {joy0[6], joy0[5], joy0[4], joy0[0], joy0[1], joy0[2], joy0[3]};
wire [6:0] p2 = {joy1[6], joy1[5], joy1[4], joy1[0], joy1[1], joy1[2], joy1[3]};
wire [3:0] sy = {joy1[11], joy0[11], joy1[10], joy0[10]};
wire [15:0] in_dsw1   = suho   ? {2'b00, joy0[8], 1'b0, joy0[6], joy0[5], joy0[4], joy0[7], dip_sw[7:0]} :
                        act_hi ? {1'b0, p1, dip_sw[7:0]} : {1'b0, ~p1, dip_sw[7:0]};
wire [15:0] in_dsw2   = suho   ? {8'h00, dip_sw[15:8]} :
                        act_hi ? {1'b0, p2, dip_sw[15:8]} : {1'b0, ~p2, dip_sw[15:8]};
wire [15:0] in_system = suho   ? {4'h0, joy1[11], joy0[11], 1'b0, joy0[10], 8'h00} :
                        act_hi ? {4'hF, sy, 8'h00} : {4'hF, ~sy, 8'h00};

// Pause: the Pause button toggles it; the 68000 and the Z80 stop.
wire pause_btn = joy0[12] | joy1[12];
reg  pause_btn_d, pause;
always @(posedge clk_sys) begin
	pause_btn_d <= pause_btn;
	if (reset) pause <= 1'b0;
	else if (pause_btn & ~pause_btn_d) pause <= ~pause;
end

// One flip: the OSD's or the fake DIP's, XOR the game's own register (snowbros_core)
wire flip_osd = status[49] ^ dip_sw[16];

///////////////////////   CORE   //////////////////////////////////

wire        ce_pix, hblank, vblank, hsync, vsync;
wire  [7:0] r, g, b;
wire signed [15:0] audio;
wire        ldr_active, ldr_req, ldr_we16, ldr_busy;
wire [24:0] ldr_addr;
wire [15:0] ldr_data;

snowbros_top u_top (
	.clk(clk_sys), .reset(reset), .init(~pll_locked), .pause(pause),
	.SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(), .SDRAM_CKE(SDRAM_CKE),
	.SDRAM_DQ(SDRAM_DQ),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr[24:0]), .ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
	.ldr_active(ldr_active), .ldr_req(ldr_req), .ldr_addr(ldr_addr), .ldr_data(ldr_data),
	.ldr_we16(ldr_we16), .ldr_busy(ldr_busy),
	.mod0(mod[0]), .mod1(mod[1]), .const_val({mod[2], mod[3]}), .bg_pen(mod[4]),
	.ntiles({mod[5][6:0], mod[6]}), .flip_osd(flip_osd),
	.in_dsw1(in_dsw1), .in_dsw2(in_dsw2), .in_system(in_system),
	.ce_pix(ce_pix), .r(r), .g(g), .b(b),
	.hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .audio(audio)
);

///////////////////////   VIDEO   //////////////////////////////////

// Orientation: status 0 Off, 1 CW, 2 CCW. Aspect 4:3 whatever the pixel count, 3:4 rotated;
// ARY 0 means "stretch" to video_freak
wire        rotate_en  = status[48:47] != 2'd0;
wire        rotate_ccw = status[48:47] == 2'd2;
wire [1:0]  ar       = status[122:121];
wire [11:0] base_arx = (!ar) ? (rotate_en ? 12'd3 : 12'd4) : 12'({ar} - 2'd1);
wire [11:0] base_ary = (!ar) ? (rotate_en ? 12'd4 : 12'd3) : 12'd0;

// CRT Adjust (rtl/video/crt_chain.sv): moves the picture inside the line, sync untouched.
// H-Position's list has 97 entries, so its negative half wraps at 97; V-Size's 15 at 15.
wire crt_adj_on   = status[64];
wire crt_scale_en = ~(forced_scandoubler | |status[46:44]);
wire  [6:0] crt_hpos_idx = status[71:65];
wire signed [8:0] crt_hoffset = (crt_hpos_idx <= 7'd48) ? $signed({2'b00, crt_hpos_idx})
                                                         : $signed({2'b00, crt_hpos_idx}) - 9'sd97;
wire signed [5:0] crt_voffset = $signed(status[77:72]);
wire signed [4:0] crt_hsize   = $signed(status[85:81]);
wire  [3:0] crt_vsz_idx  = status[89:86];
wire signed [3:0] crt_vsz_step = (crt_vsz_idx <= 4'd7) ? $signed(crt_vsz_idx) : $signed(crt_vsz_idx - 4'd15);

wire       crt_ce;
wire [7:0] crt_r, crt_g, crt_b;
wire       crt_hs, crt_vs, crt_hb, crt_vb;
crt_chain #(.HTOTAL(354), .VTOTAL(262), .ACTIVE_W(256), .RD_BASE(36)) crt_chain   // 9 clk a pixel, x4
(
	.clk(clk_sys), .ce_pix(ce_pix),
	.active(crt_adj_on), .scale_en(crt_scale_en),
	.hoffset(crt_hoffset), .voffset(crt_voffset), .hsize(crt_hsize),
	.vsize_step(crt_vsz_step), .vsize_cabinet(status[90]),
	.r_in(r), .g_in(g), .b_in(b),
	.hs_in(hsync), .vs_in(vsync), .hb_in(hblank), .vb_in(vblank),
	.ce_out(crt_ce), .r_out(crt_r), .g_out(crt_g), .b_out(crt_b),
	.hs_out(crt_hs), .vs_out(crt_vs), .hb_out(crt_hb), .vb_out(crt_vb)
);

wire vga_de_raw;
arcade_video #(.WIDTH(256), .DW(24), .GAMMA(1)) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(crt_ce),
	.RGB_in({crt_r, crt_g, crt_b}),
	.HBlank(crt_hb), .VBlank(crt_vb), .HSync(crt_hs), .VSync(crt_vs),
	.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(vga_de_raw), .VGA_SL(VGA_SL),
	.fx(status[46:44]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

// integer scaling, crop, aspect: 216 of the 224 lines is 5x on a 1080-line display
video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL), .VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH), .HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE), .VIDEO_ARX(VIDEO_ARX), .VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(vga_de_raw), .ARX(base_arx), .ARY(base_ary),
	.CROP_SIZE(status[94] ? 12'd216 : 12'd0), .CROP_OFF(status[99:95]),
	.SCALE(status[93:91])
);

///////////////////////   FAST ROM LOAD   //////////////////////////

// The .mra's <rom index="0" address="0x30000000"> has the HPS put the image in DDR3; the copy
// to SDRAM starts out of reset when no byte of index 0 came through the FPGA (the DreamWorld
// core, after srg320/Arcade-PsikyoSH2_MiSTer), once per download.
reg  dl_seen_wr = 1'b0, dl_active_d = 1'b0, ldr_pending = 1'b0, ldr_start = 1'b0, ldr_done = 1'b0;
wire dl_index0 = ioctl_download && ioctl_index == 16'd0;
always @(posedge clk_sys) begin
	ldr_start   <= 1'b0;
	dl_active_d <= dl_index0;
	if (dl_index0 && !dl_active_d)  dl_seen_wr <= 1'b0;
	else if (dl_index0 && ioctl_wr) dl_seen_wr <= 1'b1;
	if (dl_index0 && !dl_active_d) ldr_done <= 1'b0;
	if (reset) ldr_pending <= 1'b1;
	else if (ldr_pending && !ioctl_download && !ldr_active) begin
		ldr_pending <= 1'b0;
		if (!dl_seen_wr && !ldr_done) begin ldr_start <= 1'b1; ldr_done <= 1'b1; end
	end
end

wire        ldr_ddr_req, ldr_ddr_busy, ldr_ddr_valid;
wire [27:0] ldr_ddr_addr;
wire [63:0] ldr_ddr_rdata;
// to YUT_END: yutnori's image is the longest; a shorter one copies DDR3 past its end into
// SDRAM nothing reads
rom_loader #(.LENGTH(28'h03E0000)) u_rom_loader (   // snowbros_sdram_top YUT_END
	.clk(clk_sys), .reset(reset),
	.start(ldr_start), .busy(ldr_active),
	.ddr_req(ldr_ddr_req), .ddr_addr(ldr_ddr_addr), .ddr_busy(ldr_ddr_busy),
	.ddr_valid(ldr_ddr_valid), .ddr_rdata(ldr_ddr_rdata),
	.dl_req(ldr_req), .dl_addr(ldr_addr), .dl_data(ldr_data),
	.dl_we16(ldr_we16), .dl_busy(ldr_busy)
);

wire [7:0]  ldr_DDRAM_BURSTCNT, ldr_DDRAM_BE;
wire [28:0] ldr_DDRAM_ADDR;
wire [63:0] ldr_DDRAM_DIN;
wire        ldr_DDRAM_RD, ldr_DDRAM_WE;
ddram_phy u_ldr_ddram (
	.clk(clk_sys), .reset(reset),
	.DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(ldr_DDRAM_BURSTCNT),
	.DDRAM_ADDR(ldr_DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(ldr_DDRAM_RD),
	.DDRAM_DIN(ldr_DDRAM_DIN), .DDRAM_BE(ldr_DDRAM_BE), .DDRAM_WE(ldr_DDRAM_WE),
	.req(ldr_ddr_req), .we(1'b0), .addr(ldr_ddr_addr), .wdata(8'd0),
	.busy(ldr_ddr_busy), .valid(ldr_ddr_valid), .rdata(ldr_ddr_rdata)
);

///////////////////////   HDMI ROTATION   ////////////////////////////

// Sorgelig's rotator, from the DreamWorld core: a tap on the scaler's input that writes a
// rotated copy into DDR3 and points the HPS framebuffer at it, for HDMI only. Flip stays the
// core's (both outputs). DDRAM_BUSY is held during the ROM copy: the rotator still samples it
// to decide whether a write was taken, and with no reset port a phantom accept leaves a stale
// band in the frame buffer (the DreamWorld core's finding).
wire        rot_DDRAM_CLK, rot_DDRAM_WE, rot_DDRAM_RD;
wire [7:0]  rot_DDRAM_BURSTCNT, rot_DDRAM_BE;
wire [28:0] rot_DDRAM_ADDR;
wire [63:0] rot_DDRAM_DIN;
screen_rotate_two screen_rotate_two
(
	.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE),
	.rotate_ccw(rotate_ccw), .no_rotate(~rotate_en), .flip(1'b0), .two_screen(1'b0),
	.video_rotated(video_rotated),
	.FB_EN(FB_EN), .FB_FORMAT(FB_FORMAT), .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE), .FB_STRIDE(FB_STRIDE), .FB_VBL(FB_VBL), .FB_LL(FB_LL),
	.DDRAM_CLK(rot_DDRAM_CLK), .DDRAM_BUSY(DDRAM_BUSY | ldr_active),
	.DDRAM_BURSTCNT(rot_DDRAM_BURSTCNT), .DDRAM_ADDR(rot_DDRAM_ADDR),
	.DDRAM_DIN(rot_DDRAM_DIN), .DDRAM_BE(rot_DDRAM_BE),
	.DDRAM_WE(rot_DDRAM_WE), .DDRAM_RD(rot_DDRAM_RD)
);

// the loader has DDR3 while it copies (the board in reset, nothing to show)
assign DDRAM_CLK      = ldr_active ? clk_sys            : rot_DDRAM_CLK;
assign DDRAM_BURSTCNT = ldr_active ? ldr_DDRAM_BURSTCNT : rot_DDRAM_BURSTCNT;
assign DDRAM_ADDR     = ldr_active ? ldr_DDRAM_ADDR     : rot_DDRAM_ADDR;
assign DDRAM_DIN      = ldr_active ? ldr_DDRAM_DIN      : rot_DDRAM_DIN;
assign DDRAM_BE       = ldr_active ? ldr_DDRAM_BE       : rot_DDRAM_BE;
assign DDRAM_WE       = ldr_active ? ldr_DDRAM_WE       : rot_DDRAM_WE;
assign DDRAM_RD       = ldr_active ? ldr_DDRAM_RD       : rot_DDRAM_RD;

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = act_cnt[26] ? act_cnt[25:18] > act_cnt[7:0] : act_cnt[25:18] <= act_cnt[7:0];

assign AUDIO_L = audio;
assign AUDIO_R = audio;

endmodule
