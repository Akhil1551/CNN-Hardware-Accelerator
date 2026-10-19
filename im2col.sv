`timescale 1ns / 1ps

module im2col_addr_gen #(
    parameter int ADDR_WIDTH = 8,
    parameter int NUM_GENS   = 9
)(
    input  logic                                clk,
    input  logic                                rst_n,
    input  logic                                en,         // High while Control Block sends valid window anchors
    input  logic                                first_load, // 1-cycle initial kickoff pulse from Control Block
    input  logic [ADDR_WIDTH-1:0]               start_row,  // Shared window anchor row bus
    input  logic [ADDR_WIDTH-1:0]               start_col,  // Shared window anchor col bus

    output logic [NUM_GENS-1:0][ADDR_WIDTH-1:0] row_addr,   // 9 parallel row addresses
    output logic [NUM_GENS-1:0][ADDR_WIDTH-1:0] col_addr,   // 9 parallel col addresses
    output logic [NUM_GENS-1:0]                 valid,      // 9 parallel valid flags
    output logic [NUM_GENS-1:0]                 done        // 9 parallel done pulses
);

    // Internal systolic load chain wires
    logic [NUM_GENS-1:0] gen_load;
    logic [NUM_GENS-1:0] gen_load_out;

    // -------------------------------------------------------------------------
    // Systolic Ring Trigger Logic
    // -------------------------------------------------------------------------
    // Gen 0 triggers on initial kickoff (first_load) OR loops back from Gen 8
    // when the Control Block is still broadcasting valid windows (en == 1)
    assign gen_load[0] = first_load | (gen_load_out[NUM_GENS-1] & en);

    // Generators 1 to 8 receive their trigger systolically from the previous block
    assign gen_load[NUM_GENS-1:1] = gen_load_out[NUM_GENS-2:0];

    // -------------------------------------------------------------------------
    // Instantiate 9 mini_addr_gen Blocks via Generate Loop
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_GENS; i++) begin : g_mini_addr_gen
            mini_addr_gen #(
                .ADDR_WIDTH(ADDR_WIDTH)
            ) u_mini_addr_gen (
                .clk       (clk),
                .rst_n     (rst_n),
                .load      (gen_load[i]),
                .start_row (start_row),
                .start_col (start_col),
                .load_out  (gen_load_out[i]),
                .row_addr  (row_addr[i]),
                .col_addr  (col_addr[i]),
                .valid     (valid[i]),
                .done      (done[i])
            );
        end
    endgenerate

endmodule
