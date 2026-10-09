// ============================================================================
// ro_array.v — Ring Oscillator Array (512 ROs, 256 pairs)
// Silicon-Biometric Secure Element | DE10-Nano
// ============================================================================
// 256 disjoint pairs grouped into 16 banks of 16 pairs each.
// Only the selected bank is active at any time to reduce power.
// All ROs placed inside Logic Lock Region for symmetric routing.
// ============================================================================
`timescale 1ns/1ps

module ro_array (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  group_sel,   // active bank 0..15
    input  wire        en,          // global enable from measure FSM
    output wire [15:0] osc_a,       // 16 RO_A outputs
    output wire [15:0] osc_b        // 16 RO_B outputs
);

    // Per-pair enable: only the selected group of 16 pairs is active
    wire [255:0] pair_en;

    genvar p;
    generate
        for (p = 0; p < 256; p = p + 1) begin : gen_en
            assign pair_en[p] = en & (group_sel == p[7:4]);
        end
    endgenerate

    // 512 RO cells instantiated as 256 pairs
    wire [255:0] ro_out_a, ro_out_b;

    generate
        for (p = 0; p < 256; p = p + 1) begin : gen_pair
            ro_cell ro_a (
                .en  (pair_en[p]),
                .osc (ro_out_a[p])
            );
            ro_cell ro_b (
                .en  (pair_en[p]),
                .osc (ro_out_b[p])
            );
        end
    endgenerate

    // Mux: route the 16 active RO outputs to the measurement units
    genvar m;
    generate
        for (m = 0; m < 16; m = m + 1) begin : gen_mux
            assign osc_a[m] = ro_out_a[{group_sel, m[3:0]}];
            assign osc_b[m] = ro_out_b[{group_sel, m[3:0]}];
        end
    endgenerate

endmodule
