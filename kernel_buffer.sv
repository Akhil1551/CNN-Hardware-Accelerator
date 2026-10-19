`timescale 1ns / 1ps

module kernel_buffer #(
    parameter int KERNEL_SZ  = 3,
    parameter int DATA_W     = 16,
    parameter int ADDR_WIDTH = 8
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // Synchronous Write Port (Distinct Kernel Names)
    input  logic                     k_wr_en,
    input  logic [ADDR_WIDTH-1:0]    k_wr_row,
    input  logic [ADDR_WIDTH-1:0]    k_wr_col,
    input  logic signed [DATA_W-1:0] k_wr_data,

    // 1-Bit Trigger from Control Block (starts scanning the 3x3 kernel)
    input  logic                     k_load,

    // Outputs to systolic_array
    output logic signed [DATA_W-1:0] k_out,
    output logic                     k_first,
    output logic                     k_valid,
    output logic                     k_done
);

    // 2D Register Matrix for the 3x3 Kernel Weights
    logic signed [DATA_W-1:0] k_mem [0:KERNEL_SZ-1][0:KERNEL_SZ-1];

    // Internal wires from the dedicated mini_addr_gen
    logic [ADDR_WIDTH-1:0] k_row_addr;
    logic [ADDR_WIDTH-1:0] k_col_addr;
    logic                  unused_load_out;

    // -------------------------------------------------------------------------
    // Pre-load 3x3 Kernel with 1..9 for simulation
    // -------------------------------------------------------------------------
    initial begin
        for (int r = 0; r < KERNEL_SZ; r++) begin
            for (int c = 0; c < KERNEL_SZ; c++) begin
                k_mem[r][c] = DATA_W'(r * KERNEL_SZ + c + 1);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous Write Port
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (k_wr_en && (k_wr_row < KERNEL_SZ) && (k_wr_col < KERNEL_SZ)) begin
            k_mem[k_wr_row][k_wr_col] <= k_wr_data;
        end
    end

    // -------------------------------------------------------------------------
    // Dedicated mini_addr_gen (Hardwired to start at 0,0)
    // -------------------------------------------------------------------------
    mini_addr_gen #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_kernel_addr_gen (
        .clk       (clk),
        .rst_n     (rst_n),
        .load      (k_load),
        .start_row ('0),              // Kernel always starts at Row 0
        .start_col ('0),              // Kernel always starts at Col 0
        .load_out  (unused_load_out),
        .row_addr  (k_row_addr),
        .col_addr  (k_col_addr),
        .valid     (k_valid),
        .done      (k_done)
    );

    // -------------------------------------------------------------------------
    // Combinational Read Output to Systolic Array PE[0]
    // -------------------------------------------------------------------------
    assign k_first = k_load; // High on Tap 0 (1st weight of the 3x3 kernel)

    always_comb begin
        if (k_valid && (k_row_addr < KERNEL_SZ) && (k_col_addr < KERNEL_SZ)) begin
            k_out = k_mem[k_row_addr][k_col_addr];
        end else begin
            k_out = '0;
        end
    end

endmodule
