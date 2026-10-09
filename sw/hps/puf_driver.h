// ============================================================================
// Silicon-Biometric Secure Element
// PUF Register Driver Header
// Team: Ruang Circuit - PENS
// PERURI Chip Hackathon 2026
// ============================================================================
#ifndef PUF_DRIVER_H
#define PUF_DRIVER_H

#include <stdint.h>

// ---------------------------------------------------------------------------
// Lightweight HPS-to-FPGA Bridge base address
// ---------------------------------------------------------------------------
#define LW_BRIDGE_BASE  0xFF200000
#define LW_BRIDGE_SPAN  0x00200000  // 2 MB

// ---------------------------------------------------------------------------
// PUF Register Map (Avalon-MM, word-aligned offsets)
// Matches rtl/puf_regs.v register definitions
// ---------------------------------------------------------------------------
#define REG_CTRL        0x00    // [W]  Control register
#define REG_STATUS      0x04    // [R]  Status register
#define REG_PAIR_SEL    0x08    // [W]  Pair selection index for enrollment
#define REG_RAW_DIFF    0x0C    // [R]  Raw counter difference (0 when LOCKED)

#define REG_NONCE0      0x10    // [W]  Challenge nonce bits [31:0]
#define REG_NONCE1      0x14    // [W]  Challenge nonce bits [63:32]
#define REG_NONCE2      0x18    // [W]  Challenge nonce bits [95:64]
#define REG_NONCE3      0x1C    // [W]  Challenge nonce bits [127:96]

#define REG_RESP0       0x20    // [R]  AES response bits [31:0]
#define REG_RESP1       0x24    // [R]  AES response bits [63:32]
#define REG_RESP2       0x28    // [R]  AES response bits [95:64]
#define REG_RESP3       0x2C    // [R]  AES response bits [127:96]

#define REG_MASK0       0x30    // [RW] Reliability mask bits [31:0]
#define REG_MASK1       0x34    // [RW] Reliability mask bits [63:32]
#define REG_MASK2       0x38    // [RW] Reliability mask bits [95:64]
#define REG_MASK3       0x3C    // [RW] Reliability mask bits [127:96]
#define REG_MASK4       0x40    // [RW] Reliability mask bits [159:128]
#define REG_MASK5       0x44    // [RW] Reliability mask bits [191:160]
#define REG_MASK6       0x48    // [RW] Reliability mask bits [223:192]
#define REG_MASK7       0x4C    // [RW] Reliability mask bits [255:224]

#define REG_HELPER0     0x50    // [RW] Helper data bits [31:0]
#define REG_HELPER1     0x54    // [RW] Helper data bits [51:32]

// ---------------------------------------------------------------------------
// CTRL register bit definitions
// ---------------------------------------------------------------------------
#define CTRL_START_PUF  (1 << 0)    // Trigger PUF measurement & key reconstruction
#define CTRL_START_AUTH (1 << 1)    // Trigger full authentication (PUF + ECC + AES)
#define CTRL_LOCK       (1U << 31)  // Permanent hardware lock (irreversible)

// ---------------------------------------------------------------------------
// STATUS register bit definitions
// ---------------------------------------------------------------------------
#define STATUS_BUSY     (1 << 0)    // Hardware is processing
#define STATUS_DONE     (1 << 1)    // Operation complete
#define STATUS_KEY_OK   (1 << 2)    // PUF key is valid and stable
#define STATUS_ECC_FAIL (1 << 3)    // Uncorrectable ECC error detected
#define STATUS_LOCKED   (1 << 4)    // Hardware lock is active

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
#define NUM_RO_PAIRS        256
#define NUM_MASK_REGS       8
#define NUM_HELPER_REGS     2
#define NUM_NONCE_REGS      4
#define NUM_RESP_REGS       4
#define MASK_RELIABLE_BITS  195
#define KEY_BITS            128
#define HELPER_DATA_BITS    52

// ---------------------------------------------------------------------------
// Memory-mapped I/O helper macros
// ---------------------------------------------------------------------------
#define PUF_READ(base, offset) \
    (*((volatile uint32_t *)((uint8_t *)(base) + (offset))))

#define PUF_WRITE(base, offset, val) \
    (*((volatile uint32_t *)((uint8_t *)(base) + (offset))) = (val))

// ---------------------------------------------------------------------------
// Convenience: wait until hardware is no longer busy
// ---------------------------------------------------------------------------
static inline void puf_wait_done(void *base) {
    while (PUF_READ(base, REG_STATUS) & STATUS_BUSY) {
        // spin
    }
}

static inline int puf_is_locked(void *base) {
    return (PUF_READ(base, REG_STATUS) & STATUS_LOCKED) != 0;
}

#endif // PUF_DRIVER_H
