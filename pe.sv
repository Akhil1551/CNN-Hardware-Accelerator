module pe #(
  parameter int DATA_W = 16,
  parameter int ACC_W  = 36
) (
  input  logic                     clk,
  input  logic                     rst_n,

  input  logic signed [DATA_W-1:0] pix_in,
  input  logic signed [DATA_W-1:0] k_in,
  output logic signed [DATA_W-1:0] k_out,

  input  logic                     clr_in,
  output logic                     clr_out,
  input  logic                     en_in,
  output logic                     en_out,

  output logic signed [ACC_W-1:0]  acc_out
);

  logic signed [(2*DATA_W)-1:0] prod;
  assign prod = pix_in * k_in;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_out <= '0;
      k_out   <= '0;
      clr_out <= 1'b0;
      en_out  <= 1'b0;
    end else begin
      // Systolic propagation of weight and control signals
      k_out   <= k_in;
      clr_out <= clr_in;
      en_out  <= en_in;

      if (en_in) begin
        if (clr_in)
          acc_out <= ACC_W'(signed'(prod)); // Start new window with 1st product
        else
          acc_out <= acc_out + ACC_W'(signed'(prod));
      end
    end
  end

endmodule
