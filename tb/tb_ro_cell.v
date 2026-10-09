`timescale 1ns/1ps

// tb_ro_cell.v
// basic sim for RO and measurement unit
module tb_ro_cell;

    reg clk;
    reg rst_n;
    reg start;
    wire ro_en;
    wire done;
    wire result_bit;
    wire [17:0] raw_diff;
    wire valid;

    // behavioral RO clocks since structural loops won't oscillate in sim
    reg osc_a;
    reg osc_b;

    // the real dut for measure unit
    measure_unit dut (
        .clk(clk),
        .rst_n(rst_n),
        .osc_a(osc_a),
        .osc_b(osc_b),
        .start(start),
        .ro_en(ro_en),
        .done(done),
        .result_bit(result_bit),
        .raw_diff(raw_diff),
        .valid(valid)
    );

    // just to verify it compiles and elaborates
    wire dummy_osc;
    ro_cell #(.STAGES(7)) dummy_ro (
        .en(ro_en),
        .osc(dummy_osc)
    );

    always #10 clk = ~clk; // 50 MHz

    // mock ROs
    always begin
        if (ro_en) #2.1 osc_a = ~osc_a; // slower
        else begin osc_a = 0; #1; end
    end

    always begin
        if (ro_en) #1.9 osc_b = ~osc_b; // faster
        else begin osc_b = 0; #1; end
    end

    initial begin
        $dumpfile("tb_ro_cell.vcd");
        $dumpvars(0, tb_ro_cell);

        clk = 0;
        rst_n = 0;
        start = 0;
        osc_a = 0;
        osc_b = 0;

        #100;
        rst_n = 1;
        #20;
        
        $display("starting measurement...");
        start = 1;
        #20;
        start = 0;

        wait(done);
        #20;

        $display("done. result_bit: %b, diff: %d", result_bit, raw_diff);
        
        // B is faster, so cnt_b > cnt_a, expect result_bit = 0 usually (assuming A>B is 1)
        if (result_bit !== 0) $display("warning: expected result_bit 0");
        if (raw_diff == 0) $display("error: raw_diff is 0");

        #100;
        $finish;
    end

endmodule
