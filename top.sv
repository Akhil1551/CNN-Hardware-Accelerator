`timescale 1ns / 1ps

module cnn_top #(
    parameter int IMG_H      = 5,
    parameter int IMG_W      = 5,
    parameter int KERNEL_SZ  = 3,
    parameter int DATA_W     = 16,
    parameter int ACC_W      = 36,
    parameter int ADDR_WIDTH = 8,
    parameter int NUM_GENS   = 9
)(
    input  logic                                clk,
    input  logic                                rst_n,
    input  logic                                start,
    output logic                                busy,
    output logic                                conv_done,

    // Optional External Write Ports (to load image/kernel dynamically if needed)
    input  logic                                img_wr_en,
    input  logic [ADDR_WIDTH-1:0]               img_wr_row,
    input  logic [ADDR_WIDTH-1:0]               img_wr_col,
    input  logic [DATA_W-1:0]                   img_wr_data,

    input  logic                                k_wr_en,
    input  logic [ADDR_WIDTH-1:0]               k_wr_row,
    input  logic [ADDR_WIDTH-1:0]               k_wr_col,
    input  logic signed [DATA_W-1:0]            k_wr_data,

    // Final Output Feature Map Monitoring Ports
    output logic signed [ACC_W-1:0]             acc_out_mon,
    output logic                                acc_valid_mon,
    output logic                                ofm_done,

    // Output Feature Map Read Port (select an output location to read its value)
    input  logic [ADDR_WIDTH-1:0]               ofm_rd_row,
    input  logic [ADDR_WIDTH-1:0]               ofm_rd_col,
    output logic signed [ACC_W-1:0]             ofm_rd_data
);

    // Internal interconnect wires
    logic                                       en;
    logic                                       first_load;
    logic [ADDR_WIDTH-1:0]                      start_row;
    logic [ADDR_WIDTH-1:0]                      start_col;
    logic                                       k_load;
    logic                                       k_first;
    logic                                       k_valid;
    logic                                       k_done;
    logic signed [DATA_W-1:0]                   k_out;

    logic [NUM_GENS-1:0][ADDR_WIDTH-1:0]        row_addr;
    logic [NUM_GENS-1:0][ADDR_WIDTH-1:0]        col_addr;
    logic [NUM_GENS-1:0]                        valid;
    logic [NUM_GENS-1:0]                        done;
    logic [NUM_GENS-1:0][DATA_W-1:0]            pixel_out;

    logic signed [ACC_W-1:0]                    acc_out;
    logic                                       acc_valid;
    logic [ADDR_WIDTH-1:0]                      wr_row_mon;
    logic [ADDR_WIDTH-1:0]                      wr_col_mon;

    // Monitor assignments
    assign acc_out_mon   = acc_out;
    assign acc_valid_mon = acc_valid;

    // 1. Master Control Block
    im2col_ctrl #(
        .IMG_H     (IMG_H),
        .IMG_W     (IMG_W),
        .KERNEL_SZ (KERNEL_SZ),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_ctrl (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .busy      (busy),
        .conv_done (conv_done),
        .k_done    (k_done),
        .acc_valid (acc_valid),
        .en        (en),
        .first_load(first_load),
        .start_row (start_row),
        .start_col (start_col),
        .k_load    (k_load)
    );

    // 2. im2col Address Generator Array
    im2col_addr_gen #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_GENS  (NUM_GENS)
    ) u_addr_gen (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (en),
        .first_load(first_load),
        .start_row (start_row),
        .start_col (start_col),
        .row_addr  (row_addr),
        .col_addr  (col_addr),
        .valid     (valid),
        .done      (done)
    );

    // 3. Combinational Image Buffer
    img_buffer #(
        .IMG_H     (IMG_H),
        .IMG_W     (IMG_W),
        .DATA_WIDTH(DATA_W),
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_GENS  (NUM_GENS)
    ) u_img_buffer (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (img_wr_en),
        .wr_row   (img_wr_row),
        .wr_col   (img_wr_col),
        .wr_data  (img_wr_data),
        .row_addr (row_addr),
        .col_addr (col_addr),
        .valid    (valid),
        .pixel_out(pixel_out)
    );

    // 4. Kernel Buffer with Internal mini_addr_gen
    kernel_buffer #(
        .KERNEL_SZ (KERNEL_SZ),
        .DATA_W    (DATA_W),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_kernel_buffer (
        .clk      (clk),
        .rst_n    (rst_n),
        .k_wr_en  (k_wr_en),
        .k_wr_row (k_wr_row),
        .k_wr_col (k_wr_col),
        .k_wr_data(k_wr_data),
        .k_load   (k_load),
        .k_out    (k_out),
        .k_first  (k_first),
        .k_valid  (k_valid),
        .k_done   (k_done)
    );

    // 5. 9-PE Systolic Array
    systolic_array #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W),
        .NUM_WIN(NUM_GENS)
    ) u_systolic_array (
        .clk       (clk),
        .rst_n     (rst_n),
        .pix_in    (signed'(pixel_out)),
        .k_in      (k_out),
        .k_first   (k_first),
        .valid_in_0(valid[0]),
        .done_in   (done),
        .acc_out   (acc_out),
        .acc_valid (acc_valid)
    );

    // 6. Output Feature Map Buffer
    output_buffer #(
        .IMG_H     (IMG_H),
        .IMG_W     (IMG_W),
        .KERNEL_SZ (KERNEL_SZ),
        .ACC_W     (ACC_W),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_output_buffer (
        .clk        (clk),
        .rst_n      (rst_n),
        .acc_valid  (acc_valid),
        .acc_in     (acc_out),
        .ofm_rd_row (ofm_rd_row),
        .ofm_rd_col (ofm_rd_col),
        .ofm_rd_data(ofm_rd_data),
        .wr_row_mon (wr_row_mon),
        .wr_col_mon (wr_col_mon),
        .ofm_done   (ofm_done)
    );

endmodule
