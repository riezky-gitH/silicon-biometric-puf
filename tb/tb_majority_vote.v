`timescale 1ns/1ps

// tb_majority_vote.v
// testing majority voting logic in error correction
module tb_majority_vote;

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

    initial begin
        $dumpfile("tb_majority_vote.vcd");
        $dumpvars(0, tb_majority_vote);

        clk = 0;
        rst_n = 0;
        raw_response = 0;
        mask = {256{1'b1}}; // all reliable
        helper_data = 0;
        vote_round = 0;
        vote_valid = 0;
        ecc_start = 0;
        mode = 0; // enroll for now

        #50 rst_n = 1;
        #20;

        // feed 5 rounds of data with noise
        // correct response is all 1s for bits 0-15 just to test
        
        // round 0
        raw_response = 256'hFFFF;
        vote_round = 0;
        vote_valid = 1;
        #20 vote_valid = 0;
        #20;
        
        // round 1 (bit 0 flipped)
        raw_response = 256'hFFFE;
        vote_round = 1;
        vote_valid = 1;
        #20 vote_valid = 0;
        #20;
        
        // round 2 (bit 1 flipped)
        raw_response = 256'hFFFD;
        vote_round = 2;
        vote_valid = 1;
        #20 vote_valid = 0;
        #20;

        // round 3
        raw_response = 256'hFFFF;
        vote_round = 3;
        vote_valid = 1;
        #20 vote_valid = 0;
        #20;

        // round 4
        raw_response = 256'hFFFF;
        vote_round = 4;
        vote_valid = 1;
        #20 vote_valid = 0;
        #20;

        ecc_start = 1;
        #20 ecc_start = 0;

        wait(ecc_done);
        $display("done. key=%x", key);
        
        #50 $finish;
    end

endmodule
