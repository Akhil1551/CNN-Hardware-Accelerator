`timescale 1ns / 1ps
// Simple testbench for cnn_top.
//  - Prints one table per clock cycle (with $strobe, so values are settled)
//  - Prints the final 3x3 output at the end of each data set
//  - Runs several image/kernel data sets back to back

`define PE_ROW(I) \
    $strobe("| %0d | %3d %3d |  %b  | %6d | %6d | %8d | %10d |", I, \
            dut.row_addr[I], dut.col_addr[I], dut.valid[I], \
            $signed(dut.pixel_out[I]), \
            dut.u_systolic_array.g_pe[I].u_pe.k_in, \
            dut.u_systolic_array.g_pe[I].u_pe.prod, \
            dut.u_systolic_array.g_pe[I].u_pe.acc_out);

module tb_cnn_test_top;

    localparam int IMG_H = 5, IMG_W = 5, K = 3, OUT_N = 3;
    localparam int NUM_SETS = 3;

    logic               clk = 0;
    logic               rst_n, start;
    logic               busy, conv_done, ofm_done;
    logic               img_wr_en, k_wr_en;
    logic [7:0]         img_wr_row, img_wr_col, k_wr_row, k_wr_col;
    logic [15:0]        img_wr_data;
    logic signed [15:0] k_wr_data;
    logic signed [35:0] acc_out_mon;
    logic               acc_valid_mon;
    logic [7:0]         ofm_rd_row, ofm_rd_col;
    logic signed [35:0] ofm_rd_data;

    cnn_top dut (
        .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .conv_done(conv_done),
        .img_wr_en(img_wr_en), .img_wr_row(img_wr_row), .img_wr_col(img_wr_col),
        .img_wr_data(img_wr_data),
        .k_wr_en(k_wr_en), .k_wr_row(k_wr_row), .k_wr_col(k_wr_col), .k_wr_data(k_wr_data),
        .acc_out_mon(acc_out_mon), .acc_valid_mon(acc_valid_mon), .ofm_done(ofm_done),
        .ofm_rd_row(ofm_rd_row), .ofm_rd_col(ofm_rd_col), .ofm_rd_data(ofm_rd_data)
    );

    always #5 clk = ~clk;

    // ---------------- data sets ----------------
    int img [NUM_SETS][IMG_H][IMG_W];
    int ker [NUM_SETS][K][K];
    int result [OUT_N][OUT_N];

    initial begin
        for (int s = 0; s < NUM_SETS; s++) begin
            for (int r = 0; r < IMG_H; r++)
                for (int c = 0; c < IMG_W; c++)
                    case (s)
                        0:       img[s][r][c] = r * IMG_W + c + 1;          // 1..25
                        1:       img[s][r][c] = 1;                          // all ones
                        default: img[s][r][c] = ((r * 7 + c * 3) % 13) - 6; // mixed signs
                    endcase
            for (int r = 0; r < K; r++)
                for (int c = 0; c < K; c++)
                    case (s)
                        0:       ker[s][r][c] = r * K + c + 1;              // 1..9
                        1:       ker[s][r][c] = 2;                          // all twos
                        default: ker[s][r][c] = (r * K + c) - 4;            // -4..4
                    endcase
        end
    end

    // ---------------- per-cycle table ----------------
    logic log_en = 0;
    int   cyc    = 0;

    always @(posedge clk) if (log_en) begin
        cyc = cyc + 1;
        $strobe("");
        $strobe("=== Cycle %0d  (t = %0t) ===", cyc, $time);
        $strobe("CTRL : state=%0d en=%b first_load=%b k_load=%b start_row=%0d start_col=%0d busy=%b conv_done=%b",
                dut.u_ctrl.state, dut.en, dut.first_load, dut.k_load,
                dut.start_row, dut.start_col, busy, conv_done);
        $strobe("KBUF : k_valid=%b k_first=%b k_done=%b k_addr=(%0d,%0d) k_out=%0d",
                dut.k_valid, dut.k_first, dut.k_done,
                dut.u_kernel_buffer.k_row_addr, dut.u_kernel_buffer.k_col_addr, dut.k_out);
        $strobe("+---+---------+-----+--------+--------+----------+------------+");
        $strobe("|PE | row col |valid| pixel  |  k_in  |   prod   |    acc     |");
        $strobe("+---+---------+-----+--------+--------+----------+------------+");
        `PE_ROW(0) `PE_ROW(1) `PE_ROW(2)
        `PE_ROW(3) `PE_ROW(4) `PE_ROW(5)
        `PE_ROW(6) `PE_ROW(7) `PE_ROW(8)
        $strobe("+---+---------+-----+--------+--------+----------+------------+");
        $strobe("SYSARR: pe_done_d=%b acc_valid=%b acc_out=%0d",
                dut.u_systolic_array.pe_done_d, acc_valid_mon, acc_out_mon);
        $strobe("OBUF : wr_row=%0d wr_col=%0d ofm_done=%b", dut.wr_row_mon, dut.wr_col_mon, ofm_done);
    end

    // ---------------- one data set ----------------
    task run_set(input int s);
        int timeout;
        begin
            $display("\n#################### DATA SET %0d ####################", s);
            $display("Image:");
            for (int r = 0; r < IMG_H; r++)
                $display("  %4d %4d %4d %4d %4d", img[s][r][0], img[s][r][1], img[s][r][2],
                         img[s][r][3], img[s][r][4]);
            $display("Kernel:");
            for (int r = 0; r < K; r++)
                $display("  %4d %4d %4d", ker[s][r][0], ker[s][r][1], ker[s][r][2]);

            // reset
            rst_n = 0; start = 0; img_wr_en = 0; k_wr_en = 0;
            ofm_rd_row = 0; ofm_rd_col = 0;
            repeat (3) @(negedge clk);
            rst_n = 1;
            @(negedge clk);

            // load image
            for (int r = 0; r < IMG_H; r++)
                for (int c = 0; c < IMG_W; c++) begin
                    img_wr_en = 1; img_wr_row = r; img_wr_col = c;
                    img_wr_data = img[s][r][c];
                    @(negedge clk);
                end
            img_wr_en = 0;

            // load kernel
            for (int r = 0; r < K; r++)
                for (int c = 0; c < K; c++) begin
                    k_wr_en = 1; k_wr_row = r; k_wr_col = c;
                    k_wr_data = ker[s][r][c];
                    @(negedge clk);
                end
            k_wr_en = 0;

            // start + log until done
            cyc = 0;
            log_en = 1;
            start = 1;
            @(negedge clk);
            start = 0;

            timeout = 0;
            while (!conv_done && timeout < 200) begin
                @(negedge clk);
                timeout++;
            end
            repeat (3) @(negedge clk);
            log_en = 0;

            // read final output through the read port
            for (int r = 0; r < OUT_N; r++)
                for (int c = 0; c < OUT_N; c++) begin
                    ofm_rd_row = r; ofm_rd_col = c;
                    #1;
                    result[r][c] = ofm_rd_data;
                end

            $display("\n---- FINAL OUTPUT (data set %0d, after ReLU) ----", s);
            for (int r = 0; r < OUT_N; r++)
                $display("  %10d %10d %10d", result[r][0], result[r][1], result[r][2]);
            if (timeout >= 200) $display("WARNING: timed out waiting for conv_done");
        end
    endtask

    initial begin
        for (int s = 0; s < NUM_SETS; s++)
            run_set(s);
        $display("\nAll data sets done.");
	        $finish;
    end

endmodule
