`timescale 1ns/1ps

// tb_puf_top.v
// top level testbench checking avalon interface and locks
module tb_puf_top;

    reg clk;
    reg rst_n;
    reg [3:0] sw;
    wire [7:0] led;
    reg [6:0] avs_address;
    reg avs_write;
    reg [31:0] avs_writedata;
    reg avs_read;
    wire [31:0] avs_readdata;

    puf_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw),
        .led(led),
        .avs_address(avs_address),
        .avs_write(avs_write),
        .avs_writedata(avs_writedata),
        .avs_read(avs_read),
        .avs_readdata(avs_readdata)
    );

    always #10 clk = ~clk;

    task write_reg(input [6:0] addr, input [31:0] data);
    begin
        avs_address = addr;
        avs_writedata = data;
        avs_write = 1;
        #20;
        avs_write = 0;
        #20;
    end
    endtask

    task read_reg(input [6:0] addr);
    begin
        avs_address = addr;
        avs_read = 1;
        #20;
        avs_read = 0;
        #20;
    end
    endtask

    integer i;

    initial begin
        $dumpfile("tb_puf_top.vcd");
        $dumpvars(0, tb_puf_top);

        clk = 0;
        rst_n = 0;
        sw = 0;
        avs_address = 0;
        avs_write = 0;
        avs_writedata = 0;
        avs_read = 0;

        #100 rst_n = 1;
        #20;

        // write masks
        for (i=12; i<=19; i=i+1) begin
            write_reg(i, 32'hFFFFFFFF);
        end

        // write helpers
        write_reg(20, 32'h12345678);
        write_reg(21, 32'h9ABCDEF0);

        // read status
        read_reg(1);
        $display("Status: %x (expect not busy)", avs_readdata);

        // start PUF
        write_reg(0, 32'h1);
        
        // wait a bit, then activate lock
        #200;
        write_reg(0, 32'h80000000); // lock
        
        read_reg(1);
        $display("Status after lock: %x", avs_readdata);

        read_reg(3); // raw diff
        $display("RAW DIFF (expect 0 if locked): %x", avs_readdata);

        // start auth
        write_reg(4, 32'h11223344);
        write_reg(0, 32'h2);

        #500 $finish;
    end

endmodule
