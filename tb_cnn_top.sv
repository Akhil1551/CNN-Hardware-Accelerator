`timescale 1ns / 1ps
// =============================================================================
// Testbench : tb_cnn_top
// DUT       : cnn_top  (5x5 image, 3x3 kernel, 9 PEs, 3x3 output feature map)
//
// What it does
//   1. Resets the DUT.
//   2. Loads a custom 5x5 image and 3x3 kernel through the external write ports
//      (overwrites the 1..25 / 1..9 values pre-loaded inside the buffers).
//   3. Pulses `start` and lets the convolution run to conv_done / ofm_done.
//   4. Reads all 9 output locations back through the new ofm_rd_row/ofm_rd_col
//      port (plus one out-of-range address) and compares against a golden model
//      (3x3 convolution + ReLU, same as output_buffer EN_RELU=1).
//
// Logging
//   * One block per clock cycle, printed with $fstrobe, so every value is the
//     settled value at the END of the posedge time step (after all non-blocking
//     updates). No $monitor is used.
//   * The multi-channel descriptor `mcd` has bit 0 set, so each $fstrobe goes to
//     the console AND to cnn_top_log.txt.
//   * Reading the per-cycle values: the operands shown for each PE (pix_in,
//     k_in, prod) are the ones that will be accumulated on the NEXT clock edge;
//     `acc` is the accumulator result of the edge that just happened.
//
// NUM_GENS is assumed to be 9 (the per-PE / per-generator lines are unrolled).
// =============================================================================
`define AGEN_LINE(IDX) \
    $fstrobe(mcd, "  AGEN[%0d] load=%b valid=%b row_addr=%0d col_addr=%0d done=%b  ->  pixel_out=%0d", \
             IDX, dut.u_addr_gen.gen_load[IDX], dut.valid[IDX], dut.row_addr[IDX], \
             dut.col_addr[IDX], dut.done[IDX], dut.pixel_out[IDX]);

`define PE_LINE(IDX) \
    $fstrobe(mcd, "  PE[%0d]   en_in=%b clr_in=%b pix_in=%0d k_in=%0d prod=%0d | acc=%0d | k_out=%0d en_out=%b clr_out=%b", \
             IDX, pe_en_in[IDX], pe_clr_in[IDX], pe_pix[IDX], pe_kin[IDX], pe_prod[IDX], \
             pe_acc[IDX], pe_kout[IDX], pe_en_out[IDX], pe_clr_out[IDX]);

module tb_cnn_top;

    // ------------------------------------------------------------------ params
    localparam int IMG_H      = 5;
    localparam int IMG_W      = 5;
    localparam int KERNEL_SZ  = 3;
    localparam int DATA_W     = 16;
    localparam int ACC_W      = 36;
    localparam int ADDR_WIDTH = 8;
    localparam int NUM_GENS   = 9;
    localparam int OUT_H      = IMG_H - KERNEL_SZ + 1;
    localparam int OUT_W      = IMG_W - KERNEL_SZ + 1;
    localparam int MAX_CYCLES = 300;

    // ----------------------------------------------------------------- DUT I/O
    logic                       clk;
    logic                       rst_n;
    logic                       start;
    logic                       busy;
    logic                       conv_done;

    logic                       img_wr_en;
    logic [ADDR_WIDTH-1:0]      img_wr_row;
    logic [ADDR_WIDTH-1:0]      img_wr_col;
    logic [DATA_W-1:0]          img_wr_data;

    logic                       k_wr_en;
    logic [ADDR_WIDTH-1:0]      k_wr_row;
    logic [ADDR_WIDTH-1:0]      k_wr_col;
    logic signed [DATA_W-1:0]   k_wr_data;

    logic signed [ACC_W-1:0]    acc_out_mon;
    logic                       acc_valid_mon;
    logic                       ofm_done;

    logic [ADDR_WIDTH-1:0]      ofm_rd_row;
    logic [ADDR_WIDTH-1:0]      ofm_rd_col;
    logic signed [ACC_W-1:0]    ofm_rd_data;

    cnn_top #(
        .IMG_H     (IMG_H),
        .IMG_W     (IMG_W),
        .KERNEL_SZ (KERNEL_SZ),
        .DATA_W    (DATA_W),
        .ACC_W     (ACC_W),
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_GENS  (NUM_GENS)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .busy         (busy),
        .conv_done    (conv_done),
        .img_wr_en    (img_wr_en),
        .img_wr_row   (img_wr_row),
        .img_wr_col   (img_wr_col),
        .img_wr_data  (img_wr_data),
        .k_wr_en      (k_wr_en),
        .k_wr_row     (k_wr_row),
        .k_wr_col     (k_wr_col),
        .k_wr_data    (k_wr_data),
        .acc_out_mon  (acc_out_mon),
        .acc_valid_mon(acc_valid_mon),
        .ofm_done     (ofm_done),
        .ofm_rd_row   (ofm_rd_row),
        .ofm_rd_col   (ofm_rd_col),
        .ofm_rd_data  (ofm_rd_data)
    );

    // -------------------------------------------------------------------- clock
    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ------------------------------------------- per-PE probes (generate scope)
    wire                       pe_en_in   [0:NUM_GENS-1];
    wire                       pe_clr_in  [0:NUM_GENS-1];
    wire                       pe_en_out  [0:NUM_GENS-1];
    wire                       pe_clr_out [0:NUM_GENS-1];
    wire signed [DATA_W-1:0]   pe_pix     [0:NUM_GENS-1];
    wire signed [DATA_W-1:0]   pe_kin     [0:NUM_GENS-1];
    wire signed [DATA_W-1:0]   pe_kout    [0:NUM_GENS-1];
    wire signed [2*DATA_W-1:0] pe_prod    [0:NUM_GENS-1];
    wire signed [ACC_W-1:0]    pe_acc     [0:NUM_GENS-1];

    genvar gi;
    generate
        for (gi = 0; gi < NUM_GENS; gi++) begin : g_probe
            assign pe_en_in[gi]   = dut.u_systolic_array.g_pe[gi].u_pe.en_in;
            assign pe_clr_in[gi]  = dut.u_systolic_array.g_pe[gi].u_pe.clr_in;
            assign pe_en_out[gi]  = dut.u_systolic_array.g_pe[gi].u_pe.en_out;
            assign pe_clr_out[gi] = dut.u_systolic_array.g_pe[gi].u_pe.clr_out;
            assign pe_pix[gi]     = dut.u_systolic_array.g_pe[gi].u_pe.pix_in;
            assign pe_kin[gi]     = dut.u_systolic_array.g_pe[gi].u_pe.k_in;
            assign pe_kout[gi]    = dut.u_systolic_array.g_pe[gi].u_pe.k_out;
            assign pe_prod[gi]    = dut.u_systolic_array.g_pe[gi].u_pe.prod;
            assign pe_acc[gi]     = dut.u_systolic_array.g_pe[gi].u_pe.acc_out;
        end
    endgenerate

    // ------------------------------------------------------- golden / stimulus
    int  tb_img [0:IMG_H-1][0:IMG_W-1];
    int  tb_k   [0:KERNEL_SZ-1][0:KERNEL_SZ-1];
    int  exp_ofm[0:OUT_H-1][0:OUT_W-1];

    integer mcd;            // bit0 = console, bit1.. = log file
    integer cyc;
    integer errors;
    integer checks;

    // ---------------------------------------------------------------------
    // Per-cycle log (single process => deterministic line order)
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        cyc = cyc + 1;

        $fstrobe(mcd, "");
        $fstrobe(mcd, "================ cycle %0d @ %0t ================", cyc, $time);

        // ---- top-level handshake + control block (im2col_ctrl)
        $fstrobe(mcd, "[TOP ] rst_n=%b start=%b busy=%b conv_done=%b ofm_done=%b",
                 rst_n, start, busy, conv_done, ofm_done);
        $fstrobe(mcd, "[CTRL] state=%0d en=%b first_load=%b k_load=%b k_done_d=%b start_row=%0d start_col=%0d out_cnt=%0d",
                 dut.u_ctrl.state, dut.en, dut.first_load, dut.k_load, dut.u_ctrl.k_done_d,
                 dut.start_row, dut.start_col, dut.u_ctrl.out_cnt);

        // ---- data written into the image buffer / kernel buffer
        $fstrobe(mcd, "[IMGW] wr_en=%b wr_row=%0d wr_col=%0d wr_data=%0d | mem[wr_row][wr_col]=%0d",
                 img_wr_en, img_wr_row, img_wr_col, $signed(img_wr_data),
                 (img_wr_en && img_wr_row < IMG_H && img_wr_col < IMG_W) ?
                     $signed(dut.u_img_buffer.mem[img_wr_row][img_wr_col]) : 0);
        $fstrobe(mcd, "[KW  ] wr_en=%b wr_row=%0d wr_col=%0d wr_data=%0d | k_mem[wr_row][wr_col]=%0d",
                 k_wr_en, k_wr_row, k_wr_col, k_wr_data,
                 (k_wr_en && k_wr_row < KERNEL_SZ && k_wr_col < KERNEL_SZ) ?
                     dut.u_kernel_buffer.k_mem[k_wr_row][k_wr_col] : 0);

        // ---- kernel buffer streaming into PE[0]
        $fstrobe(mcd, "[KBUF] k_load=%b k_valid=%b k_first=%b k_done=%b k_row_addr=%0d k_col_addr=%0d k_out=%0d",
                 dut.k_load, dut.k_valid, dut.k_first, dut.k_done,
                 dut.u_kernel_buffer.k_row_addr, dut.u_kernel_buffer.k_col_addr, dut.k_out);

        // ---- im2col address generators -> image buffer pixel outputs
        $fstrobe(mcd, "[IM2COL addr gens -> img_buffer]");
        `AGEN_LINE(0) `AGEN_LINE(1) `AGEN_LINE(2)
        `AGEN_LINE(3) `AGEN_LINE(4) `AGEN_LINE(5)
        `AGEN_LINE(6) `AGEN_LINE(7) `AGEN_LINE(8)

        // ---- systolic array: per-PE operands and accumulators
        $fstrobe(mcd, "[SYSTOLIC PEs] (pix_in/k_in/prod = operands for NEXT edge, acc = result of this edge)");
        `PE_LINE(0) `PE_LINE(1) `PE_LINE(2)
        `PE_LINE(3) `PE_LINE(4) `PE_LINE(5)
        `PE_LINE(6) `PE_LINE(7) `PE_LINE(8)
        $fstrobe(mcd, "[SYS ] pe_done_d=%b acc_valid=%b acc_out=%0d",
                 dut.u_systolic_array.pe_done_d, acc_valid_mon, acc_out_mon);

        // ---- output buffer
        $fstrobe(mcd, "[OBUF] acc_valid=%b acc_in=%0d wr_row=%0d wr_col=%0d ofm_done=%b | store_value(after ReLU)=%0d",
                 dut.acc_valid, dut.acc_out, dut.wr_row_mon, dut.wr_col_mon, ofm_done,
                 (dut.acc_out < 0) ? 0 : dut.acc_out);
        $fstrobe(mcd, "[OFMR] ofm_rd_row=%0d ofm_rd_col=%0d ofm_rd_data=%0d",
                 ofm_rd_row, ofm_rd_col, ofm_rd_data);
    end

    // ---------------------------------------------------------------------
    // Helper tasks
    // ---------------------------------------------------------------------
    task automatic do_reset;
        begin
            rst_n       = 1'b0;
            start       = 1'b0;
            img_wr_en   = 1'b0; img_wr_row = '0; img_wr_col = '0; img_wr_data = '0;
            k_wr_en     = 1'b0; k_wr_row   = '0; k_wr_col   = '0; k_wr_data   = '0;
            ofm_rd_row  = '0;   ofm_rd_col = '0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
        end
    endtask

    task automatic load_image;
        begin
            $fdisplay(mcd, "\n>>> Loading image through img_wr_* ports");
            for (int r = 0; r < IMG_H; r++) begin
                for (int c = 0; c < IMG_W; c++) begin
                    @(negedge clk);
                    img_wr_en   = 1'b1;
                    img_wr_row  = ADDR_WIDTH'(r);
                    img_wr_col  = ADDR_WIDTH'(c);
                    img_wr_data = DATA_W'(tb_img[r][c]);
                end
            end
            @(negedge clk);
            img_wr_en = 1'b0;
        end
    endtask

    task automatic load_kernel;
        begin
            $fdisplay(mcd, "\n>>> Loading kernel through k_wr_* ports");
            for (int r = 0; r < KERNEL_SZ; r++) begin
                for (int c = 0; c < KERNEL_SZ; c++) begin
                    @(negedge clk);
                    k_wr_en   = 1'b1;
                    k_wr_row  = ADDR_WIDTH'(r);
                    k_wr_col  = ADDR_WIDTH'(c);
                    k_wr_data = DATA_W'(tb_k[r][c]);
                end
            end
            @(negedge clk);
            k_wr_en = 1'b0;
        end
    endtask

    task automatic compute_golden;
        int acc;
        begin
            for (int r = 0; r < OUT_H; r++) begin
                for (int c = 0; c < OUT_W; c++) begin
                    acc = 0;
                    for (int i = 0; i < KERNEL_SZ; i++)
                        for (int j = 0; j < KERNEL_SZ; j++)
                            acc += tb_img[r+i][c+j] * tb_k[i][j];
                    exp_ofm[r][c] = (acc < 0) ? 0 : acc;   // ReLU (EN_RELU = 1)
                end
            end
        end
    endtask

    task automatic print_tables;
        begin
            $fdisplay(mcd, "\n---- Input image (%0dx%0d) ----", IMG_H, IMG_W);
            for (int r = 0; r < IMG_H; r++)
                $fdisplay(mcd, "  %4d %4d %4d %4d %4d", tb_img[r][0], tb_img[r][1],
                          tb_img[r][2], tb_img[r][3], tb_img[r][4]);
            $fdisplay(mcd, "---- Kernel (%0dx%0d) ----", KERNEL_SZ, KERNEL_SZ);
            for (int r = 0; r < KERNEL_SZ; r++)
                $fdisplay(mcd, "  %4d %4d %4d", tb_k[r][0], tb_k[r][1], tb_k[r][2]);
            $fdisplay(mcd, "---- Expected output feature map (conv + ReLU) ----");
            for (int r = 0; r < OUT_H; r++)
                $fdisplay(mcd, "  %6d %6d %6d", exp_ofm[r][0], exp_ofm[r][1], exp_ofm[r][2]);
        end
    endtask

    // Select an output location through the new read port and check it.
    // Module-level copies are used so the deferred $fstrobe sees stable values.
    int rd_r, rd_c, rd_exp;

    task read_check(input int row, input int col, input int expected);
        begin
            @(negedge clk);
            rd_r = row; rd_c = col; rd_exp = expected;
            ofm_rd_row = ADDR_WIDTH'(row);
            ofm_rd_col = ADDR_WIDTH'(col);
            #1;
            checks = checks + 1;
            if (ofm_rd_data !== ACC_W'(rd_exp)) begin
                errors = errors + 1;
                $fstrobe(mcd, "[READ ] FAIL ofm[%0d][%0d]: got %0d expected %0d",
                         rd_r, rd_c, ofm_rd_data, rd_exp);
            end else begin
                $fstrobe(mcd, "[READ ] PASS ofm[%0d][%0d] = %0d", rd_r, rd_c, ofm_rd_data);
            end
        end
    endtask

    // ---------------------------------------------------------------------
    // Main sequence
    // ---------------------------------------------------------------------
    int wait_cnt;

    initial begin
        mcd    = $fopen("cnn_top_log.txt");
        mcd    = mcd | 32'h1;           // also echo to console
        cyc    = 0;
        errors = 0;
        checks = 0;

        // Test data (mixed signs so ReLU is exercised)
        for (int r = 0; r < IMG_H; r++)
            for (int c = 0; c < IMG_W; c++)
                tb_img[r][c] = ((r * 7 + c * 3) % 13) - 6;
        tb_k[0][0] =  1; tb_k[0][1] =  2; tb_k[0][2] =  3;
        tb_k[1][0] = -4; tb_k[1][1] =  5; tb_k[1][2] = -6;
        tb_k[2][0] =  7; tb_k[2][1] = -8; tb_k[2][2] =  9;

        compute_golden();
        print_tables();

        $fdisplay(mcd, "\n>>> Reset");
        do_reset();

        load_image();
        load_kernel();

        // One-cycle start pulse
        $fdisplay(mcd, "\n>>> start pulse");
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        // Wait for the final output (conv_done) with a watchdog
        wait_cnt = 0;
        while (!conv_done && wait_cnt < MAX_CYCLES) begin
            @(negedge clk);
            wait_cnt++;
        end
        if (wait_cnt >= MAX_CYCLES) begin
            errors = errors + 1;
            $fdisplay(mcd, "ERROR: timeout waiting for conv_done");
        end

        // Let the last value be written, then let busy drop
        repeat (3) @(negedge clk);

        // Read every output location back through ofm_rd_row / ofm_rd_col
        $fdisplay(mcd, "\n>>> Reading output feature map through ofm_rd_* port");
        for (int r = 0; r < OUT_H; r++)
            for (int c = 0; c < OUT_W; c++)
                read_check(r, c, exp_ofm[r][c]);
        // Out-of-range address must return 0
        read_check(OUT_H, 0, 0);
        read_check(0, OUT_W, 0);

        repeat (2) @(negedge clk);

        $fdisplay(mcd, "\n=====================================================");
        if (errors == 0)
            $fdisplay(mcd, " TEST PASSED : %0d/%0d read checks matched", checks, checks);
        else
            $fdisplay(mcd, " TEST FAILED : %0d error(s) in %0d checks", errors, checks);
        $fdisplay(mcd, "=====================================================");
        $fclose(mcd);
        $finish;
    end

endmodule
