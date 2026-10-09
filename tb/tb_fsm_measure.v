`timescale 1ns/1ps

// tb_fsm_measure.v
// checking state transitions for control fsm
module tb_fsm_measure;

    reg clk;
    reg rst_n;
    reg start_puf;
    reg start_auth;
    reg lock;
    reg meas_done;
    reg ecc_done;
    reg ecc_fail;
    reg aes_done;

    wire [2:0] state;
    wire meas_start;
    wire [3:0] pair_group;
    wire [2:0] vote_round;
    wire ecc_start;
    wire aes_start;
    wire busy;
    wire done;
    wire key_valid_out;

    control_fsm dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_puf(start_puf),
        .start_auth(start_auth),
        .lock(lock),
        .meas_done(meas_done),
        .ecc_done(ecc_done),
        .ecc_fail(ecc_fail),
        .aes_done(aes_done),
        .state(state),
        .meas_start(meas_start),
        .pair_group(pair_group),
        .vote_round(vote_round),
        .ecc_start(ecc_start),
        .aes_start(aes_start),
        .busy(busy),
        .done(done),
        .key_valid_out(key_valid_out)
    );

    always #10 clk = ~clk;

    integer i, j;

    initial begin
        $dumpfile("tb_fsm_measure.vcd");
        $dumpvars(0, tb_fsm_measure);

        clk = 0;
        rst_n = 0;
        start_puf = 0;
        start_auth = 0;
        lock = 0;
        meas_done = 0;
        ecc_done = 0;
        ecc_fail = 0;
        aes_done = 0;

        #50 rst_n = 1;
        #20;

        // test puf flow
        start_puf = 1;
        #20 start_puf = 0;

        // 5 rounds, 16 groups
        for (i = 0; i < 5; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                wait(meas_start);
                #40;
                meas_done = 1;
                #20;
                meas_done = 0;
                #20;
            end
        end

        wait(ecc_start);
        #40;
        ecc_done = 1;
        #20;
        ecc_done = 0;

        wait(done);
        $display("PUF generation complete.");

        #100;
        // test auth flow
        start_auth = 1;
        #20 start_auth = 0;
        
        // repeat meas + ecc
        for (i = 0; i < 5; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                wait(meas_start);
                #20 meas_done = 1;
                #20 meas_done = 0;
            end
        end

        wait(ecc_start);
        #20 ecc_done = 1;
        #20 ecc_done = 0;

        wait(aes_start);
        #20 aes_done = 1;
        #20 aes_done = 0;

        wait(done);
        $display("Auth complete.");

        #50 $finish;
    end

endmodule
