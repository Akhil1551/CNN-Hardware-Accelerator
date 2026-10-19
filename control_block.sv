`timescale 1ns / 1ps

module im2col_ctrl #(
    parameter int IMG_H      = 5,
    parameter int IMG_W      = 5,
    parameter int KERNEL_SZ  = 3,
    parameter int ADDR_WIDTH = 8
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Top-level system handshake
    input  logic                  start,      // 1-cycle pulse to start convolution
    output logic                  busy,       // High while accelerator is running
    output logic                  conv_done,  // Pulses high on the final valid output cycle

    // Feedback from datapath blocks
    input  logic                  k_done,     // From kernel_buffer (for multi-batch retriggering)
    input  logic                  acc_valid,  // From systolic_array (tracks completed windows)

    // Outputs to im2col_addr_gen
    output logic                  en,
    output logic                  first_load,
    output logic [ADDR_WIDTH-1:0] start_row,
    output logic [ADDR_WIDTH-1:0] start_col,

    // Output to kernel_buffer
    output logic                  k_load
);

    localparam int MAX_ROW   = IMG_H - KERNEL_SZ;              // 5 - 3 = 2
    localparam int MAX_COL   = IMG_W - KERNEL_SZ;              // 5 - 3 = 2
    localparam int TOTAL_WIN = (MAX_ROW + 1) * (MAX_COL + 1);  // 3 * 3 = 9 windows
    localparam int CNT_W     = $clog2(TOTAL_WIN + 1);

    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        STREAM = 2'b01,
        DRAIN  = 2'b10
    } state_t;

    state_t           state;
    logic [CNT_W-1:0] out_cnt;
    logic             k_done_d;

    // Register k_done by 1 cycle so kernel_buffer can re-trigger on Cycle 10 if en is still high
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            k_done_d <= 1'b0;
        else
            k_done_d <= k_done;
    end

    // Trigger kernel_buffer on initial kickoff OR when a 9-tap kernel pass finishes & more windows remain
    assign k_load    = first_load | (k_done_d & en);
    assign busy      = (state != IDLE);
    assign conv_done = (state != IDLE) && acc_valid && (out_cnt == CNT_W'(TOTAL_WIN - 1));

    // -------------------------------------------------------------------------
    // Control FSM & Master Window Anchor Counter (start_row, start_col)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            en         <= 1'b0;
            first_load <= 1'b0;
            start_row  <= '0;
            start_col  <= '0;
            out_cnt    <= '0;
        end else begin
            case (state)
                IDLE: begin
                    en         <= 1'b0;
                    first_load <= 1'b0;
                    start_row  <= '0;
                    start_col  <= '0;
                    out_cnt    <= '0;

                    if (start) begin
                        state      <= STREAM;
                        en         <= 1'b1;
                        first_load <= 1'b1;
                        start_row  <= '0;
                        start_col  <= '0;
                    end
                end

                STREAM: begin
                    first_load <= 1'b0; // Only high on the first cycle of STREAM

                    // Count any valid outputs that appear during STREAM (for large images)
                    if (acc_valid)
                        out_cnt <= out_cnt + 1'b1;

                    // Step (start_row, start_col) across all valid window anchors
                    if (start_col == ADDR_WIDTH'(MAX_COL)) begin
                        if (start_row == ADDR_WIDTH'(MAX_ROW)) begin
                            // Final window anchor (2,2) has just been broadcast!
                            en        <= 1'b0;
                            start_row <= '0;
                            start_col <= '0;
                            state     <= DRAIN;
                        end else begin
                            start_col <= '0;
                            start_row <= start_row + 1'b1;
                        end
                    end else begin
                        start_col <= start_col + 1'b1;
                    end
                end

                DRAIN: begin
                    // Wait for all remaining PE results to exit systolic_array
                    if (acc_valid) begin
                        if (out_cnt == CNT_W'(TOTAL_WIN - 1)) begin
                            out_cnt <= '0;
                            state   <= IDLE;
                        end else begin
                            out_cnt <= out_cnt + 1'b1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
