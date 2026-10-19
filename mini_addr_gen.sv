`timescale 1ns / 1ps

module mini_addr_gen #(
    parameter int ADDR_WIDTH = 8
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  load,
    input  logic [ADDR_WIDTH-1:0] start_row,
    input  logic [ADDR_WIDTH-1:0] start_col,
    
    output logic                  load_out,
    output logic [ADDR_WIDTH-1:0] row_addr,
    output logic [ADDR_WIDTH-1:0] col_addr,
    output logic                  valid,
    output logic                  done
);

    // Internal state registers
    logic                  busy;
    logic [ADDR_WIDTH-1:0] base_col;
    logic [ADDR_WIDTH-1:0] reg_row;
    logic [ADDR_WIDTH-1:0] reg_col;
    logic [1:0]            row_step;
    logic [1:0]            col_step;

    // -------------------------------------------------------------------------
    // Combinatorial Output Logic (Cycle 0 Bypass + Cycles 1..8 Registered)
    // -------------------------------------------------------------------------
    always_comb begin
        valid    = load | busy;
        row_addr = load ? start_row : reg_row;
        col_addr = load ? start_col : reg_col;
        done     = busy & (row_step == 2'd2) & (col_step == 2'd2) & ~load;
    end

    // -------------------------------------------------------------------------
    // Sequential Stepping & Systolic Trigger Propagation
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_out <= 1'b0;
            busy     <= 1'b0;
            base_col <= '0;
            reg_row  <= '0;
            reg_col  <= '0;
            row_step <= 2'd0;
            col_step <= 2'd0;
        end else begin
            // 1-cycle systolic delay of load for the next generator in the chain
            load_out <= load;

            if (load) begin
                // Cycle 0 is currently on the outputs combinatorially (Tap 0).
                // Pre-load the registers with Tap 1 (row + 0, col + 1) for Cycle 1.
                busy     <= 1'b1;
                base_col <= start_col;
                reg_row  <= start_row;
                reg_col  <= start_col + 1'b1;
                row_step <= 2'd0;
                col_step <= 2'd1;
            end else if (busy) begin
                if (col_step == 2'd2) begin
                    if (row_step == 2'd2) begin
                        // Completed Tap 8 (Cycle 8); return to Idle on next edge
                        busy     <= 1'b0;
                        row_step <= 2'd0;
                        col_step <= 2'd0;
                    end else begin
                        // End of current row; wrap column to base_col and increment row
                        reg_row  <= reg_row + 1'b1;
                        reg_col  <= base_col;
                        row_step <= row_step + 2'd1;
                        col_step <= 2'd0;
                    end
                end else begin
                    // Standard horizontal step across the current row
                    reg_col  <= reg_col + 1'b1;
                    col_step <= col_step + 2'd1;
                end
            end
        end
    end

endmodule
