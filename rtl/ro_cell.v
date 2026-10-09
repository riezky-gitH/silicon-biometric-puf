// ============================================================================
// ro_cell.v — Ring Oscillator Cell
// Silicon-Biometric Secure Element on Cyclone V SE (DE10-Nano)
// ============================================================================
`timescale 1ns/1ps

module ro_cell #(
    parameter STAGES = 7
)(
    input  wire en,
    output wire osc
);
    (* keep *) wire [STAGES-1:0] n;

    assign n[0] = ~(en & n[STAGES-1]);

    genvar i;
    generate
        for (i = 1; i < STAGES; i = i + 1) begin : inv
            assign n[i] = ~n[i-1];
        end
    endgenerate

    assign osc = n[STAGES-1];
endmodule
