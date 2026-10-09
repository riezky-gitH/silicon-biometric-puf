# AES-128 Core

This directory should contain the [secworks/aes](https://github.com/secworks/aes) Verilog implementation.

## Setup

### Option 1: Git Submodule (Recommended)
```bash
cd silicon-biometric-puf
git submodule add https://github.com/secworks/aes.git rtl/aes/secworks_aes
```

### Option 2: Manual Download
1. Download from https://github.com/secworks/aes
2. Copy the following files to this directory:
   - `src/rtl/aes_core.v`
   - `src/rtl/aes_decipher_block.v`
   - `src/rtl/aes_encipher_block.v`
   - `src/rtl/aes_key_mem.v`
   - `src/rtl/aes_sbox.v`
   - `src/rtl/aes.v`

## License

The secworks/aes core is licensed under BSD-2-Clause.
See https://github.com/secworks/aes/blob/master/LICENSE for details.
