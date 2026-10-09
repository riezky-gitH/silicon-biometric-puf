// ============================================================================
// error_correction.v — 3-Stage PUF Key Stabilization
// Silicon-Biometric Secure Element | DE10-Nano
// ============================================================================
// Stage 1: Reliability masking (256 → 195 bits via external mask)
// Stage 2: Temporal majority voting (5 rounds, bit-wise 3-of-5)
// Stage 3: Hamming(15,11) ECC — 13 blocks, 52-bit helper data
// Output:  128-bit key from 143 corrected data bits (XOR-fold)
// ============================================================================
`timescale 1ns/1ps

module error_correction (
    input  wire         clk,
    input  wire         rst_n,
    // PUF response input
    input  wire [255:0] raw_response,
    input  wire [255:0] mask,
    input  wire [51:0]  helper_data,
    // voting control
    input  wire [2:0]   vote_round,  // 0..4
    input  wire         vote_valid,  // pulse: current round data ready
    // correction control
    input  wire         ecc_start,   // pulse: begin Hamming correction
    input  wire         mode,        // 0=OPERATE, 1=ENROLL
    // outputs
    output reg  [127:0] key,
    output reg          key_valid,
    output reg          ecc_fail,
    output reg          ecc_done,
    output reg  [51:0]  helper_data_out
);

    // =====================================================================
    // STAGE 1 — Reliability Masking (combinational)
    // =====================================================================
    // Select bits where mask[i]=1, pack into 195-bit vector.
    // Fixed bit-select: generates a priority encoder network.
    reg [194:0] masked_bits;
    integer mi, mj;
    always @(*) begin
        masked_bits = 195'b0;
        mj = 0;
        for (mi = 0; mi < 256; mi = mi + 1) begin
            if (mask[mi] && mj < 195) begin
                masked_bits[mj] = raw_response[mi];
                mj = mj + 1;
            end
        end
    end

    // =====================================================================
    // STAGE 2 — Majority Voting (sequential, across 5 rounds)
    // =====================================================================
    // Accumulate vote counts per bit across 5 measurement rounds.
    // After round 4: majority = (count >= 3) ? 1 : 0
    reg [2:0] vote_cnt [0:194];
    reg [194:0] voted_bits;
    reg         voting_done;
    integer vi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (vi = 0; vi < 195; vi = vi + 1)
                vote_cnt[vi] <= 3'd0;
            voted_bits  <= 195'd0;
            voting_done <= 1'b0;
        end else if (vote_valid) begin
            voting_done <= 1'b0;
            if (vote_round == 3'd0) begin
                // first round: initialize counts
                for (vi = 0; vi < 195; vi = vi + 1)
                    vote_cnt[vi] <= {2'b0, masked_bits[vi]};
            end else begin
                // accumulate
                for (vi = 0; vi < 195; vi = vi + 1)
                    if (masked_bits[vi])
                        vote_cnt[vi] <= vote_cnt[vi] + 1'b1;
            end

            if (vote_round == 3'd4) begin
                // finalize: majority decision
                for (vi = 0; vi < 195; vi = vi + 1) begin
                    // count already has rounds 0..3, add current (round 4)
                    voted_bits[vi] <= ((vote_cnt[vi] + masked_bits[vi]) >= 3'd3);
                end
                voting_done <= 1'b1;
            end
        end
    end

    // =====================================================================
    // STAGE 3 — Hamming(15,11) Correction (13 blocks)
    // =====================================================================
    // 195 bits = 13 blocks × 15 bits
    // Each 15-bit block: 11 data bits at positions {3,5,6,7,9,10,11,12,13,14,15}
    //                     4 parity bits at positions {1,2,4,8}
    // Helper data stores the enrollment syndrome (4 bits/block = 52 bits).
    // Reconstruction: syndrome_new XOR helper → error position.

    wire [10:0] block_data  [0:12];  // 11 data bits per block
    wire [3:0]  block_syn   [0:12];  // computed syndrome
    wire [3:0]  err_pos     [0:12];  // error position after XOR with helper
    reg  [10:0] corrected   [0:12];  // corrected data bits
    wire        block_err   [0:12];  // uncorrectable error flag

    genvar b;
    generate
        for (b = 0; b < 13; b = b + 1) begin : hamming_blk
            wire [14:0] blk = voted_bits[b*15 +: 15];

            // Data bit extraction (Hamming positions 3,5,6,7,9,10,11,12,13,14,15)
            // In a 15-bit codeword indexed 1..15:
            //   parity positions: 1, 2, 4, 8
            //   data positions:   3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15
            // Map to 0-indexed blk[0..14] = positions 1..15
            assign block_data[b] = {blk[14], blk[13], blk[12], blk[11],
                                    blk[10], blk[9],  blk[8],  blk[6],
                                    blk[5],  blk[4],  blk[2]};

            // Syndrome computation
            // p1 checks positions with bit 0 set: 1,3,5,7,9,11,13,15
            wire s1 = blk[0]^blk[2]^blk[4]^blk[6]^blk[8]^blk[10]^blk[12]^blk[14];
            // p2 checks positions with bit 1 set: 2,3,6,7,10,11,14,15
            wire s2 = blk[1]^blk[2]^blk[5]^blk[6]^blk[9]^blk[10]^blk[13]^blk[14];
            // p4 checks positions with bit 2 set: 4,5,6,7,12,13,14,15
            wire s4 = blk[3]^blk[4]^blk[5]^blk[6]^blk[11]^blk[12]^blk[13]^blk[14];
            // p8 checks positions with bit 3 set: 8,9,10,11,12,13,14,15
            wire s8 = blk[7]^blk[8]^blk[9]^blk[10]^blk[11]^blk[12]^blk[13]^blk[14];

            assign block_syn[b] = {s8, s4, s2, s1};

            // During enrollment: syndrome IS the helper data
            assign helper_data_out[b*4 +: 4] = block_syn[b];

            // During reconstruction: XOR with stored helper → error position
            assign err_pos[b] = block_syn[b] ^ helper_data[b*4 +: 4];

            // Correction: flip the bit at error position (if any)
            // err_pos is 1-indexed position in the 15-bit block
            // Only correct if err_pos points to a data position
            integer ci;
            always @(*) begin
                corrected[b] = block_data[b];
                if (err_pos[b] != 4'd0) begin
                    // Flip the errored bit in the full 15-bit block,
                    // then re-extract data bits. Simplified: map err_pos
                    // to data bit index if it's a data position.
                    case (err_pos[b])
                        4'd3:  corrected[b][0]  = ~block_data[b][0];
                        4'd5:  corrected[b][1]  = ~block_data[b][1];
                        4'd6:  corrected[b][2]  = ~block_data[b][2];
                        4'd7:  corrected[b][3]  = ~block_data[b][3];
                        4'd9:  corrected[b][4]  = ~block_data[b][4];
                        4'd10: corrected[b][5]  = ~block_data[b][5];
                        4'd11: corrected[b][6]  = ~block_data[b][6];
                        4'd12: corrected[b][7]  = ~block_data[b][7];
                        4'd13: corrected[b][8]  = ~block_data[b][8];
                        4'd14: corrected[b][9]  = ~block_data[b][9];
                        4'd15: corrected[b][10] = ~block_data[b][10];
                        default: ; // parity-only error (pos 1,2,4,8), data OK
                    endcase
                end
            end

            // 2-bit error heuristic: overall parity check
            // If err_pos != 0 but overall block parity is even → likely 2-bit error
            wire overall_parity = ^blk;
            assign block_err[b] = (err_pos[b] != 4'd0) && (overall_parity == 1'b0);
        end
    endgenerate

    // =====================================================================
    // Key derivation: 13×11 = 143 data bits → XOR-fold to 128 bits
    // =====================================================================
    wire [142:0] all_data;
    genvar d;
    generate
        for (d = 0; d < 13; d = d + 1) begin : pack
            assign all_data[d*11 +: 11] = corrected[d];
        end
    endgenerate

    // Fold 143 bits → 128: first 128 XOR with remaining 15 bits (padded)
    wire [127:0] folded_key = all_data[127:0] ^ {113'b0, all_data[142:128]};

    // =====================================================================
    // Output registers
    // =====================================================================
    wire any_block_err;
    assign any_block_err = block_err[0]  | block_err[1]  | block_err[2]  |
                           block_err[3]  | block_err[4]  | block_err[5]  |
                           block_err[6]  | block_err[7]  | block_err[8]  |
                           block_err[9]  | block_err[10] | block_err[11] |
                           block_err[12];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key       <= 128'd0;
            key_valid <= 1'b0;
            ecc_fail  <= 1'b0;
            ecc_done  <= 1'b0;
        end else begin
            ecc_done <= 1'b0;
            if (ecc_start && voting_done) begin
                key       <= folded_key;
                key_valid <= ~any_block_err;
                ecc_fail  <= (mode == 1'b0) ? any_block_err : 1'b0;
                ecc_done  <= 1'b1;
            end
        end
    end

endmodule
