module systolic_array #(
  parameter int DATA_W  = 16,
  parameter int ACC_W   = 36,
  parameter int NUM_WIN = 9
) (
  input  logic                                   clk,
  input  logic                                   rst_n,

  input  logic signed [NUM_WIN-1:0][DATA_W-1:0]  pix_in,
  input  logic signed [DATA_W-1:0]               k_in,
  input  logic                                   k_first, // High on the 1st weight of each window

  input  logic                                   running,
  output logic signed [ACC_W-1:0]                acc_out,
  output logic                                   acc_valid
);

  localparam int SEL_W = (NUM_WIN > 1) ? $clog2(NUM_WIN) : 1;

  logic signed [DATA_W-1:0]             k_chain   [NUM_WIN+1];
  logic                                 clr_chain [NUM_WIN+1];
  logic                                 en_chain  [NUM_WIN+1];
  logic signed [NUM_WIN-1:0][ACC_W-1:0] pe_acc;

  assign k_chain[0]   = k_in;
  assign clr_chain[0] = k_first;
  assign en_chain[0]  = running;

  genvar i;
  generate
    for (i = 0; i < NUM_WIN; i++) begin : g_pe
      pe #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W)
      ) u_pe (
        .clk     (clk),
        .rst_n   (rst_n),
        .pix_in  (pix_in[i]),
        .k_in    (k_chain[i]),
        .k_out   (k_chain[i+1]),
        .clr_in  (clr_chain[i]),
        .clr_out (clr_chain[i+1]),
        .en_in   (en_chain[i]),
        .en_out  (en_chain[i+1]),
        .acc_out (pe_acc[i])
      );
    end
  endgenerate

  // Track when PE[0] finishes its first full window of NUM_WIN cycles
  logic [SEL_W-1:0] warmup_cnt;
  logic             array_primed;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      warmup_cnt   <= '0;
      array_primed <= 1'b0;
    end else if (!running) begin
      warmup_cnt   <= '0;
      array_primed <= 1'b0;
    end else if (!array_primed) begin
      if (warmup_cnt == SEL_W'(NUM_WIN-1))
        array_primed <= 1'b1;
      else
        warmup_cnt <= warmup_cnt + 1'b1;
    end
  end

  // Readout selector starts stepping only after PE[0] has accumulated NUM_WIN elements
  logic [SEL_W-1:0] sel;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || !running || !array_primed) begin
      sel <= '0;
    end else if (sel == SEL_W'(NUM_WIN-1)) begin
      sel <= '0;
    end else begin
      sel <= sel + 1'b1;
    end
  end

  assign acc_out   = pe_acc[sel];
  assign acc_valid = running && array_primed;

endmodule
