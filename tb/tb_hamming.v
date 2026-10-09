`timescale 1ns/1ps

// tb_hamming.v
// testing hamming 15,11 in error correction
module tb_hamming;

    reg clk;
    reg rst_n;
    reg [255:0] raw_response;
    reg [255:0] mask;
    reg [51:0] helper_data;
    reg [2:0] vote_round;
    reg vote_valid;
    reg ecc_start;
    reg mode;
    
    wire [127:0] key;
    wire key_valid;
    wire ecc_fail;
    wire ecc_done;
    wire [51:0] helper_data_out;

    error_correction dut (
        .clk(clk),
        .rst_n(rst_n),
        .raw_response(raw_response),
        .mask(mask),
        .helper_data(helper_data),
        .vote_round(vote_round),
        .vote_valid(vote_valid),
        .ecc_start(ecc_start),
        .mode(mode),
        .key(key),
        .key_valid(key_valid),
        .ecc_fail(ecc_fail),
        .ecc_done(ecc_done),
        .helper_data_out(helper_data_out)
    );

    always #10 clk = ~clk;

    integer i;
    reg [255:0] enroll_data;

    initial begin
        $dumpfile("tb_hamming.vcd");
        $dumpvars(0, tb_hamming);

        clk = 0;
        rst_n = 0;
        raw_response = 0;
        mask = {256{1'b1}};
        helper_data = 0;
        vote_round = 0;
        vote_valid = 0;
        ecc_start = 0;
        mode = 1; // 1 = ENROLL

        #50 rst_n = 1;
        #20;

        // ENROLL MODE
        enroll_data = 256'h1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF;
        for (i=0; i<5; i=i+1) begin
            raw_response = enroll_data;
            vote_round = i;
            vote_valid = 1;
            #20 vote_valid = 0;
            #20;
        end
        ecc_start = 1;
        #20 ecc_start = 0;
        wait(ecc_done);
        
        $display("Enroll done. Helper data: %x", helper_data_out);
        helper_data = helper_data_out; // save for operate phase

        #50;
        // OPERATE MODE (inject single bit error)
        mode = 0; // 0 = OPERATE
        // flip bit 0
        raw_response = enroll_data ^ 256'h1;
        for (i=0; i<5; i=i+1) begin
            vote_round = i;
            vote_valid = 1;
            #20 vote_valid = 0;
            #20;
        end
        ecc_start = 1;
        #20 ecc_start = 0;
        wait(ecc_done);
        
        $display("Operate 1 done. Fail=%b, Key=%x", ecc_fail, key);

        #50;
        // OPERATE MODE (inject double bit error to trigger fail)
        // flip bits 0 and 1
        raw_response = enroll_data ^ 256'h3;
        for (i=0; i<5; i=i+1) begin
            vote_round = i;
            vote_valid = 1;
            #20 vote_valid = 0;
            #20;
        end
        ecc_start = 1;
        #20 ecc_start = 0;
        wait(ecc_done);
        
        $display("Operate 2 (2 errs) done. Fail=%b", ecc_fail);

        #50 $finish;
    end

endmodule
