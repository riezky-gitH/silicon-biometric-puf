// ============================================================================
// control_fsm.v — Master Sequencer
// Silicon-Biometric Secure Element | DE10-Nano
// ============================================================================
// State flow: IDLE → MEASURE → VOTE → CORRECT → KEY_READY → AES → DONE
// Handles 16 groups × 5 voting rounds = 80 measurement cycles total.
// Both START_PUF and START_AUTH trigger the full PUF pipeline.
// ============================================================================
`timescale 1ns/1ps

module control_fsm (
    input  wire        clk,
    input  wire        rst_n,
    // commands from register interface
    input  wire        start_puf,
    input  wire        start_auth,
    input  wire        lock,
    // handshake signals from datapath
    input  wire        meas_done,     // from measure_unit (all 16 done)
    input  wire        ecc_done,
    input  wire        ecc_fail,
    input  wire        aes_done,
    // control outputs
    output reg  [2:0]  state,
    output reg         meas_start,    // pulse to start measurement cycle
    output reg  [3:0]  pair_group,    // current group 0..15
    output reg  [2:0]  vote_round,    // current voting round 0..4
    output reg         ecc_start,
    output reg         aes_start,
    output reg         busy,
    output reg         done,
    output reg         key_valid_out
);

    localparam S_IDLE      = 3'd0,
               S_MEASURE   = 3'd1,
               S_VOTE      = 3'd2,
               S_CORRECT   = 3'd3,
               S_KEY_READY = 3'd4,
               S_AES       = 3'd5,
               S_DONE      = 3'd6;

    reg auth_mode;  // 1 = authentication requested (continue to AES)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            meas_start    <= 1'b0;
            pair_group    <= 4'd0;
            vote_round    <= 3'd0;
            ecc_start     <= 1'b0;
            aes_start     <= 1'b0;
            busy          <= 1'b0;
            done          <= 1'b0;
            key_valid_out <= 1'b0;
            auth_mode     <= 1'b0;
        end else begin
            // default: clear single-cycle pulses
            meas_start <= 1'b0;
            ecc_start  <= 1'b0;
            aes_start  <= 1'b0;
            done       <= 1'b0;

            case (state)
                // -------------------------------------------------
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start_puf || start_auth) begin
                        state      <= S_MEASURE;
                        busy       <= 1'b1;
                        pair_group <= 4'd0;
                        vote_round <= 3'd0;
                        auth_mode  <= start_auth;
                        meas_start <= 1'b1;
                        key_valid_out <= 1'b0;
                    end
                end

                // -------------------------------------------------
                S_MEASURE: begin
                    if (meas_done) begin
                        if (pair_group == 4'd15) begin
                            // all 16 groups measured for this vote round
                            state <= S_VOTE;
                        end else begin
                            pair_group <= pair_group + 1'b1;
                            meas_start <= 1'b1;
                        end
                    end
                end

                // -------------------------------------------------
                S_VOTE: begin
                    if (vote_round == 3'd4) begin
                        // 5 rounds complete → run ECC
                        state     <= S_CORRECT;
                        ecc_start <= 1'b1;
                    end else begin
                        // next voting round: remeasure all groups
                        vote_round <= vote_round + 1'b1;
                        pair_group <= 4'd0;
                        meas_start <= 1'b1;
                        state      <= S_MEASURE;
                    end
                end

                // -------------------------------------------------
                S_CORRECT: begin
                    if (ecc_done) begin
                        if (ecc_fail) begin
                            state <= S_DONE;
                        end else begin
                            key_valid_out <= 1'b1;
                            state         <= S_KEY_READY;
                        end
                    end
                end

                // -------------------------------------------------
                S_KEY_READY: begin
                    if (auth_mode) begin
                        aes_start <= 1'b1;
                        state     <= S_AES;
                    end else begin
                        state <= S_DONE;
                    end
                end

                // -------------------------------------------------
                S_AES: begin
                    if (aes_done)
                        state <= S_DONE;
                end

                // -------------------------------------------------
                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
