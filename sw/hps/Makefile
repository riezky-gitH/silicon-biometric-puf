# ============================================================================
# Silicon-Biometric Secure Element — HPS Software
# Cross-compilation Makefile for ARM Cortex-A9 (DE10-Nano)
# Team: Ruang Circuit - PENS
# PERURI Chip Hackathon 2026
# ============================================================================

# Cross-compiler toolchain
CC       = arm-linux-gnueabihf-gcc
CFLAGS   = -Wall -Wextra -O2 -std=c99
LDFLAGS  = -lrt

# Targets
TARGETS  = puf_enroll puf_verify
HEADERS  = puf_driver.h

.PHONY: all clean deploy

all: $(TARGETS)

puf_enroll: puf_enroll.c $(HEADERS)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	@echo "[OK] Built $@"

puf_verify: puf_verify.c $(HEADERS)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	@echo "[OK] Built $@"

clean:
	rm -f $(TARGETS) *.o *.bin *.csv
	@echo "[OK] Cleaned"

# Deploy to DE10-Nano via SCP (set DE10_IP environment variable)
DE10_IP ?= 192.168.1.100
deploy: $(TARGETS)
	scp $(TARGETS) root@$(DE10_IP):~/puf/
	@echo "[OK] Deployed to $(DE10_IP)"
