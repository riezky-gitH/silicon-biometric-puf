// ============================================================================
// measure_unit.v — Frequency Measurement Unit (×16 parallel)
// Silicon-Biometric Secure Element | DE10-Nano
// ============================================================================
// Async counters clocked directly by RO outputs. RO disabled before
// counter readout to guarantee static values (no CDC metastability).
// False path declared in SDC for cnt_a/cnt_b → latched domain.
// ============================================================================
`timescale 1ns/1ps

module measure_unit (
    input  wire        clk,        // 50 MHz system clock
    input  wire        rst_n,
    input  wire        osc_a,      // RO_A oscillation
    input  wire        osc_b,      // RO_B oscillation
    input  wire        start,      // pulse to begin measurement
    output reg         ro_en,      // gating enable to RO pair
    output reg         done,       // single-cycle pulse when complete
    output wire        result_bit, // 1 if cnt_a > cnt_b
    output wire [17:0] raw_diff,   // |cnt_a - cnt_b|
    output reg         valid       // latched result is available
);

    // 2^13 = 8192 cycles @ 50 MHz ≈ 164 µs measurement window
    localparam [12:0] WINDOW_MAX = 13'd8191;
    localparam [1:0]  SETTLE_MAX = 2'd2;

    localparam S_IDLE    = 3'd0,
               S_RESET   = 3'd1,
               S_MEASURE = 3'd2,
               S_SETTLE  = 3'd3,
               S_LATCH   = 3'd4,
               S_DONE    = 3'd5;

    reg [2:0]  state;
    reg [12:0] window_cnt;
    reg [1:0]  settle_cnt;

    // --- Async counters (clocked by RO outputs directly) ------
    reg        cnt_rst;
    reg [17:0] cnt_a, cnt_b;

    always @(posedge osc_a or posedge cnt_rst) begin
        if (cnt_rst) cnt_a <= 18'd0;
        else         cnt_a <= cnt_a + 1'b1;
    end

    always @(posedge osc_b or posedge cnt_rst) begin
        if (cnt_rst) cnt_b <= 18'd0;
        else         cnt_b <= cnt_b + 1'b1;
    end

    // --- Latched counter values (sampled after RO stops) ------
    reg [17:0] lat_a, lat_b;

    assign result_bit = (lat_a > lat_b);
    assign raw_diff   = (lat_a >= lat_b) ? (lat_a - lat_b)
                                          : (lat_b - lat_a);

    // --- Control FSM ------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            ro_en      <= 1'b0;
            done       <= 1'b0;
            valid      <= 1'b0;
            cnt_rst    <= 1'b1;
            window_cnt <= 13'd0;
            settle_cnt <= 2'd0;
            lat_a      <= 18'd0;
            lat_b      <= 18'd0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        cnt_rst <= 1'b1;
                        valid   <= 1'b0;
                        state   <= S_RESET;
                    end
                end

                S_RESET: begin
                    cnt_rst    <= 1'b0;
                    ro_en      <= 1'b1;
                    window_cnt <= 13'd0;
                    state      <= S_MEASURE;
                end

                S_MEASURE: begin
                    if (window_cnt == WINDOW_MAX) begin
                        ro_en      <= 1'b0;   // stop RO first
                        settle_cnt <= 2'd0;
                        state      <= S_SETTLE;
                    end else begin
                        window_cnt <= window_cnt + 1'b1;
                    end
                end

                S_SETTLE: begin
                    if (settle_cnt == SETTLE_MAX) begin
                        lat_a <= cnt_a;  // counters are static now
                        lat_b <= cnt_b;
                        state <= S_LATCH;
                    end else begin
                        settle_cnt <= settle_cnt + 1'b1;
                    end
                end

                S_LATCH: begin
                    valid <= 1'b1;
                    done  <= 1'b1;
                    state <= S_DONE;
                end

                S_DONE: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
