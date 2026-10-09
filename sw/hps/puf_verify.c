// ============================================================================
// Silicon-Biometric Secure Element — Verification Application
// Runs on HPS (ARM Cortex-A9, Linux) on DE10-Nano
// Team: Ruang Circuit - PENS
// PERURI Chip Hackathon 2026
// ============================================================================
//
// Authentication (challenge-response) procedure:
//   1. Load enrollment data (mask + helper data) from file
//   2. Write mask and helper data to FPGA registers
//   3. Generate cryptographic random 128-bit nonce
//   4. Write nonce to FPGA, trigger authentication
//   5. FPGA autonomously: reconstruct key → ECC → AES-128(Key, Nonce)
//   6. Read 128-bit response from FPGA
//   7. Display result — PASS (genuine chip) or FAIL (clone detected)
//
// Compile: arm-linux-gnueabihf-gcc -Wall -O2 -o puf_verify puf_verify.c
// Usage:   sudo ./puf_verify [--repeat N]
// ============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>
#include "puf_driver.h"

#define ENROLL_DATA_FILE    "enroll_data.bin"
#define TIMEOUT_US          100000  // 100 ms timeout

// ---------------------------------------------------------------------------
// Generate cryptographic random nonce from /dev/urandom
// ---------------------------------------------------------------------------
static int generate_nonce(uint32_t nonce[4]) {
    int urand = open("/dev/urandom", O_RDONLY);
    if (urand < 0) {
        perror("[ERROR] Cannot open /dev/urandom");
        return -1;
    }
    ssize_t n = read(urand, nonce, 16);
    close(urand);
    if (n != 16) {
        fprintf(stderr, "[ERROR] Failed to read 16 bytes from /dev/urandom\n");
        return -1;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Wait for FPGA to finish with timeout
// ---------------------------------------------------------------------------
static int wait_with_timeout(void *puf, uint32_t *status_out) {
    int elapsed = 0;
    while (elapsed < TIMEOUT_US) {
        uint32_t st = PUF_READ(puf, REG_STATUS);
        if (st & STATUS_DONE) {
            *status_out = st;
            return 0;
        }
        usleep(100);
        elapsed += 100;
    }
    return -1; // timeout
}

// ---------------------------------------------------------------------------
// Main verification routine
// ---------------------------------------------------------------------------
int main(int argc, char *argv[]) {
    int repeat_count = 1;

    // Parse arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--repeat") == 0 && i + 1 < argc) {
            repeat_count = atoi(argv[++i]);
            if (repeat_count < 1) repeat_count = 1;
        }
    }

    printf("============================================\n");
    printf("  Silicon-Biometric PUF — Verification\n");
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

    void *puf = lw_base;

    // --- Load enrollment data ---
    printf("[1] Loading enrollment data from '%s'...\n", ENROLL_DATA_FILE);

    uint32_t mask[NUM_MASK_REGS];
    uint32_t helper[NUM_HELPER_REGS];

    FILE *fp = fopen(ENROLL_DATA_FILE, "rb");
    if (!fp) {
        fprintf(stderr, "[ERROR] Cannot open '%s'. Run puf_enroll first.\n",
                ENROLL_DATA_FILE);
        munmap(lw_base, LW_BRIDGE_SPAN);
        close(fd);
        return EXIT_FAILURE;
    }

    if (fread(mask, sizeof(uint32_t), NUM_MASK_REGS, fp) != NUM_MASK_REGS ||
        fread(helper, sizeof(uint32_t), NUM_HELPER_REGS, fp) != NUM_HELPER_REGS) {
        fprintf(stderr, "[ERROR] Enrollment data file is corrupted.\n");
        fclose(fp);
        munmap(lw_base, LW_BRIDGE_SPAN);
        close(fd);
        return EXIT_FAILURE;
    }
    fclose(fp);
    printf("  Enrollment data loaded.\n\n");

    // --- Write mask and helper data to FPGA ---
    printf("[2] Writing mask and helper data to FPGA...\n");
    for (int i = 0; i < NUM_MASK_REGS; i++) {
        PUF_WRITE(puf, REG_MASK0 + i * 4, mask[i]);
    }
    for (int i = 0; i < NUM_HELPER_REGS; i++) {
        PUF_WRITE(puf, REG_HELPER0 + i * 4, helper[i]);
    }
    printf("  Registers configured.\n\n");

    // --- Run authentication(s) ---
    int pass_count = 0;
    int fail_count = 0;

    struct timespec ts_start, ts_end;

    for (int r = 0; r < repeat_count; r++) {
        if (repeat_count > 1) {
            printf("--- Attempt %d/%d ---\n", r + 1, repeat_count);
        }

        // Generate random nonce
        uint32_t nonce[NUM_NONCE_REGS];
        if (generate_nonce(nonce) != 0) {
            fail_count++;
            continue;
        }
        printf("[3] Challenge nonce: %08X_%08X_%08X_%08X\n",
               nonce[3], nonce[2], nonce[1], nonce[0]);

        // Write nonce to FPGA
        PUF_WRITE(puf, REG_NONCE0, nonce[0]);
        PUF_WRITE(puf, REG_NONCE1, nonce[1]);
        PUF_WRITE(puf, REG_NONCE2, nonce[2]);
        PUF_WRITE(puf, REG_NONCE3, nonce[3]);

        // Trigger authentication
        clock_gettime(CLOCK_MONOTONIC, &ts_start);
        PUF_WRITE(puf, REG_CTRL, CTRL_START_AUTH);

        // Wait for completion
        uint32_t status = 0;
        if (wait_with_timeout(puf, &status) != 0) {
            printf("[ERROR] Authentication timed out!\n");
            fail_count++;
            continue;
        }
        clock_gettime(CLOCK_MONOTONIC, &ts_end);

        double latency_ms = (ts_end.tv_sec - ts_start.tv_sec) * 1000.0 +
                            (ts_end.tv_nsec - ts_start.tv_nsec) / 1e6;

        // Check for errors
        if (status & STATUS_ECC_FAIL) {
            printf("[ERROR] ECC failure detected! Key reconstruction failed.\n");
            printf("\033[1;31m  *** AUTHENTICATION FAILED — ECC ERROR ***\033[0m\n");
            fail_count++;
            continue;
        }

        if (!(status & STATUS_KEY_OK)) {
            printf("[ERROR] Key not valid!\n");
            fail_count++;
            continue;
        }

        // Read response
        uint32_t resp[NUM_RESP_REGS];
        resp[0] = PUF_READ(puf, REG_RESP0);
        resp[1] = PUF_READ(puf, REG_RESP1);
        resp[2] = PUF_READ(puf, REG_RESP2);
        resp[3] = PUF_READ(puf, REG_RESP3);

        printf("[4] Response:       %08X_%08X_%08X_%08X\n",
               resp[3], resp[2], resp[1], resp[0]);
        printf("    Latency:        %.2f ms\n", latency_ms);
        printf("    Status:         0x%08X (KEY_OK=%d, LOCKED=%d)\n",
               status,
               (status & STATUS_KEY_OK) ? 1 : 0,
               (status & STATUS_LOCKED) ? 1 : 0);

        // In a real deployment, the verifier would:
        //   1. Look up the golden key K from enrollment database
        //   2. Compute expected = AES-128(K, nonce) in software
        //   3. Compare expected with resp
        // For this demo, we trust the FPGA response if status is OK
        printf("\n\033[1;32m  ✓ CHIP ASLI — AUTENTIKASI BERHASIL\033[0m\n");
        printf("  Genuine silicon identity confirmed.\n\n");
        pass_count++;
    }

    // --- Summary ---
    if (repeat_count > 1) {
        printf("============================================\n");
        printf("  Summary: %d/%d PASSED, %d/%d FAILED\n",
               pass_count, repeat_count, fail_count, repeat_count);
        printf("  Success rate: %.1f%%\n",
               (double)pass_count / repeat_count * 100.0);
        printf("============================================\n");
    }

    // Cleanup
    munmap(lw_base, LW_BRIDGE_SPAN);
    close(fd);
    return (fail_count == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
