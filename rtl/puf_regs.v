// ============================================================================
// puf_regs.v — Avalon-MM Slave Register Interface
// Silicon-Biometric Secure Element | DE10-Nano
// ============================================================================
// Word-addressed (avs_address selects 32-bit words).
// Byte offset = avs_address × 4.
// ============================================================================
`timescale 1ns/1ps

module puf_regs (
    input  wire        clk,
    input  wire        rst_n,
    // Avalon-MM slave
    input  wire [6:0]  avs_address,     // word address (0..21 used)
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire        avs_read,
    output reg  [31:0] avs_readdata,
    // PUF control signals (directly to/from FSM)
    output reg         start_puf,
    output reg         start_auth,
    output wire        lock,
    // PUF status signals
    input  wire        busy,
    input  wire        done,
    input  wire        key_valid,
    input  wire        ecc_fail,
    // raw data readback
    output reg  [7:0]  pair_sel,
    input  wire [17:0] raw_diff,
    // nonce / response
    output wire [127:0] nonce,
    input  wire [127:0] response,
    // mask / helper
    output wire [255:0] mask,
    output wire [51:0]  helper_data,
    input  wire [51:0]  helper_data_in   // from ECC during enrollment
);

    // Word address definitions (byte_offset / 4)
    localparam A_CTRL     = 7'd0,   // 0x00
               A_STATUS   = 7'd1,   // 0x04
               A_PAIR_SEL = 7'd2,   // 0x08
               A_RAW_DIFF = 7'd3,   // 0x0C
               A_NONCE0   = 7'd4,   // 0x10
               A_NONCE1   = 7'd5,   // 0x14
               A_NONCE2   = 7'd6,   // 0x18
               A_NONCE3   = 7'd7,   // 0x1C
               A_RESP0    = 7'd8,   // 0x20
               A_RESP1    = 7'd9,   // 0x24
               A_RESP2    = 7'd10,  // 0x28
               A_RESP3    = 7'd11,  // 0x2C
               A_MASK0    = 7'd12,  // 0x30
               A_MASK1    = 7'd13,  // 0x34
               A_MASK2    = 7'd14,  // 0x38
               A_MASK3    = 7'd15,  // 0x3C
               A_MASK4    = 7'd16,  // 0x40
               A_MASK5    = 7'd17,  // 0x44
               A_MASK6    = 7'd18,  // 0x48
               A_MASK7    = 7'd19,  // 0x4C
               A_HELPER0  = 7'd20,  // 0x50
               A_HELPER1  = 7'd21;  // 0x54

    // --- Register storage ---
    reg         locked;
    reg [31:0]  nonce_r   [0:3];
    reg [31:0]  mask_r    [0:7];
    reg [31:0]  helper_r  [0:1];

    // Output bus mapping
    assign lock  = locked;
    assign nonce = {nonce_r[3], nonce_r[2], nonce_r[1], nonce_r[0]};
    assign mask  = {mask_r[7], mask_r[6], mask_r[5], mask_r[4],
                    mask_r[3], mask_r[2], mask_r[1], mask_r[0]};
    assign helper_data = {helper_r[1][19:0], helper_r[0]};  // 52 bits

    // --- Write logic ---
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_puf  <= 1'b0;
            start_auth <= 1'b0;
            locked     <= 1'b0;
            pair_sel   <= 8'd0;
            for (i = 0; i < 4; i = i + 1) nonce_r[i] <= 32'd0;
            for (i = 0; i < 8; i = i + 1) mask_r[i]  <= 32'd0;
            helper_r[0] <= 32'd0;
            helper_r[1] <= 32'd0;
        end else begin
            // auto-clear command pulses
            start_puf  <= 1'b0;
            start_auth <= 1'b0;

            if (avs_write) begin
                case (avs_address)
                    A_CTRL: begin
                        if (avs_writedata[0])  start_puf  <= 1'b1;
                        if (avs_writedata[1])  start_auth <= 1'b1;
                        if (avs_writedata[31]) locked     <= 1'b1; // sticky
                    end
                    A_PAIR_SEL: if (!locked) pair_sel <= avs_writedata[7:0];
                    A_NONCE0: nonce_r[0] <= avs_writedata;
                    A_NONCE1: nonce_r[1] <= avs_writedata;
                    A_NONCE2: nonce_r[2] <= avs_writedata;
                    A_NONCE3: nonce_r[3] <= avs_writedata;
                    A_MASK0:  mask_r[0]  <= avs_writedata;
                    A_MASK1:  mask_r[1]  <= avs_writedata;
                    A_MASK2:  mask_r[2]  <= avs_writedata;
                    A_MASK3:  mask_r[3]  <= avs_writedata;
                    A_MASK4:  mask_r[4]  <= avs_writedata;
                    A_MASK5:  mask_r[5]  <= avs_writedata;
                    A_MASK6:  mask_r[6]  <= avs_writedata;
                    A_MASK7:  mask_r[7]  <= avs_writedata;
                    A_HELPER0: helper_r[0] <= avs_writedata;
                    A_HELPER1: helper_r[1] <= avs_writedata;
                    default: ;
                endcase
            end
        end
    end

    // --- Read logic ---
    always @(*) begin
        avs_readdata = 32'd0;
        case (avs_address)
            A_STATUS:  avs_readdata = {27'd0, locked, ecc_fail, key_valid, done, busy};
            A_RAW_DIFF: avs_readdata = locked ? 32'd0 : {14'd0, raw_diff};
            A_RESP0:   avs_readdata = response[31:0];
            A_RESP1:   avs_readdata = response[63:32];
            A_RESP2:   avs_readdata = response[95:64];
            A_RESP3:   avs_readdata = response[127:96];
            A_MASK0:   avs_readdata = mask_r[0];
            A_MASK1:   avs_readdata = mask_r[1];
            A_MASK2:   avs_readdata = mask_r[2];
            A_MASK3:   avs_readdata = mask_r[3];
            A_MASK4:   avs_readdata = mask_r[4];
            A_MASK5:   avs_readdata = mask_r[5];
            A_MASK6:   avs_readdata = mask_r[6];
            A_MASK7:   avs_readdata = mask_r[7];
            A_HELPER0: avs_readdata = helper_r[0];
            A_HELPER1: avs_readdata = helper_r[1];
            default:   avs_readdata = 32'd0;
        endcase
    end

endmodule
