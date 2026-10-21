// SPDX-License-Identifier: GPL-3.0-or-later
// yutnori's sound: two M6295s at 2 MHz, driven from the 68000's command byte at 0x400001 by
// MAME's high-level stand-in for the undumped PIC (snowbros.cpp yutnori_sound_hle_w,
// yutnori_scanline, yutnori_voice_update; mamedev/mame#16478). No sound CPU.
//
//   0x01-0x22  a voice sample (SAMPLE_REMAP) on the voice chip's first free channel; 29 and 31
//              start a sentence that sample 30 finishes on the same channel once it is free
//   0x80       music off: channel 0 of the music chip stopped
//   0x81-0x82  music on: channel 0 stopped, the music ROM's bank set to 0 or 1
//   line 0     music restarted (phrase 1, channel 0) if it is on and idle, then the sentence
//
// MAME reads the chip's status in the same instant it writes it. jt6295 shows a started channel
// busy only once it has fetched the phrase table through the ROM path, and a second start before
// that overwrites the first, so a start in flight is held here (pend) and counted as busy, and
// one chip takes one start at a time. Mix: both chips at 1.0, x16 to full scale (semicom_sound).

module yutnori_sound (
	input  logic        clk,           // 48 MHz
	input  logic        reset,
	input  logic        cen_oki,       // 2 MHz, 1/24
	input  logic        cmd_we,        // one clk, the 68000's byte write at 0x400001
	input  logic [7:0]  cmd,
	input  logic        line0,         // one clk at the start of line 0 (MAME's scanline 0)

	output logic        music_req,     // held until valid: {bank, chip address}
	output logic [18:0] music_addr,
	input  logic        music_valid,
	input  logic [7:0]  music_data,
	output logic        voice_req,
	output logic [17:0] voice_addr,
	input  logic        voice_valid,
	input  logic [7:0]  voice_data,

	output logic signed [15:0] audio
);
	// SAMPLE_REMAP: commands 0x00-0x1c play sample n; 0x1d-0x22 are special cases
	function automatic logic [5:0] remap(input logic [7:0] c);
		case (c)
			8'h1d:   remap = 6'd32;
			8'h1e:   remap = 6'd30;
			8'h1f:   remap = 6'd34;
			8'h20:   remap = 6'd29;
			8'h21:   remap = 6'd33;
			8'h22:   remap = 6'd0;
			default: remap = c[5:0];
		endcase
	endfunction

	// ---- the two chips ----
	logic        wr_m, wr_v;           // one clk each
	logic [7:0]  wd;
	logic [7:0]  m_dout, v_dout;
	logic [17:0] m_rom_addr, v_rom_addr;
	logic [7:0]  m_rom_data, v_rom_data;
	logic        m_rom_ok, v_rom_ok;
	logic signed [13:0] m_snd, v_snd;
	logic        bank;

	jt6295 #(.INTERPOL(0)) u_music (
		.rst(reset), .clk(clk), .cen(cen_oki), .ss(1'b1),
		.wrn(~wr_m), .din(wd), .dout(m_dout),
		.rom_addr(m_rom_addr), .rom_data(m_rom_data), .rom_ok(m_rom_ok),
		.sound(m_snd), .sample()
	);
	jt6295 #(.INTERPOL(0)) u_voice (
		.rst(reset), .clk(clk), .cen(cen_oki), .ss(1'b1),
		.wrn(~wr_v), .din(wd), .dout(v_dout),
		.rom_addr(v_rom_addr), .rom_data(v_rom_data), .rom_ok(v_rom_ok),
		.sound(v_snd), .sample()
	);
	logic [19:0] m_br_addr, v_br_addr;
	oki_rom_bridge u_music_bridge (
		.clk(clk), .reset(reset),
		.rom_addr(m_rom_addr), .rom_data(m_rom_data), .rom_ok(m_rom_ok), .bank({1'b0, bank}),
		.req(music_req), .addr(m_br_addr), .valid(music_valid), .data(music_data)
	);
	oki_rom_bridge u_voice_bridge (
		.clk(clk), .reset(reset),
		.rom_addr(v_rom_addr), .rom_data(v_rom_data), .rom_ok(v_rom_ok), .bank(2'd0),
		.req(voice_req), .addr(v_br_addr), .valid(voice_valid), .data(voice_data)
	);
	assign music_addr = m_br_addr[18:0];
	assign voice_addr = v_br_addr[17:0];

	// a start in flight: set by its second byte, cleared once the chip shows the channel
	logic [3:0] m_pend, v_pend;
	wire  [3:0] m_busy = m_dout[3:0] | m_pend;
	wire  [3:0] v_busy = v_dout[3:0] | v_pend;

	// ---- the sequencer ----
	typedef enum logic [3:0] {
		S_IDLE, S_CMD, S_LOOP, S_VU, S_VSTART, S_MSTOP,
		S_W1, S_GAP, S_W2, S_WAITPEND
	} st_t;
	st_t        st, ret;               // ret: where S_W* go when the write is done
	logic       cmd_p, line_p;         // pending
	logic [7:0] cmd_q;
	logic       music_on;
	logic [5:0] v_next;                // the sentence's second half, 0 if none
	logic [1:0] v_ch;
	logic       w_music;               // the start being written is the music chip's
	logic [7:0] w_b1, w_b2;
	logic [1:0] w_ch;
	logic       w_two;                 // a start (two bytes), else one byte
	logic [5:0] samp;
	logic [2:0] gap;

	function automatic logic [2:0] first_free(input logic [3:0] busy);
		first_free = !busy[0] ? 3'd0 : !busy[1] ? 3'd1 : !busy[2] ? 3'd2 : !busy[3] ? 3'd3 : 3'd4;
	endfunction
	wire [2:0] v_free = first_free(v_busy);

	// a start the chip never shows busy (an empty phrase) is let go: the table fetch takes a few
	// thousand clk at most
	logic [14:0] m_age, v_age;

	always_ff @(posedge clk) begin
		wr_m <= 1'b0; wr_v <= 1'b0;
		if (cmd_we && cmd != 8'h00) begin cmd_p <= 1'b1; cmd_q <= cmd; end
		if (line0) line_p <= 1'b1;
		for (int i = 0; i < 4; i++) begin
			if (m_dout[i]) m_pend[i] <= 1'b0;
			if (v_dout[i]) v_pend[i] <= 1'b0;
		end
		m_age <= (m_pend == 4'd0) ? 15'd0 : m_age + 15'd1;
		v_age <= (v_pend == 4'd0) ? 15'd0 : v_age + 15'd1;
		if (&m_age) m_pend <= 4'd0;
		if (&v_age) v_pend <= 4'd0;

		if (reset) begin
			st <= S_IDLE; cmd_p <= 1'b0; line_p <= 1'b0; music_on <= 1'b0; v_next <= 6'd0;
			bank <= 1'b0; m_pend <= 4'd0; v_pend <= 4'd0; samp <= 6'd0;
		end else case (st)
			S_IDLE:
				if (line_p) begin line_p <= 1'b0; st <= S_LOOP; end
				else if (cmd_p) begin cmd_p <= 1'b0; st <= S_CMD; end

			// line 0: the music loop, then the sentence
			S_LOOP:
				if (music_on && !m_busy[0]) begin
					w_music <= 1'b1; w_two <= 1'b1; w_b1 <= 8'h81; w_b2 <= 8'h10; w_ch <= 2'd0;
					st <= S_WAITPEND; ret <= S_VU;
				end else st <= S_VU;

			// yutnori_voice_update; from S_CMD it continues to the sample's start
			S_VU: begin
				if (v_next != 6'd0 && !v_busy[v_ch]) begin
					w_music <= 1'b0; w_two <= 1'b1; w_b1 <= {2'b10, v_next}; w_ch <= v_ch;
					w_b2 <= 8'h10 << v_ch; v_next <= 6'd0;
					st <= S_WAITPEND; ret <= (samp != 6'd0) ? S_VSTART : S_IDLE;
				end else st <= (samp != 6'd0) ? S_VSTART : S_IDLE;
			end

			S_CMD: begin
				samp <= 6'd0;
				if (cmd_q >= 8'h01 && cmd_q <= 8'h22) begin
					samp <= remap(cmd_q);
					st   <= (remap(cmd_q) != 6'd0) ? S_VU : S_IDLE;
				end else if (cmd_q == 8'h80) begin
					music_on <= 1'b0; st <= S_MSTOP;
				end else if (cmd_q == 8'h81 || cmd_q == 8'h82) begin
					music_on <= 1'b1; bank <= cmd_q[1]; st <= S_MSTOP;
				end else st <= S_IDLE;
			end

			S_MSTOP: begin
				w_music <= 1'b1; w_two <= 1'b0; w_b1 <= 8'h08;
				st <= S_W1; ret <= S_IDLE;
			end

			S_VSTART: begin
				if (v_free != 3'd4) begin
					w_music <= 1'b0; w_two <= 1'b1; w_b1 <= {2'b10, samp};
					w_ch <= v_free[1:0]; w_b2 <= 8'h10 << v_free[1:0];
					if (samp == 6'd29 || samp == 6'd31) begin
						v_next <= 6'd30; v_ch <= v_free[1:0];
					end
					st <= S_WAITPEND; ret <= S_IDLE;
				end else st <= S_IDLE;
				samp <= 6'd0;
			end

			// one start per chip at a time
			S_WAITPEND:
				if (w_music ? m_pend == 4'd0 : v_pend == 4'd0) st <= S_W1;

			S_W1: begin
				wd <= w_b1;
				if (w_music) wr_m <= 1'b1; else wr_v <= 1'b1;
				gap <= 3'd0;
				st  <= w_two ? S_GAP : ret;
			end
			S_GAP: begin
				gap <= gap + 3'd1;
				if (gap == 3'd3) st <= S_W2;
			end
			S_W2: begin
				wd <= w_b2;
				if (w_music) begin wr_m <= 1'b1; m_pend[w_ch] <= 1'b1; end
				else         begin wr_v <= 1'b1; v_pend[w_ch] <= 1'b1; end
				st <= ret;
			end
			default: st <= S_IDLE;
		endcase
	end

	// ---- mix ----
	logic signed [20:0] mix;
	always_ff @(posedge clk) begin
		mix   <= (21'(m_snd) <<< 4) + (21'(v_snd) <<< 4);
		audio <= mix > 21'sd32767 ? 16'sd32767 : mix < -21'sd32768 ? 16'sh8000 : mix[15:0];
	end
endmodule
