`timescale 1ns/1ps

// tb_aes_auth.v
// testing aes engine wrapper
// NOTE: requires secworks/aes core files in the project
module tb_aes_auth;

    reg clk;
    reg rst_n;
    reg [127:0] key;
    reg key_valid;
    reg [127:0] nonce;
    reg start;
    wire [127:0] response;
    wire done;

    aes_auth dut (
        .clk(clk),
        .rst_n(rst_n),
        .key(key),
        .key_valid(key_valid),
        .nonce(nonce),
        .start(start),
        .response(response),
        .done(done)
    );

    always #10 clk = ~clk;

    initial begin
        $dumpfile("tb_aes_auth.vcd");
        $dumpvars(0, tb_aes_auth);

        clk = 0;
        rst_n = 0;
        key = 128'h000102030405060708090a0b0c0d0e0f;
        key_valid = 0;
        nonce = 128'h00112233445566778899aabbccddeeff; // plaintext
        start = 0;

        #50 rst_n = 1;
        #20;

        key_valid = 1;
        start = 1;
        #20 start = 0;

        wait(done);
        
        $display("AES Done. Response: %x", response);
        if (response === 128'h69c4e0d86a7b0430d8cdb78070b4c55a)
            $display("MATCH: FIPS vector passed");
        else
            $display("FAIL: Mismatch with expected");

        #50 $finish;
    end

endmodule
