// CRT Adjust: native raster -> crt_vsize (V-Size) -> crt_adjust (H-Position,
// V-Shift, H-Size) -> arcade_video. Passthrough while `active` is low.
module crt_chain #(
	parameter int HTOTAL   = 456,
	parameter int VTOTAL   = 262,
	parameter int ACTIVE_W = 320,
	parameter int RD_BASE  = 48,          // clk per pixel, in quarter cycles
	parameter int PVM_FREE_LINES = 5      // lines after the picture PVM mode can drop
) (
	input  logic              clk,
	input  logic              ce_pix,

	input  logic              active,
	input  logic              scale_en,
	input  logic signed [8:0] hoffset,
	input  logic signed [5:0] voffset,
	input  logic signed [4:0] hsize,
	input  logic signed [3:0] vsize_step,
	input  logic              vsize_cabinet,

	input  logic [7:0]        r_in, g_in, b_in,
	input  logic              hs_in, vs_in, hb_in, vb_in,

	output logic              ce_out,
	output logic [7:0]        r_out, g_out, b_out,
	output logic              hs_out, vs_out, hb_out, vb_out
);

	wire scaling = active & scale_en;

	// 3 lines per step; crt_vsize's +N means shorter, so negate.
	logic signed [5:0] vsize = 6'sd0;
	logic              cabinet = 1'b0;
	always_ff @(posedge clk) if (ce_pix) begin
		vsize   <= scaling ? -(6'sd3 * $signed({{2{vsize_step[3]}}, vsize_step})) : 6'sd0;
		cabinet <= vsize_cabinet;
	end

	// PVM mode drops lines from the end of the frame, but Psikyo's blanking is
	// mostly before the picture, so taller settings would cut its bottom.
	// Delaying the VSync crt_vsize sees moves the dropped lines into the back
	// porch; the picture moves up as it grows.
	localparam logic signed [6:0] PVM_MARGIN  = 7'(PVM_FREE_LINES - 1);
	localparam int                PVM_DLY_MAX = 21 - (PVM_FREE_LINES - 1);

	logic                   hs_nat_d = 1'b0;
	logic [PVM_DLY_MAX-1:0] vs_lines = '0;
	always_ff @(posedge clk) if (ce_pix) begin
		hs_nat_d <= hs_in;
		if (hs_in & ~hs_nat_d) vs_lines <= {vs_lines[PVM_DLY_MAX-2:0], vs_in};
	end

	wire signed [6:0] pvm_need = -$signed({vsize[5], vsize}) - PVM_MARGIN;
	wire        [4:0] pvm_dly  = (!cabinet && pvm_need > 0) ? pvm_need[4:0] : 5'd0;
	wire              vs_pre   = (pvm_dly == 0) ? vs_in : vs_lines[pvm_dly - 1'd1];

	logic [7:0] vz_r, vz_g, vz_b;
	logic       vz_hs, vz_vs, vz_de, vz_vb, vz_ce;

	crt_vsize #(
		.RING_LINES(46),
		.LINE_PX   (ACTIVE_W)
	) u_crt_vsize (
		.clk      (clk),
		.pxl_cen  (ce_pix),
		.active   (scaling),
		.tube_mode(cabinet),
		.vsize    (vsize),
		.r_in(r_in), .g_in(g_in), .b_in(b_in),
		.hs_in(hs_in), .vs_in(vs_pre),
		.de_in(~(hb_in | vb_in)),
		.vb_in(vb_in),
		.r_out(vz_r), .g_out(vz_g), .b_out(vz_b),
		.hs_out(vz_hs), .vs_out(vz_vs), .de_out(vz_de), .vb_out(vz_vb),
		.ce_out(vz_ce)
	);

	// H-Size read rate; must restart on hs_ref_out, not the raw HSync.
	wire signed [4:0] hsize_eff = scaling ? hsize : 5'sd0;
	wire        [7:0] rd_period = 8'(RD_BASE) + {{3{hsize_eff[4]}}, hsize_eff};

	logic       hs_ref;
	logic       hs_ref_d = 1'b0;
	logic [7:0] rd_acc = 8'd0;
	wire        rd_tick = (rd_acc + 8'd4) >= rd_period;
	always_ff @(posedge clk) begin
		hs_ref_d <= hs_ref;
		if      (hs_ref & ~hs_ref_d) rd_acc <= 8'd0;
		else if (rd_tick)            rd_acc <= rd_acc + 8'd4 - rd_period;
		else                         rd_acc <= rd_acc + 8'd4;
	end

	assign ce_out = active ? rd_tick : vz_ce;

	logic adj_hb, adj_vb;

	crt_adjust #(
		.VTOTAL   (VTOTAL),
		.HTOTAL   (HTOTAL),
		.HPOS_MODE(1)
	) u_crt_adjust (
		.clk      (clk),
		.pxl_cen  (vz_ce),
		.pxl2_cen (rd_tick),
		.active   (active),
		.hsize    (hsize_eff),
		.hoffset  (active ? hoffset : 9'sd0),
		.voffset  (active ? voffset : 6'sd0),
		.r_in(vz_r), .g_in(vz_g), .b_in(vz_b),
		.hs_in(vz_hs), .vs_in(vz_vs), .hb_in(~vz_de), .vb_in(vz_vb),
		.r_out(r_out), .g_out(g_out), .b_out(b_out),
		.hs_out(hs_out), .vs_out(vs_out), .hb_out(adj_hb), .vb_out(adj_vb),
		.hs_ref_out(hs_ref)
	);

	// crt_adjust's vb_out leads its picture by a line, which drops the last
	// line; latching it at HSync keeps it. Blanking the HSync pulse removes a
	// one-pixel DE stub when a stretched line overruns into the next.
	logic hs_out_d = 1'b0, vb_line = 1'b1;
	always_ff @(posedge clk) if (ce_out) begin
		hs_out_d <= hs_out;
		if (hs_out & ~hs_out_d) vb_line <= adj_vb;
	end

	assign vb_out = active ? vb_line : adj_vb;
	assign hb_out = active ? (adj_hb | hs_out) : adj_hb;

endmodule
