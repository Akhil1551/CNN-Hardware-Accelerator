`timescale 1ns / 1ps

module output_buffer #(
    parameter int IMG_H      = 5,
    parameter int IMG_W      = 5,
    parameter int KERNEL_SZ  = 3,
    parameter int ACC_W      = 36,
    parameter int ADDR_WIDTH = 8
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // From systolic_array
    input  logic                     acc_valid, // High when a PE outputs a finished sum
    input  logic signed [ACC_W-1:0]  acc_in,    // Connected to systolic_array.acc_out

    // Optional Combinational Read Port (to inspect stored results externally)
    input  logic [ADDR_WIDTH-1:0]    ofm_rd_row,
    input  logic [ADDR_WIDTH-1:0]    ofm_rd_col,
    output logic signed [ACC_W-1:0]  ofm_rd_data,

    // Status outputs
    output logic [ADDR_WIDTH-1:0]    wr_row_mon, // Monitors current write row
    output logic [ADDR_WIDTH-1:0]    wr_col_mon, // Monitors current write col
    output logic                     ofm_done    // High when final (2,2) output is being written
);

    localparam int OUT_H = IMG_H - KERNEL_SZ + 1; // 5 - 3 + 1 = 3
    localparam int OUT_W = IMG_W - KERNEL_SZ + 1; // 5 - 3 + 1 = 3

    // 2D Output Feature Map Register Matrix (3x3)
    logic signed [ACC_W-1:0] out_mem [0:OUT_H-1][0:OUT_W-1];

    // Internal 2D write coordinate counters
    logic [ADDR_WIDTH-1:0] wr_row;
    logic [ADDR_WIDTH-1:0] wr_col;

    assign wr_row_mon = wr_row;
    assign wr_col_mon = wr_col;
    assign ofm_done   = acc_valid && (wr_row == ADDR_WIDTH'(OUT_H - 1)) && (wr_col == ADDR_WIDTH'(OUT_W - 1));

    // -------------------------------------------------------------------------
    // Sequential Write & Internal 2D Address Counter
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_row <= '0;
            wr_col <= '0;
            for (int r = 0; r < OUT_H; r++) begin
                for (int c = 0; c < OUT_W; c++) begin
                    out_mem[r][c] <= '0;
                end
            end
        end else if (acc_valid) begin
            // 1. Store incoming accumulator sum at current (wr_row, wr_col)
            out_mem[wr_row][wr_col] <= acc_in;

            // 2. Advance internal 2D write pointer for the next cycle
            if (wr_col == ADDR_WIDTH'(OUT_W - 1)) begin
                wr_col <= '0;
                if (wr_row == ADDR_WIDTH'(OUT_H - 1)) begin
                    wr_row <= '0; // All 9 outputs stored; wrap back to (0,0)
                end else begin
                    wr_row <= wr_row + 1'b1;
                end
            end else begin
                wr_col <= wr_col + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Combinational Read Port
    // -------------------------------------------------------------------------
    always_comb begin
        if ((ofm_rd_row < OUT_H) && (ofm_rd_col < OUT_W))
            ofm_rd_data = out_mem[ofm_rd_row][ofm_rd_col];
        else
            ofm_rd_data = '0;
    end

endmodule
