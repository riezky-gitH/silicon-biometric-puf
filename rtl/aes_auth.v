// ============================================================================
// aes_auth.v — AES-128 Authentication Wrapper
// Silicon-Biometric Secure Element | DE10-Nano
// ============================================================================
// Wraps secworks/aes core. Key flows directly from ECC output —
// never exposed to any readable register. Encrypt-only mode.
// ============================================================================
`timescale 1ns/1ps

module aes_auth (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] key,
    input  wire         key_valid,
    input  wire [127:0] nonce,
    input  wire         start,
    output reg  [127:0] response,
    output reg          done
);

    // FSM for AES sequencing
    localparam S_IDLE    = 3'd0,
               S_INIT   = 3'd1,   // load key
               S_WAIT_K = 3'd2,   // wait for key expansion
               S_LOAD   = 3'd3,   // load plaintext
               S_WAIT_E = 3'd4,   // wait for encryption
               S_DONE   = 3'd5;

    reg [2:0] state;
    reg       core_init, core_next;

    // secworks/aes core interface signals
    wire       core_ready;
    wire       core_valid;
    wire [127:0] core_result;

    // Instantiate secworks/aes core
    // Key for AES-128: use upper 128 bits of 256-bit key port
    aes_core u_aes (
        .clk       (clk),
        .reset_n   (rst_n),
        .encdec    (1'b1),              // encrypt only
        .init      (core_init),
        .next      (core_next),
        .ready     (core_ready),
        .key       ({key, 128'd0}),     // AES-128: key in upper half
        .keylen    (1'b0),              // 0 = 128-bit key
        .block     (nonce),
        .result    (core_result),
        .result_valid (core_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            done      <= 1'b0;
            response  <= 128'd0;
            core_init <= 1'b0;
            core_next <= 1'b0;
        end else begin
            done      <= 1'b0;
            core_init <= 1'b0;
            core_next <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start && key_valid) begin
                        core_init <= 1'b1;
                        state     <= S_INIT;
                    end
                end

                S_INIT: state <= S_WAIT_K;

                S_WAIT_K: begin
                    if (core_ready) begin
                        core_next <= 1'b1;
                        state     <= S_LOAD;
                    end
                end

                S_LOAD: state <= S_WAIT_E;

                S_WAIT_E: begin
                    if (core_valid) begin
                        response <= core_result;
                        done     <= 1'b1;
                        state    <= S_DONE;
                    end
                end

                S_DONE: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
