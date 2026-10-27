// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// rtl/sound/yutnori_sound.sv against MAME's high-level emulation: the 68000's command bytes
// replayed at MAME's times (sim/yut_tb/cmds.txt, from debug/yutnori-snd/mame.txt), line 0 at
// every frame start (57.5 Hz from 0, as MAME's screen), the ROMs from the set's image. Logged
// to <OUT>: "<ns> S <chip> <ch> <phrase>" for each start written, "<ns> E <chip> <ch>" when a
// channel goes idle (chip 0 the music chip, 1 the voice chip, as MAME's oki1 and oki2), for
// sim/yut_tb/compare.py. ROM bytes answer a few clocks after the request, as a cache hit does.
//
// RUN FROM THE REPOSITORY ROOT:
//     python sim/yut_tb/gen_fixture.py
//     scripts/run_verilator.sh yut_tb +OUT=debug/yutnori-snd/rtl.txt +MS=42000
//     python sim/yut_tb/compare.py
module tb_yut;
	localparam real HALF = 10.41667;   // 48 MHz
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic reset = 1;

	logic [7:0] music [0:524287], voice [0:262143];
	initial begin
		$readmemh("sim/yut_tb/music.hex", music);
		$readmemh("sim/yut_tb/voice.hex", voice);
	end

	logic [4:0] div = 0;
	logic       cen = 0;
	always_ff @(posedge clk) begin
		div <= div == 5'd23 ? 5'd0 : div + 5'd1;
		cen <= div == 5'd0;
	end

	logic        cmd_we = 0, line0 = 0;
	logic [7:0]  cmd = 0;
	logic        m_req, v_req, m_valid = 0, v_valid = 0;
	logic [18:0] m_addr;
	logic [17:0] v_addr;
	logic [7:0]  m_data, v_data;
	logic signed [15:0] audio;

	yutnori_sound dut (
		.clk(clk), .reset(reset), .cen_oki(cen), .cmd_we(cmd_we), .cmd(cmd), .line0(line0),
		.music_req(m_req), .music_addr(m_addr), .music_valid(m_valid), .music_data(m_data),
		.voice_req(v_req), .voice_addr(v_addr), .voice_valid(v_valid), .voice_data(v_data),
		.audio(audio)
	);

	// held req, valid after 6 clk
	int mc = -1, vc = -1;
	always_ff @(posedge clk) begin
		m_valid <= 1'b0; v_valid <= 1'b0;
		if (m_req && !m_valid) begin
			mc <= mc < 0 ? 5 : mc - 1;
			if (mc == 0) begin m_valid <= 1'b1; m_data <= music[m_addr]; mc <= -1; end
		end
		if (v_req && !v_valid) begin
			vc <= vc < 0 ? 5 : vc - 1;
			if (vc == 0) begin v_valid <= 1'b1; v_data <= voice[v_addr]; vc <= -1; end
		end
	end

	int fd;
	string out = "debug/yutnori-snd/rtl.txt";
	// a start's second byte: the phrase is the first byte's, the channel this byte's
	logic [6:0] m_ph, v_ph;
	always_ff @(posedge clk) begin
		if (dut.wr_m && dut.wd[7] && !dut.u_music.u_ctrl.cmd) m_ph <= dut.wd[6:0];
		if (dut.wr_v && dut.wd[7] && !dut.u_voice.u_ctrl.cmd) v_ph <= dut.wd[6:0];
		if (dut.wr_m && dut.u_music.u_ctrl.cmd)
			for (int c = 0; c < 4; c++) if (dut.wd[4 + c]) $fwrite(fd, "%0d S 0 %0d %0d\n", longint'($realtime), c, m_ph);
		if (dut.wr_v && dut.u_voice.u_ctrl.cmd)
			for (int c = 0; c < 4; c++) if (dut.wd[4 + c]) $fwrite(fd, "%0d S 1 %0d %0d\n", longint'($realtime), c, v_ph);
	end
	logic [3:0] m_b = 0, v_b = 0;
	always_ff @(posedge clk) begin
		m_b <= dut.m_dout[3:0]; v_b <= dut.v_dout[3:0];
		for (int c = 0; c < 4; c++) begin
			if (m_b[c] && !dut.m_dout[c]) $fwrite(fd, "%0d E 0 %0d\n", longint'($realtime), c);
			if (v_b[c] && !dut.v_dout[c]) $fwrite(fd, "%0d E 1 %0d\n", longint'($realtime), c);
		end
	end

	// line 0 every 1/57.5 s
	initial begin
		real t;
		t = 1.0e9 / 57.5;
		forever begin
			#(t) @(posedge clk);
			line0 = 1; @(posedge clk); line0 = 0;
		end
	end

	initial begin
		int cf, ms = 3000, n;
		longint t;
		int b;
		void'($value$plusargs("OUT=%s", out));
		void'($value$plusargs("MS=%d", ms));
		fd = $fopen(out, "w");
		if (fd == 0) $fatal(1, "cannot write %s", out);
		cf = $fopen("sim/yut_tb/cmds.txt", "r");
		repeat (4) @(posedge clk);
		reset = 0;
		fork
			begin
				while ($fscanf(cf, "%d %h", t, b) == 2) begin
					if (t > longint'($realtime)) #(t - longint'($realtime));
					@(posedge clk); cmd = 8'(b); cmd_we = 1; @(posedge clk); cmd_we = 0;
				end
			end
			begin
				#(longint'(ms) * 1000000);
			end
		join_any
		$fclose(fd);
		$display("%0d ms simulated", ms);
		$finish;
	end
endmodule
