`timescale 1ns / 1ps

module systolic_array #(
    parameter int DATA_W  = 16,
    parameter int ACC_W   = 36,
    parameter int NUM_WIN = 9
)(
    input  logic                                  clk,
    input  logic                                  rst_n,

    // From img_buffer (9 parallel pixel streams)
    input  logic signed [NUM_WIN-1:0][DATA_W-1:0] pix_in,

    // From Control Block / Kernel Streamer (1 weight per cycle into PE 0)
    input  logic signed [DATA_W-1:0]              k_in,
    input  logic                                  k_first,    // High on 1st weight (W[0]) of a window

    // From im2col_addr_gen
    input  logic                                  valid_in_0, // Connect to valid[0] of im2col_addr_gen
    input  logic [NUM_WIN-1:0]                    done_in,    // Connect to done[8:0] of im2col_addr_gen

    // Serialized Convolution Output (1 completed window sum per cycle)
    output logic signed [ACC_W-1:0]               acc_out,
    output logic                                  acc_valid
);

    // Systolic interconnect chains across the 9 PEs
    logic signed [DATA_W-1:0]              k_chain   [NUM_WIN+1];
    logic                                  clr_chain [NUM_WIN+1];
    logic                                  en_chain  [NUM_WIN+1];
    logic signed [NUM_WIN-1:0][ACC_W-1:0]  pe_acc;

    // Feed PE[0] directly; PEs 1..8 get their inputs systolically from previous PE
    assign k_chain[0]   = k_in;
    assign clr_chain[0] = k_first;
    assign en_chain[0]  = valid_in_0;

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

    // -------------------------------------------------------------------------
    // Output Readout Logic Driven by im2col done_in[8:0]
    // -------------------------------------------------------------------------
    // done_in[i] is high during the 9th tap (while PE[i] is multiplying the 9th pair).
    // The final accumulated sum is registered in pe_acc[i] on the next posedge clk.
    // Delaying done_in by 1 clock cycle aligns pe_done_d[i] with the finished pe_acc[i].
    logic [NUM_WIN-1:0] pe_done_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pe_done_d <= '0;
        end else begin
            pe_done_d <= done_in;
        end
    end

    // One-hot multiplexer selects whichever PE just completed its 9th tap
    always_comb begin
        acc_out   = '0;
        acc_valid = |pe_done_d; // High whenever any PE finishes its window

        for (int idx = 0; idx < NUM_WIN; idx++) begin
            if (pe_done_d[idx]) begin
                acc_out = pe_acc[idx];
            end
        end
    end

endmodule
