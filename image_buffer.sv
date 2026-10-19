`timescale 1ns / 1ps

module img_buffer #(
    parameter int IMG_H      = 5,
    parameter int IMG_W      = 5,
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 8,
    parameter int NUM_GENS   = 9
)(
    input  logic                                clk,
    input  logic                                rst_n,

    // Synchronous Single-Pixel Write Port (can be left idle if pre-loaded in sim)
    input  logic                                wr_en,
    input  logic [ADDR_WIDTH-1:0]               wr_row,
    input  logic [ADDR_WIDTH-1:0]               wr_col,
    input  logic [DATA_WIDTH-1:0]               wr_data,

    // 9 Parallel Read Address Ports (from im2col_addr_gen)
    input  logic [NUM_GENS-1:0][ADDR_WIDTH-1:0] row_addr,
    input  logic [NUM_GENS-1:0][ADDR_WIDTH-1:0] col_addr,
    input  logic [NUM_GENS-1:0]                 valid,

    // 9 Parallel Combinational Pixel Outputs (to Systolic Array)
    output logic [NUM_GENS-1:0][DATA_WIDTH-1:0] pixel_out
);

    // 2D Register Matrix for the Input Image (IMG_H x IMG_W)
    logic [DATA_WIDTH-1:0] mem [0:IMG_H-1][0:IMG_W-1];

    // -------------------------------------------------------------------------
    // Pre-load 5x5 Matrix for Simulation (Values 1 to 25)
    // -------------------------------------------------------------------------
    initial begin
        for (int r = 0; r < IMG_H; r++) begin
            for (int c = 0; c < IMG_W; c++) begin
                mem[r][c] = DATA_WIDTH'(r * IMG_W + c + 1); // Pattern A: 1 to 25
                // mem[r][c] = DATA_WIDTH'(r * 10 + c);     // Pattern B: Row*10 + Col
            end
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous Write Port (for Hardware Loading)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (wr_row < IMG_H && wr_col < IMG_W) begin
                mem[wr_row][wr_col] <= wr_data;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Combinational 9-Port Read Logic
    // -------------------------------------------------------------------------
    always_comb begin
        for (int i = 0; i < NUM_GENS; i++) begin
            if (valid[i] && (row_addr[i] < IMG_H) && (col_addr[i] < IMG_W)) begin
                pixel_out[i] = mem[row_addr[i]][col_addr[i]];
            end else begin
                pixel_out[i] = '0; // Output 0 when generator is idle
            end
        end
    end

endmodule
