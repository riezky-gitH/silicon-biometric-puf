// ============================================================================
// Silicon-Biometric Secure Element — Enrollment Application
// Runs on HPS (ARM Cortex-A9, Linux) on DE10-Nano
// Team: Ruang Circuit - PENS
// PERURI Chip Hackathon 2026
// ============================================================================
//
// Enrollment procedure (executed once at a trusted facility):
//   1. Measure raw counter difference for each of 256 RO pairs (repeated)
//   2. Rank pairs by stability (|diff| magnitude)
//   3. Select 195 most stable pairs → generate 256-bit reliability mask
//   4. Compute Hamming(15,11) helper data (52 bits)
//   5. Write mask and helper data to FPGA registers
//   6. Trigger PUF key reconstruction, record the golden key
//   7. Activate hardware LOCK (irreversible)
//
// Compile: arm-linux-gnueabihf-gcc -Wall -O2 -o puf_enroll puf_enroll.c
// Usage:   sudo ./puf_enroll
// ============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include "puf_driver.h"

// Number of repeated measurements per pair for stability analysis
#define MEASURE_REPEATS     10
#define ENROLL_DATA_FILE    "enroll_data.bin"

// ---------------------------------------------------------------------------
// Pair stability record
// ---------------------------------------------------------------------------
typedef struct {
    uint16_t index;         // pair index 0..255
    uint32_t avg_diff;      // average |counter_a - counter_b|
    uint32_t min_diff;      // minimum difference across repeats
    uint8_t  bit_value;     // dominant bit value (majority)
} pair_info_t;

// Compare function for qsort: descending by min_diff (most stable first)
static int cmp_pair_stability(const void *a, const void *b) {
    const pair_info_t *pa = (const pair_info_t *)a;
    const pair_info_t *pb = (const pair_info_t *)b;
    if (pb->min_diff > pa->min_diff) return 1;
    if (pb->min_diff < pa->min_diff) return -1;
    return 0;
}

// ---------------------------------------------------------------------------
// Main enrollment routine
// ---------------------------------------------------------------------------
int main(int argc, char *argv[]) {
    printf("============================================\n");
    printf("  Silicon-Biometric PUF — Enrollment\n");
    printf("  Team Ruang Circuit — PENS\n");
    printf("============================================\n\n");

    // --- Open /dev/mem and map Lightweight Bridge ---
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("[ERROR] Cannot open /dev/mem (run as root)");
        return EXIT_FAILURE;
    }

    void *lw_base = mmap(NULL, LW_BRIDGE_SPAN, PROT_READ | PROT_WRITE,
                         MAP_SHARED, fd, LW_BRIDGE_BASE);
    if (lw_base == MAP_FAILED) {
        perror("[ERROR] mmap failed");
        close(fd);
        return EXIT_FAILURE;
    }

    void *puf = lw_base;   // PUF registers start at offset 0

    // Check if already locked
    if (puf_is_locked(puf)) {
        printf("[WARNING] Hardware is already LOCKED. Enrollment aborted.\n");
        munmap(lw_base, LW_BRIDGE_SPAN);
        close(fd);
        return EXIT_FAILURE;
    }

    // --- Step 1: Measure all 256 pairs repeatedly ---
    printf("[1/7] Measuring %d RO pairs (%d repeats each)...\n",
           NUM_RO_PAIRS, MEASURE_REPEATS);

    pair_info_t pairs[NUM_RO_PAIRS];
    memset(pairs, 0, sizeof(pairs));

    for (int p = 0; p < NUM_RO_PAIRS; p++) {
        pairs[p].index = (uint16_t)p;
        uint32_t sum_diff = 0;
        uint32_t min_d = UINT32_MAX;
        int ones = 0;

        for (int r = 0; r < MEASURE_REPEATS; r++) {
            // Select pair
            PUF_WRITE(puf, REG_PAIR_SEL, (uint32_t)p);

            // Trigger PUF measurement
            PUF_WRITE(puf, REG_CTRL, CTRL_START_PUF);
            puf_wait_done(puf);

            // Read raw counter difference
            uint32_t raw = PUF_READ(puf, REG_RAW_DIFF);
            uint32_t diff = raw & 0x3FFFF; // 18-bit value

            sum_diff += diff;
            if (diff < min_d) min_d = diff;

            // Determine bit value (sign of difference is encoded in result)
            // For enrollment we count how many times bit = 1
            uint32_t status = PUF_READ(puf, REG_STATUS);
            if (status & STATUS_KEY_OK) ones++;
        }

        pairs[p].avg_diff = sum_diff / MEASURE_REPEATS;
        pairs[p].min_diff = min_d;
        pairs[p].bit_value = (ones >= (MEASURE_REPEATS / 2 + 1)) ? 1 : 0;

        if ((p + 1) % 32 == 0) {
            printf("  ... measured %d/%d pairs\n", p + 1, NUM_RO_PAIRS);
        }
    }
    printf("  Measurement complete.\n\n");

    // --- Step 2: Rank pairs by stability ---
    printf("[2/7] Ranking pairs by stability (min |diff|)...\n");
    qsort(pairs, NUM_RO_PAIRS, sizeof(pair_info_t), cmp_pair_stability);

    printf("  Top-5 most stable pairs:\n");
    for (int i = 0; i < 5 && i < NUM_RO_PAIRS; i++) {
        printf("    Pair %3d: avg_diff=%5u  min_diff=%5u\n",
               pairs[i].index, pairs[i].avg_diff, pairs[i].min_diff);
    }
    printf("  Bottom-5 least stable pairs:\n");
    for (int i = NUM_RO_PAIRS - 5; i < NUM_RO_PAIRS; i++) {
        printf("    Pair %3d: avg_diff=%5u  min_diff=%5u\n",
               pairs[i].index, pairs[i].avg_diff, pairs[i].min_diff);
    }
    printf("\n");

    // --- Step 3: Generate 256-bit reliability mask ---
    printf("[3/7] Generating reliability mask (selecting %d most stable)...\n",
           MASK_RELIABLE_BITS);

    uint32_t mask[NUM_MASK_REGS];
    memset(mask, 0, sizeof(mask));

    for (int i = 0; i < MASK_RELIABLE_BITS && i < NUM_RO_PAIRS; i++) {
        uint16_t idx = pairs[i].index;
        mask[idx / 32] |= (1U << (idx % 32));
    }

    int mask_ones = 0;
    for (int w = 0; w < NUM_MASK_REGS; w++) {
        for (int b = 0; b < 32; b++) {
            if (mask[w] & (1U << b)) mask_ones++;
        }
    }
    printf("  Mask has %d reliable bits set (expected %d).\n\n",
           mask_ones, MASK_RELIABLE_BITS);

    // --- Step 4: Compute Hamming(15,11) helper data ---
    printf("[4/7] Computing Hamming(15,11) helper data...\n");

    // Extract 195 reliable bits in order
    uint8_t reliable_bits[MASK_RELIABLE_BITS];
    int rbi = 0;
    for (int i = 0; i < NUM_RO_PAIRS && rbi < MASK_RELIABLE_BITS; i++) {
        // Find the pair with this original index among stable pairs
        for (int j = 0; j < MASK_RELIABLE_BITS; j++) {
            if (pairs[j].index == i) {
                reliable_bits[rbi++] = pairs[j].bit_value;
                break;
            }
        }
    }

    // 195 bits → 13 blocks of 15 bits
    // Compute 4-bit syndrome for each block (must match error_correction.v)
    // Hardware indexes: blk[0..14] = Hamming positions 1..15
    // Syndrome bits check positions with corresponding bit set:
    //   s1: positions 1,3,5,7,9,11,13,15 → blk[0],blk[2],blk[4],blk[6],blk[8],blk[10],blk[12],blk[14]
    //   s2: positions 2,3,6,7,10,11,14,15 → blk[1],blk[2],blk[5],blk[6],blk[9],blk[10],blk[13],blk[14]
    //   s4: positions 4,5,6,7,12,13,14,15 → blk[3],blk[4],blk[5],blk[6],blk[11],blk[12],blk[13],blk[14]
    //   s8: positions 8,9,10,11,12,13,14,15 → blk[7],blk[8],blk[9],blk[10],blk[11],blk[12],blk[13],blk[14]
    uint32_t helper[NUM_HELPER_REGS];
    memset(helper, 0, sizeof(helper));

    for (int blk = 0; blk < 13; blk++) {
        uint8_t b[15];
        for (int k = 0; k < 15; k++) {
            int bi = blk * 15 + k;
            b[k] = (bi < MASK_RELIABLE_BITS) ? reliable_bits[bi] : 0;
        }

        uint8_t s1 = b[0]^b[2]^b[4]^b[6]^b[8]^b[10]^b[12]^b[14];
        uint8_t s2 = b[1]^b[2]^b[5]^b[6]^b[9]^b[10]^b[13]^b[14];
        uint8_t s4 = b[3]^b[4]^b[5]^b[6]^b[11]^b[12]^b[13]^b[14];
        uint8_t s8 = b[7]^b[8]^b[9]^b[10]^b[11]^b[12]^b[13]^b[14];

        uint8_t syndrome = (s8 << 3) | (s4 << 2) | (s2 << 1) | s1;
        int bit_offset = blk * 4;
        helper[bit_offset / 32] |= ((uint32_t)syndrome << (bit_offset % 32));
    }

    printf("  Helper data: 0x%08X 0x%08X (52 bits)\n\n", helper[0], helper[1]);

    // --- Step 5: Write mask and helper data to FPGA ---
    printf("[5/7] Writing mask and helper data to FPGA registers...\n");

    for (int i = 0; i < NUM_MASK_REGS; i++) {
        PUF_WRITE(puf, REG_MASK0 + i * 4, mask[i]);
    }
    for (int i = 0; i < NUM_HELPER_REGS; i++) {
        PUF_WRITE(puf, REG_HELPER0 + i * 4, helper[i]);
    }
    printf("  Registers written.\n\n");

    // --- Step 6: Trigger key reconstruction and record golden response ---
    printf("[6/7] Triggering PUF key reconstruction...\n");
    PUF_WRITE(puf, REG_CTRL, CTRL_START_PUF);
    puf_wait_done(puf);

    uint32_t status = PUF_READ(puf, REG_STATUS);
    if (status & STATUS_ECC_FAIL) {
        printf("[ERROR] ECC failure during enrollment! Aborting.\n");
        munmap(lw_base, LW_BRIDGE_SPAN);
        close(fd);
        return EXIT_FAILURE;
    }
    if (!(status & STATUS_KEY_OK)) {
        printf("[ERROR] Key not valid after reconstruction! Aborting.\n");
        munmap(lw_base, LW_BRIDGE_SPAN);
        close(fd);
        return EXIT_FAILURE;
    }
    printf("  Key reconstructed successfully.\n\n");

    // --- Step 7: Activate LOCK and save enrollment data ---
    printf("[7/7] Activating hardware LOCK...\n");
    PUF_WRITE(puf, REG_CTRL, CTRL_LOCK);

    // Verify lock
    status = PUF_READ(puf, REG_STATUS);
    if (!(status & STATUS_LOCKED)) {
        printf("[WARNING] LOCK bit not confirmed!\n");
    } else {
        printf("  Hardware LOCKED. Raw data access is now disabled.\n");
    }

    // Verify RAW_DIFF is zeroed
    uint32_t raw_check = PUF_READ(puf, REG_RAW_DIFF);
    printf("  RAW_DIFF after lock: 0x%08X (expected 0x00000000)\n", raw_check);

    // Save enrollment data to file
    FILE *fp = fopen(ENROLL_DATA_FILE, "wb");
    if (fp) {
        fwrite(mask, sizeof(uint32_t), NUM_MASK_REGS, fp);
        fwrite(helper, sizeof(uint32_t), NUM_HELPER_REGS, fp);
        fclose(fp);
        printf("  Enrollment data saved to '%s'\n", ENROLL_DATA_FILE);
    } else {
        perror("[WARNING] Cannot save enrollment data");
    }

    // Export mask as CSV for analysis
    FILE *csv = fopen("enrollment_mask.csv", "w");
    if (csv) {
        fprintf(csv, "pair_index,reliable,avg_diff,min_diff,bit_value\n");
        for (int i = 0; i < NUM_RO_PAIRS; i++) {
            int is_reliable = (mask[pairs[i].index / 32] >>
                              (pairs[i].index % 32)) & 1;
            fprintf(csv, "%d,%d,%u,%u,%d\n",
                    pairs[i].index, is_reliable,
                    pairs[i].avg_diff, pairs[i].min_diff,
                    pairs[i].bit_value);
        }
        fclose(csv);
        printf("  Pair statistics exported to 'enrollment_mask.csv'\n");
    }

    printf("\n============================================\n");
    printf("  Enrollment COMPLETE\n");
    printf("  This chip now has a unique silicon identity.\n");
    printf("============================================\n");

    // Cleanup
    munmap(lw_base, LW_BRIDGE_SPAN);
    close(fd);
    return EXIT_SUCCESS;
}
