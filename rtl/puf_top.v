// ============================================================================
// puf_top.v — Top-Level Integration
// Silicon-Biometric Secure Element | DE10-Nano
// ============================================================================
`timescale 1ns/1ps

module puf_top (
    input  wire        clk,         // CLOCK_50
    input  wire        rst_n,       // KEY[0], active-low
    input  wire [3:0]  sw,          // SW[3:0]
    output wire [7:0]  led,         // LED[7:0]
    // Avalon-MM slave (directly exposed)
    input  wire [6:0]  avs_address,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire        avs_read,
    output wire [31:0] avs_readdata
);

    // SW[0]: 1=ENROLL, 0=OPERATE
    wire enroll_mode = sw[0];

    // --- Internal wires: FSM ↔ datapath ----------------------
    wire [2:0] fsm_state;
    wire       fsm_busy, fsm_done, fsm_key_valid;
    wire       meas_start;
    wire [3:0] pair_group;
    wire [2:0] vote_round;
    wire       ecc_start, aes_start;

    // --- Internal wires: register ↔ FSM ----------------------
    wire       cmd_start_puf, cmd_start_auth, lock;
    wire [7:0] pair_sel;
    wire [127:0] nonce, aes_response;
    wire [255:0] mask_vec;
    wire [51:0]  helper_to_ecc, helper_from_ecc;

    // --- Internal wires: datapath ----------------------------
    wire [15:0] osc_a, osc_b;
    wire [127:0] puf_key;
    wire         puf_key_valid, ecc_fail_flag, ecc_done_flag;
    wire         aes_done_flag;

    // --- Measurement unit outputs ----------------------------
    wire [15:0] mu_done, mu_valid, mu_result;
    wire [17:0] mu_raw_diff [0:15];
    wire [15:0] mu_ro_en;
    wire        all_mu_done = &mu_done;

    // Combined RO enable (active when any measure unit enables)
    wire        ro_en_combined = |mu_ro_en;

    // =========================================================
    // RO Array
    // =========================================================
    ro_array u_ro_array (
        .clk       (clk),
        .rst_n     (rst_n),
        .group_sel (pair_group),
        .en        (ro_en_combined),
        .osc_a     (osc_a),
        .osc_b     (osc_b)
    );

    // =========================================================
    // 16× Measurement Units
    // =========================================================
    // Collect 256-bit response in a register array
    reg [255:0] raw_response;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw_response <= 256'd0;
        end else begin
            // Latch results when measurement units complete
            if (all_mu_done) begin : latch_results
                integer k;
                for (k = 0; k < 16; k = k + 1)
                    raw_response[{pair_group, k[3:0]}] <= mu_result[k];
            end
        end
    end

    // Latch raw counter diff for selected pair during enrollment
    reg [17:0] latched_raw_diff;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_raw_diff <= 18'd0;
        end else if (all_mu_done && (pair_group == pair_sel[7:4])) begin
            latched_raw_diff <= mu_raw_diff[pair_sel[3:0]];
        end
    end
    wire [17:0] selected_raw_diff = latched_raw_diff;

    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_mu
            measure_unit u_mu (
                .clk        (clk),
                .rst_n      (rst_n),
                .osc_a      (osc_a[g]),
                .osc_b      (osc_b[g]),
                .start      (meas_start),
                .ro_en      (mu_ro_en[g]),
                .done       (mu_done[g]),
                .result_bit (mu_result[g]),
                .raw_diff   (mu_raw_diff[g]),
                .valid      (mu_valid[g])
            );
        end
    endgenerate

    // =========================================================
    // Error Correction
    // =========================================================
    error_correction u_ecc (
        .clk             (clk),
        .rst_n           (rst_n),
        .raw_response    (raw_response),
        .mask            (mask_vec),
        .helper_data     (helper_to_ecc),
        .vote_round      (vote_round),
        .vote_valid      (all_mu_done),
        .ecc_start       (ecc_start),
        .mode            (enroll_mode),
        .key             (puf_key),
        .key_valid       (puf_key_valid),
        .ecc_fail        (ecc_fail_flag),
        .ecc_done        (ecc_done_flag),
        .helper_data_out (helper_from_ecc)
    );

    // =========================================================
    // AES-128 Authentication
    // =========================================================
    aes_auth u_aes (
        .clk       (clk),
        .rst_n     (rst_n),
        .key       (puf_key),
        .key_valid (puf_key_valid),
        .nonce     (nonce),
        .start     (aes_start),
        .response  (aes_response),
        .done      (aes_done_flag)
    );

    // =========================================================
    // Control FSM
    // =========================================================
    control_fsm u_fsm (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_puf     (cmd_start_puf),
        .start_auth    (cmd_start_auth),
        .lock          (lock),
        .meas_done     (all_mu_done),
        .ecc_done      (ecc_done_flag),
        .ecc_fail      (ecc_fail_flag),
        .aes_done      (aes_done_flag),
        .state         (fsm_state),
        .meas_start    (meas_start),
        .pair_group    (pair_group),
        .vote_round    (vote_round),
        .ecc_start     (ecc_start),
        .aes_start     (aes_start),
        .busy          (fsm_busy),
        .done          (fsm_done),
        .key_valid_out (fsm_key_valid)
    );

    // =========================================================
    // Avalon-MM Registers
    // =========================================================
    puf_regs u_regs (
        .clk            (clk),
        .rst_n          (rst_n),
        .avs_address    (avs_address),
        .avs_write      (avs_write),
        .avs_writedata  (avs_writedata),
        .avs_read       (avs_read),
        .avs_readdata   (avs_readdata),
        .start_puf      (cmd_start_puf),
        .start_auth     (cmd_start_auth),
        .lock           (lock),
        .busy           (fsm_busy),
        .done           (fsm_done),
        .key_valid      (puf_key_valid),
        .ecc_fail       (ecc_fail_flag),
        .pair_sel       (pair_sel),
        .raw_diff       (selected_raw_diff),
        .nonce          (nonce),
        .response       (aes_response),
        .mask           (mask_vec),
        .helper_data    (helper_to_ecc),
        .helper_data_in (helper_from_ecc)
    );

    // =========================================================
    // LED indicators
    // =========================================================
    assign led[0] = fsm_busy;
    assign led[1] = fsm_done;
    assign led[2] = puf_key_valid;
    assign led[3] = lock;
    assign led[4] = ecc_fail_flag;
    assign led[5] = 1'b0;
    assign led[6] = ecc_fail_flag;          // red: ECC error
    assign led[7] = puf_key_valid & ~ecc_fail_flag;  // green: OK

endmodule
