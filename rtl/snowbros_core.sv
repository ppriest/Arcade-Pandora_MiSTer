// SPDX-License-Identifier: GPL-3.0-or-later
// The board: 68000 (maincpu), work RAM, the Pandora video, the Toaplan sound board, the SemiCom
// protection (the MCU, or MAME's protdata image copied at reset), from snowbros.cpp.
//
// Work RAM is 32K x 16 in two byte arrays, each with two ports: A is the 68000's, B the
// protection's writes (the MCU's port writes, or the reset-time protdata copy). The 68000 is
// held while the copy runs, as MAME does it in machine_reset (1915-1929).
//
// Flip: the Pandora's flip is the game's register (Toaplan map, `!BIT(data, 7)`, 89-93)
// XOR the OSD's / fake DIP's flip. MAME's flip, 240 - pos with the tile flipped, is exactly the
// unflipped picture turned 180 degrees in the visible window.

module snowbros_core (
	input  logic        clk,           // 48 MHz
	input  logic        reset,
	input  logic        pause,

	// configuration (the .mra mod bytes, Pandora.sv)
	input  logic        semicom, wram64, cpu12,
	input  logic        has_mcu, mcu_base_f000,
	input  logic        has_protdata, prot_at_2000,
	input  logic        const_en, const_at_500006,
	input  logic [15:0] const_val,
	input  logic [7:0]  bg_pen,
	input  logic [14:0] ntiles,
	input  logic        flip_osd,
	input  logic        finalttr,      // the sound board at 3.579545 MHz (finalttr, 2134-2152)
	input  logic        yutnori,       // yutnori_map and its PIC-driven M6295s, no sound CPU

	input  logic [15:0] in_dsw1, in_dsw2, in_system,

	output logic        cpu_rom_req,
	output logic [18:0] cpu_rom_addr,
	input  logic        cpu_rom_valid,
	input  logic [15:0] cpu_rom_data,
	output logic        z80_rom_req,
	output logic [15:0] z80_rom_addr,
	input  logic        z80_rom_valid,
	input  logic [7:0]  z80_rom_data,
	output logic        oki_rom_req,
	output logic [17:0] oki_rom_addr,
	input  logic        oki_rom_valid,
	input  logic [7:0]  oki_rom_data,
	// yutnori's music chip, {bank, address}; the SDRAM serves it on the Z80's port
	output logic        okim_rom_req,
	output logic [18:0] okim_rom_addr,
	input  logic        okim_rom_valid,
	input  logic [7:0]  okim_rom_data,
	output logic        g_req,
	output logic [17:0] g_addr,
	input  logic        g_valid,
	input  logic [63:0] g_data,

	input  logic        mcu_rom_we,
	input  logic [11:0] mcu_rom_waddr,
	input  logic [15:0] mcu_rom_wdata,
	input  logic [1:0]  mcu_rom_wbe,
	input  logic        prot_we,
	input  logic [7:0]  prot_waddr,
	input  logic [15:0] prot_wdata,
	input  logic [1:0]  prot_wbe,

	output logic        ce_pix,
	output logic [7:0]  r, g, b,
	output logic        hblank, vblank, hsync, vsync,
	output logic signed [15:0] audio,
	output logic [15:0] overruns
);
	// ---- protdata copy at reset ----
	logic [7:0]  prot_lo [0:255], prot_hi [0:255];
	logic [7:0]  pc_addr;
	logic [15:0] pc_q;
	always_ff @(posedge clk) begin
		if (prot_we && prot_wbe[0]) prot_lo[prot_waddr] <= prot_wdata[7:0];
		if (prot_we && prot_wbe[1]) prot_hi[prot_waddr] <= prot_wdata[15:8];
		pc_q <= {prot_hi[pc_addr], prot_lo[pc_addr]};
	end
	logic       copying, cp_we;
	logic [8:0] cp_n;
	logic [7:0] cp_wa;
	always_ff @(posedge clk) begin
		cp_we <= 1'b0;
		if (reset) begin
			copying <= has_protdata; cp_n <= 9'd0; pc_addr <= 8'd0;
		end else if (copying) begin
			// word n's address is on pc_addr in the clk cp_n is n; its data is on pc_q the clk
			// after, the same clk as this write of n
			pc_addr <= cp_n[7:0] + 8'd1;
			cp_n    <= cp_n + 9'd1;
			cp_we   <= 1'b1;
			cp_wa   <= cp_n[7:0];
			if (cp_n == 9'd255) copying <= 1'b0;
		end
	end
	wire cpu_reset = reset || copying;

	// ---- work RAM ----
	logic [14:0] wa_addr, wb_addr;
	logic        wa_wel, wa_weh, wb_wel, wb_weh;
	logic [15:0] wa_wdata, wa_rdata, wb_wdata;
	// no_rw_check: port B (the protection) and port A (the 68000) are never ordered against
	// each other in MAME either; without it Quartus will not infer the mixed-port memory
	(* ramstyle = "no_rw_check" *) logic [7:0] wram_lo [0:32767];
	(* ramstyle = "no_rw_check" *) logic [7:0] wram_hi [0:32767];
	always_ff @(posedge clk) begin
		if (wa_wel) wram_lo[wa_addr] <= wa_wdata[7:0];
		wa_rdata[7:0] <= wram_lo[wa_addr];
	end
	always_ff @(posedge clk) if (wb_wel) wram_lo[wb_addr] <= wb_wdata[7:0];
	always_ff @(posedge clk) begin
		if (wa_weh) wram_hi[wa_addr] <= wa_wdata[15:8];
		wa_rdata[15:8] <= wram_hi[wa_addr];
	end
	always_ff @(posedge clk) if (wb_weh) wram_hi[wb_addr] <= wb_wdata[15:8];

	logic        mcu_wel, mcu_weh;
	logic [14:0] mcu_waddr;
	logic [15:0] mcu_wdata;
	// the image is in the 68000's byte order: even byte first
	always_comb begin
		if (cp_we) begin
			wb_wel = 1'b1; wb_weh = 1'b1;
			wb_addr  = (prot_at_2000 ? 15'h1000 : 15'h7800) + {7'd0, cp_wa};
			wb_wdata = {pc_q[7:0], pc_q[15:8]};
		end else begin
			wb_wel = mcu_wel && has_mcu; wb_weh = mcu_weh && has_mcu;
			wb_addr = mcu_waddr; wb_wdata = mcu_wdata;
		end
	end

	snowbros_mcu u_mcu (
		.clk(clk), .reset(reset || !has_mcu), .base_f000(mcu_base_f000),
		.rom_we(mcu_rom_we), .rom_waddr(mcu_rom_waddr), .rom_wdata(mcu_rom_wdata), .rom_wbe(mcu_rom_wbe),
		.wram_wel(mcu_wel), .wram_weh(mcu_weh), .wram_addr(mcu_waddr), .wram_wdata(mcu_wdata)
	);

	// ---- 68000 ----
	logic [7:0]  pal_addr;
	logic        pal_wel, pal_weh, spr_we, snd_we, flip_we, flip_wdata;
	logic [15:0] pal_wdata, pal_rdata;
	logic [11:0] spr_addr;
	logic [7:0]  spr_wdata, spr_rdata, snd_wdata, snd_reply;
	logic        irq4, irq3, irq2;

	maincpu u_cpu (
		.clk(clk), .reset(cpu_reset),
		.semicom(semicom), .wram64(wram64), .cpu12(cpu12), .yutnori(yutnori),
		.const_en(const_en), .const_at_500006(const_at_500006), .const_val(const_val),
		.rom_req(cpu_rom_req), .rom_addr(cpu_rom_addr), .rom_valid(cpu_rom_valid), .rom_data(cpu_rom_data),
		.wram_addr(wa_addr), .wram_wel(wa_wel), .wram_weh(wa_weh),
		.wram_wdata(wa_wdata), .wram_rdata(wa_rdata),
		.pal_addr(pal_addr), .pal_wel(pal_wel), .pal_weh(pal_weh),
		.pal_wdata(pal_wdata), .pal_rdata(pal_rdata),
		.spr_addr(spr_addr), .spr_we(spr_we), .spr_wdata(spr_wdata), .spr_rdata(spr_rdata),
		.in_dsw1(in_dsw1), .in_dsw2(in_dsw2), .in_system(in_system),
		.snd_we(snd_we), .snd_wdata(snd_wdata), .snd_rdata(snd_reply),
		.flip_we(flip_we), .flip_wdata(flip_wdata),
		.irq4_line(irq4), .irq3_line(irq3), .irq2_line(irq2),
		.pause(pause),
		.ss_req(1'b0), .ss_go(1'b0), .ss_held(), .ss_done(),
		.ss_bidx(5'd0), .ss_bwe(1'b0), .ss_bd(32'd0), .ss_bq(),
		.ss_irq_we(1'b0), .ss_irq_d(3'd0), .ss_irq_q()
	);

	// the register's reset value: the Pandora is unflipped (kan_pand.cpp device_start)
	logic flip_reg;
	always_ff @(posedge clk) begin
		if (reset) flip_reg <= 1'b0;
		else if (flip_we) flip_reg <= !flip_wdata;
	end

	// ---- video ----
	logic [8:0] ox, oy, vcnt;
	snowbros_video u_video (
		.clk(clk), .reset(reset),
		.spr_addr(spr_addr), .spr_we(spr_we), .spr_wdata(spr_wdata), .spr_rdata(spr_rdata),
		.pal_addr(pal_addr), .pal_wel(pal_wel), .pal_weh(pal_weh), .pal_wdata(pal_wdata), .pal_rdata(pal_rdata),
		.flip((flip_reg && !semicom && !yutnori) ^ flip_osd), .bg_pen(bg_pen), .ntiles(ntiles),
		.g_req(g_req), .g_addr(g_addr), .g_valid(g_valid), .g_data(g_data),
		.ce_pix(ce_pix), .r(r), .g(g), .b(b),
		.hblank_o(hblank), .vblank_o(vblank), .hsync_o(hsync), .vsync_o(vsync),
		.out_x(ox), .out_y(oy),
		.irq4(irq4), .irq3(irq3), .irq2(irq2), .overruns(overruns),
		.ss_we(1'b0), .ss_line(9'd0), .ss_hcnt(9'd0), .ss_div(4'd0), .vcnt(vcnt), .hclk()
	);

	// ---- sound: the Toaplan board, the SemiCom board, or yutnori's ----
	// enables from one 48-clk cycle: Toaplan Z80 1/8, YM3812 1/16; SemiCom Z80 and YM2151 1/12
	// (the YM's at a quarter-cycle offset), the YM's half-rate enable, M6295 1/48
	logic [5:0] sdiv;
	logic       t_z80, t_ym, s_z80, s_ym, s_ymp1, s_oki;
	always_ff @(posedge clk) begin
		sdiv   <= (reset || sdiv == 6'd47) ? 6'd0 : sdiv + 6'd1;
		t_z80  <= !pause && sdiv[2:0] == 3'd0;
		t_ym   <= !pause && sdiv[3:0] == 4'd0;
		s_z80  <= !pause && (sdiv == 6'd0 || sdiv == 6'd12 || sdiv == 6'd24 || sdiv == 6'd36);
		s_ym   <= !pause && (sdiv == 6'd6 || sdiv == 6'd18 || sdiv == 6'd30 || sdiv == 6'd42);
		s_ymp1 <= !pause && (sdiv == 6'd6 || sdiv == 6'd30);
		s_oki  <= !pause && sdiv == 6'd0;
	end
	// finalttr: Z80 and YM2151 at 3.579545 MHz, a 32-bit phase step of 3579545 / 48 MHz * 2^32;
	// its M6295 (999900 Hz) stays on the 1 MHz enable (docs/HACKS.md)
	logic [31:0] ft_acc;
	logic        ft_cen, ft_half;
	always_ff @(posedge clk) begin
		{ft_cen, ft_acc} <= reset ? 33'd0 : {1'b0, ft_acc} + 33'h0_1317_45A9;
		if (ft_cen) ft_half <= ~ft_half;
	end
	wire sz80   = finalttr ? !pause && ft_cen : s_z80;
	wire sym    = finalttr ? !pause && ft_cen : s_ym;
	wire symp1  = finalttr ? !pause && ft_cen && ft_half : s_ymp1;
	logic signed [15:0] ta_audio, se_audio;
	logic        s_oki_req;
	logic [17:0] s_oki_addr;
	logic        t_rom_req, s_rom_req;
	logic [14:0] t_rom_addr;
	logic [15:0] s_rom_addr;
	toaplan_sound u_sound (
		.clk(clk), .reset(reset || semicom || yutnori), .cen_z80(t_z80), .cen_ym(t_ym),
		.latch_data(snd_wdata), .latch_write(snd_we && !semicom && !yutnori), .reply(snd_reply),
		.rom_req(t_rom_req), .rom_addr(t_rom_addr), .rom_valid(z80_rom_valid && !semicom), .rom_data(z80_rom_data),
		.audio(ta_audio)
	);
	semicom_sound u_semi_sound (
		.clk(clk), .reset(reset || !semicom || yutnori), .cen_z80(sz80), .cen_ym(sym), .cen_ym_p1(symp1),
		.cen_oki(s_oki), .finalttr(finalttr),
		.latch_data(snd_wdata), .latch_write(snd_we && semicom),
		.rom_req(s_rom_req), .rom_addr(s_rom_addr), .rom_valid(z80_rom_valid && semicom), .rom_data(z80_rom_data),
		.oki_req(s_oki_req), .oki_addr(s_oki_addr), .oki_valid(oki_rom_valid && !yutnori), .oki_data(oki_rom_data),
		.audio(se_audio)
	);

	// yutnori: M6295s at 2 MHz (16 MHz / 8, mamedev/mame#16478), the command byte at 0x400001,
	// MAME's scanline 0 the start of line 0 here
	logic       y_oki, line0, vcnt0_d;
	logic [4:0] ydiv;
	always_ff @(posedge clk) begin
		ydiv    <= (reset || ydiv == 5'd23) ? 5'd0 : ydiv + 5'd1;
		y_oki   <= !pause && ydiv == 5'd0;
		vcnt0_d <= vcnt == 9'd0;
		line0   <= vcnt == 9'd0 && !vcnt0_d;
	end
	logic signed [15:0] yu_audio;
	logic        y_voice_req;
	logic [17:0] y_voice_addr;
	yutnori_sound u_yut_sound (
		.clk(clk), .reset(reset || !yutnori), .cen_oki(y_oki),
		.cmd_we(snd_we && yutnori), .cmd(snd_wdata), .line0(line0),
		.music_req(okim_rom_req), .music_addr(okim_rom_addr), .music_valid(okim_rom_valid), .music_data(okim_rom_data),
		.voice_req(y_voice_req), .voice_addr(y_voice_addr), .voice_valid(oki_rom_valid && yutnori), .voice_data(oki_rom_data),
		.audio(yu_audio)
	);
	assign oki_rom_req  = yutnori ? y_voice_req : s_oki_req;
	assign oki_rom_addr = yutnori ? y_voice_addr : s_oki_addr;
	assign z80_rom_req  = semicom ? s_rom_req : t_rom_req;
	assign z80_rom_addr = semicom ? s_rom_addr : {1'b0, t_rom_addr};
	assign audio = yutnori ? yu_audio : semicom ? se_audio : ta_audio;
endmodule
