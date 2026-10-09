#!/usr/bin/env python3
# ============================================================================
# Silicon-Biometric Secure Element — PUF Statistical Analysis
# Team: Ruang Circuit - PENS
# PERURI Chip Hackathon 2026
# ============================================================================
"""
Analyze PUF response data and generate statistical quality metrics:
  - Uniformity:  proportion of '1' bits (target: 45-55%)
  - Uniqueness:  inter-chip Hamming distance (target: 40-50%)
  - Reliability: intra-chip Hamming distance / BER (target: < 5%)

Input:  CSV files with binary PUF responses
Output: Summary statistics + matplotlib plots

Usage:
  python puf_analysis.py --inter chips_data.csv
  python puf_analysis.py --intra single_chip_data.csv
  python puf_analysis.py --demo
"""

import argparse
import sys
import os
import numpy as np

try:
    import matplotlib
    matplotlib.use("Agg")  # Non-interactive backend for headless servers
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("[WARNING] matplotlib not found. Plots will be skipped.")

from hamming_distance import (
    uniformity, inter_chip_hd, intra_chip_hd, fractional_hamming_distance
)


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------
def load_responses_csv(filepath):
    """
    Load binary PUF responses from a CSV file.
    Each row is one response (one chip or one measurement).
    Each column is one bit position. Values should be 0 or 1.
    """
    if not os.path.isfile(filepath):
        print(f"[ERROR] File not found: {filepath}")
        sys.exit(1)

    data = np.loadtxt(filepath, delimiter=",", dtype=np.uint8)
    if data.ndim == 1:
        data = data.reshape(1, -1)
    print(f"  Loaded {data.shape[0]} responses × {data.shape[1]} bits")
    return data


# ---------------------------------------------------------------------------
# Analysis: Uniformity
# ---------------------------------------------------------------------------
def analyze_uniformity(responses, output_dir="."):
    """Compute per-chip and overall uniformity."""
    print("\n=== UNIFORMITY ===")
    n_chips, n_bits = responses.shape

    uni_values = []
    for i in range(n_chips):
        u = uniformity(responses[i]) * 100.0
        uni_values.append(u)

    mean_uni = np.mean(uni_values)
    std_uni = np.std(uni_values)

    print(f"  Responses analyzed : {n_chips}")
    print(f"  Bits per response  : {n_bits}")
    print(f"  Mean uniformity    : {mean_uni:.2f}%")
    print(f"  Std deviation      : {std_uni:.2f}%")
    print(f"  Target range       : 45.00% — 55.00%")
    print(f"  Status             : {'PASS' if 45 <= mean_uni <= 55 else 'FAIL'}")

    if HAS_MATPLOTLIB and n_chips > 1:
        fig, ax = plt.subplots(figsize=(8, 5))
        ax.hist(uni_values, bins=max(10, n_chips // 5), color="#2196F3",
                edgecolor="white", alpha=0.85)
        ax.axvline(50, color="red", linestyle="--", label="Ideal (50%)")
        ax.axvspan(45, 55, alpha=0.1, color="green", label="Target range")
        ax.set_xlabel("Uniformity (%)")
        ax.set_ylabel("Count")
        ax.set_title("PUF Bit Uniformity Distribution")
        ax.legend()
        fig.tight_layout()
        path = os.path.join(output_dir, "uniformity_histogram.png")
        fig.savefig(path, dpi=150)
        plt.close(fig)
        print(f"  Plot saved: {path}")

    return uni_values


# ---------------------------------------------------------------------------
# Analysis: Uniqueness (inter-chip)
# ---------------------------------------------------------------------------
def analyze_uniqueness(responses, output_dir="."):
    """Compute pairwise inter-chip Hamming distances."""
    print("\n=== UNIQUENESS (Inter-Chip HD) ===")
    n_chips, n_bits = responses.shape

    if n_chips < 2:
        print("  [SKIP] Need >= 2 chip responses for uniqueness analysis.")
        return []

    hd_values, mean_hd = inter_chip_hd(responses)
    mean_pct = mean_hd * 100
    std_pct = float(np.std(hd_values)) * 100
    n_pairs = len(hd_values)

    print(f"  Chip responses     : {n_chips}")
    print(f"  Pairwise pairs     : {n_pairs}")
    print(f"  Mean inter-HD      : {mean_pct:.2f}%")
    print(f"  Std deviation      : {std_pct:.2f}%")
    print(f"  Target range       : 45.00% — 55.00% (ideal 50.00%)")
    print(f"  Status             : {'PASS' if 45 <= mean_pct <= 55 else 'FAIL'}")

    if HAS_MATPLOTLIB:
        fig, ax = plt.subplots(figsize=(8, 5))
        hd_pct = [v * 100 for v in hd_values]
        ax.hist(hd_pct, bins=max(10, min(50, n_pairs // 10)),
                color="#4CAF50", edgecolor="white", alpha=0.85)
        ax.axvline(50, color="red", linestyle="--", label="Ideal (50%)")
        ax.axvspan(45, 55, alpha=0.1, color="green", label="Target range")
        ax.set_xlabel("Inter-Chip Hamming Distance (%)")
        ax.set_ylabel("Count")
        ax.set_title("PUF Uniqueness — Inter-Chip HD Distribution")
        ax.legend()
        fig.tight_layout()
        path = os.path.join(output_dir, "uniqueness_histogram.png")
        fig.savefig(path, dpi=150)
        plt.close(fig)
        print(f"  Plot saved: {path}")

    return hd_values


# ---------------------------------------------------------------------------
# Analysis: Reliability (intra-chip)
# ---------------------------------------------------------------------------
def analyze_reliability(responses, output_dir="."):
    """
    Compute intra-chip reliability.
    First row is treated as reference; remaining rows are repeated measurements.
    """
    print("\n=== RELIABILITY (Intra-Chip HD / BER) ===")
    n_samples, n_bits = responses.shape

    if n_samples < 2:
        print("  [SKIP] Need >= 2 measurements for reliability analysis.")
        return []

    reference = responses[0]
    samples = responses[1:]

    hd_values, mean_hd, ber = intra_chip_hd(reference, samples)
    mean_pct = mean_hd * 100
    ber_pct = ber * 100
    reliability_pct = 100.0 - mean_pct

    print(f"  Reference          : row 0")
    print(f"  Repeated samples   : {len(samples)}")
    print(f"  Mean intra-HD      : {mean_pct:.4f}%")
    print(f"  Bit Error Rate     : {ber_pct:.4f}%")
    print(f"  Reliability        : {reliability_pct:.4f}%")
    print(f"  Target             : BER < 5.00%")
    print(f"  Status             : {'PASS' if ber_pct < 5.0 else 'FAIL'}")

    if HAS_MATPLOTLIB:
        fig, ax = plt.subplots(figsize=(8, 5))
        hd_pct = [v * 100 for v in hd_values]
        ax.plot(range(1, len(hd_pct) + 1), hd_pct, "o-", color="#FF5722",
                markersize=4, linewidth=1)
        ax.axhline(5.0, color="red", linestyle="--", label="Max BER (5%)")
        ax.axhline(mean_pct, color="blue", linestyle=":", label=f"Mean ({mean_pct:.2f}%)")
        ax.set_xlabel("Sample Index")
        ax.set_ylabel("Intra-Chip HD (%)")
        ax.set_title("PUF Reliability — Intra-Chip HD Over Repeated Measurements")
        ax.legend()
        ax.set_ylim(bottom=0)
        fig.tight_layout()
        path = os.path.join(output_dir, "reliability_plot.png")
        fig.savefig(path, dpi=150)
        plt.close(fig)
        print(f"  Plot saved: {path}")

    return hd_values


# ---------------------------------------------------------------------------
# Demo mode: generate synthetic data for testing
# ---------------------------------------------------------------------------
def run_demo(output_dir="."):
    """Generate synthetic PUF data and run all analyses."""
    print("=== DEMO MODE ===")
    print("  Generating synthetic PUF response data...\n")

    np.random.seed(42)
    n_bits = 256

    # Inter-chip data: 20 chips with ~50% bit uniformity
    n_chips = 20
    inter_data = np.random.randint(0, 2, size=(n_chips, n_bits)).astype(np.uint8)

    # Intra-chip data: 1 reference + 100 noisy copies (~3% BER)
    n_repeats = 100
    ber_target = 0.03
    reference = np.random.randint(0, 2, size=(1, n_bits)).astype(np.uint8)
    noise = (np.random.rand(n_repeats, n_bits) < ber_target).astype(np.uint8)
    noisy = reference ^ noise
    intra_data = np.vstack([reference, noisy])

    # Save demo CSV files
    inter_path = os.path.join(output_dir, "demo_inter_chip.csv")
    intra_path = os.path.join(output_dir, "demo_intra_chip.csv")
    np.savetxt(inter_path, inter_data, delimiter=",", fmt="%d")
    np.savetxt(intra_path, intra_data, delimiter=",", fmt="%d")
    print(f"  Saved: {inter_path} ({n_chips} chips × {n_bits} bits)")
    print(f"  Saved: {intra_path} ({n_repeats + 1} samples × {n_bits} bits)")

    # Run analyses
    analyze_uniformity(inter_data, output_dir)
    analyze_uniqueness(inter_data, output_dir)
    analyze_reliability(intra_data, output_dir)

    print("\n=== DEMO COMPLETE ===")
    if HAS_MATPLOTLIB:
        print("  Check output plots in:", output_dir)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="PUF Statistical Analysis Tool — Silicon-Biometric Secure Element",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Examples:
  %(prog)s --demo                          Run with synthetic data
  %(prog)s --inter multi_chip.csv          Analyze inter-chip uniqueness
  %(prog)s --intra repeated_reads.csv      Analyze intra-chip reliability
  %(prog)s --inter chips.csv --intra reads.csv -o results/
"""
    )
    parser.add_argument("--inter", metavar="CSV",
                        help="CSV file with inter-chip responses (one row per chip)")
    parser.add_argument("--intra", metavar="CSV",
                        help="CSV file with intra-chip responses (row 0 = reference)")
    parser.add_argument("-o", "--output", default=".", metavar="DIR",
                        help="Output directory for plots (default: current dir)")
    parser.add_argument("--demo", action="store_true",
                        help="Run demo with synthetic data")

    args = parser.parse_args()

    if args.demo:
        os.makedirs(args.output, exist_ok=True)
        run_demo(args.output)
        return

    if not args.inter and not args.intra:
        parser.print_help()
        print("\n[ERROR] Specify --inter, --intra, or --demo.")
        sys.exit(1)

    os.makedirs(args.output, exist_ok=True)

    if args.inter:
        print(f"Loading inter-chip data: {args.inter}")
        data = load_responses_csv(args.inter)
        analyze_uniformity(data, args.output)
        analyze_uniqueness(data, args.output)

    if args.intra:
        print(f"Loading intra-chip data: {args.intra}")
        data = load_responses_csv(args.intra)
        analyze_reliability(data, args.output)

    print("\n=== ANALYSIS COMPLETE ===")


if __name__ == "__main__":
    main()
