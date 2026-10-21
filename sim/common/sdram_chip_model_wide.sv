// sdram_chip_model.sv with the full 13-bit row: 16M words, the whole 32 MB, where the shared
// model folds rows to 8 bits and aliases regions more than 128K words apart. mem[] is indexed
// by the controller's word address ({bank, row, col} = word_addr[23:0]), so a bench can load a
// ROM image straight into it (sim/frame_tb). Otherwise identical to sdram_chip_model.sv.
module sdram_chip_model_wide (
	input  logic         clk,

	inout  wire  [15:0] SDRAM_DQ,
	input  logic [12:0] SDRAM_A,
	input  logic  [1:0] SDRAM_BA,
	input  logic         SDRAM_nCS,
	input  logic         SDRAM_nWE,
	input  logic         SDRAM_nRAS,
	input  logic         SDRAM_nCAS
);

	localparam logic [2:0] CMD_NOP          = 3'b111;
	localparam logic [2:0] CMD_ACTIVE       = 3'b011;
	localparam logic [2:0] CMD_READ         = 3'b101;
	localparam logic [2:0] CMD_WRITE        = 3'b100;
	localparam logic [2:0] CMD_PRECHARGE    = 3'b010;
	localparam logic [2:0] CMD_AUTO_REFRESH = 3'b001;
	localparam logic [2:0] CMD_LOAD_MODE    = 3'b000;

	wire [2:0] cmd = {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE};

	// Full real width: {bank[1:0], row[12:0], col[8:0]} = 24 bits = 16.7M
	// words (32MB) -- matches the real MT48LC16M16 chip's actual capacity.
	logic [15:0] mem [0:16777215];

	function automatic int unsigned addr_of(input logic [1:0] bank, input logic [12:0] row, input logic [8:0] col);
		addr_of = {bank, row, col};
	endfunction

	logic [12:0] open_row [0:1];
	logic [12:0] mode_reg;
	wire  [2:0] cas_latency_field  = mode_reg[6:4];
	wire  [2:0] burst_length_field = mode_reg[2:0];
	wire  [4:0] burst_words        = 5'd1 << burst_length_field;   // 0=1,1=2,2=4,3=8

	typedef enum logic [1:0] {R_IDLE, R_WAIT_CAS, R_DRIVE} rstate_t;
	rstate_t rstate = R_IDLE;
	int          rcount;
	logic [8:0] rcol;
	logic [1:0] rbank;
	int          rburst_left;

	logic         driving;
	logic [15:0] drive_word;

	assign SDRAM_DQ = driving ? drive_word : 16'bz;

	always_ff @(posedge clk) begin
		int unsigned widx;

		driving <= 1'b0;

		unique case (cmd)
			CMD_ACTIVE:    open_row[SDRAM_BA] <= SDRAM_A;
			CMD_LOAD_MODE: mode_reg <= SDRAM_A;
			CMD_WRITE: begin
				widx = addr_of(SDRAM_BA, open_row[SDRAM_BA], SDRAM_A[8:0]);
				if (!SDRAM_A[11]) mem[widx][7:0]  <= SDRAM_DQ[7:0];
				if (!SDRAM_A[12]) mem[widx][15:8] <= SDRAM_DQ[15:8];
			end
			CMD_READ: begin
				rstate      <= R_WAIT_CAS;
				rcount      <= int'(cas_latency_field) - 2;
				rcol        <= SDRAM_A[8:0];
				rbank       <= SDRAM_BA;
				rburst_left <= int'(burst_words);
			end
			default: ; // NOP / PRECHARGE / AUTO_REFRESH: nothing to model
		endcase

		unique case (rstate)
			R_IDLE: ; // handled by CMD_READ above
			R_WAIT_CAS: begin
				if (rcount <= 0) begin
					rstate      <= R_DRIVE;
					driving     <= 1'b1;
					widx        = addr_of(rbank, open_row[rbank], rcol);
					drive_word  <= mem[widx];
					rburst_left <= rburst_left - 1;
					rcol        <= rcol + 9'd1;
				end else begin
					rcount <= rcount - 1;
				end
			end
			R_DRIVE: begin
				if (rburst_left > 0) begin
					driving     <= 1'b1;
					widx        = addr_of(rbank, open_row[rbank], rcol);
					drive_word  <= mem[widx];
					rburst_left <= rburst_left - 1;
					rcol        <= rcol + 9'd1;
				end else begin
					rstate <= R_IDLE;
				end
			end
		endcase
	end

	function automatic void poke_word(input logic [1:0] bank, input logic [12:0] row, input logic [8:0] col, input logic [15:0] data);
		mem[addr_of(bank, row, col)] = data;
	endfunction

	function automatic logic [15:0] peek_word(input logic [1:0] bank, input logic [12:0] row, input logic [8:0] col);
		return mem[addr_of(bank, row, col)];
	endfunction

	// Mirrors sdram.sv's own address decomposition exactly, same bit
	// mapping as the original model's word_addr_to_chip helpers
	// (word_addr[i] == addr0[i+1]; addr0's row=addr0[22:10] => here
	// word_addr[21:9]): bank=word_addr[23:22], row=word_addr[21:9] (now the
	// FULL 13 bits, not folded to [16:9]), col=word_addr[8:0].
	function automatic void poke_word_addr(input logic [23:0] word_addr, input logic [15:0] data);
		poke_word(word_addr[23:22], word_addr[21:9], word_addr[8:0], data);
	endfunction

	function automatic logic [15:0] peek_word_addr(input logic [23:0] word_addr);
		return peek_word(word_addr[23:22], word_addr[21:9], word_addr[8:0]);
	endfunction

endmodule
