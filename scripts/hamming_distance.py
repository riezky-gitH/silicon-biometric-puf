#!/usr/bin/env python3
# ============================================================================
# Silicon-Biometric Secure Element — Hamming Distance Utilities
# Team: Ruang Circuit - PENS
# PERURI Chip Hackathon 2026
# ============================================================================
"""
Utility functions for computing Hamming distance metrics
used in PUF quality analysis (uniformity, uniqueness, reliability).
"""

import numpy as np


def hamming_distance(vec_a, vec_b):
    """
    Compute the Hamming distance between two binary vectors.

    Parameters
    ----------
    vec_a : array_like
        First binary vector (0s and 1s).
    vec_b : array_like
        Second binary vector (same length as vec_a).

    Returns
    -------
    int
        Number of positions where vec_a and vec_b differ.
    """
    a = np.asarray(vec_a, dtype=np.uint8)
    b = np.asarray(vec_b, dtype=np.uint8)
    if a.shape != b.shape:
        raise ValueError(f"Shape mismatch: {a.shape} vs {b.shape}")
    return int(np.sum(a != b))


def fractional_hamming_distance(vec_a, vec_b):
    """
    Compute the fractional (normalized) Hamming distance.

    Returns a value between 0.0 (identical) and 1.0 (all bits differ).
    """
    hd = hamming_distance(vec_a, vec_b)
    n = len(np.asarray(vec_a).ravel())
    return hd / n if n > 0 else 0.0


def inter_chip_hd(responses):
    """
    Compute all pairwise inter-chip Hamming distances.

    Parameters
    ----------
    responses : ndarray, shape (num_chips, num_bits)
        Each row is a binary response from a different chip.

    Returns
    -------
    hd_values : list of float
        All pairwise fractional Hamming distances.
    mean_hd : float
        Average inter-chip HD (ideal: 0.50).
    """
    n_chips = responses.shape[0]
    n_bits = responses.shape[1]
    hd_values = []

    for i in range(n_chips):
        for j in range(i + 1, n_chips):
            fhd = hamming_distance(responses[i], responses[j]) / n_bits
            hd_values.append(fhd)

    mean_hd = float(np.mean(hd_values)) if hd_values else 0.0
    return hd_values, mean_hd


def intra_chip_hd(reference, samples):
    """
    Compute intra-chip Hamming distances (reliability metric).

    Parameters
    ----------
    reference : array_like
        Reference response (golden measurement) of a single chip.
    samples : ndarray, shape (num_samples, num_bits)
        Repeated measurements of the same chip under varying conditions.

    Returns
    -------
    hd_values : list of float
        Fractional HD for each sample vs reference.
    mean_hd : float
        Average intra-chip HD (ideal: 0.00, acceptable: < 0.05).
    ber : float
        Bit error rate (same as mean_hd).
    """
    ref = np.asarray(reference, dtype=np.uint8)
    n_bits = len(ref)
    hd_values = []

    for s in samples:
        fhd = hamming_distance(ref, s) / n_bits
        hd_values.append(fhd)

    mean_hd = float(np.mean(hd_values)) if hd_values else 0.0
    return hd_values, mean_hd, mean_hd  # ber == mean_hd


def uniformity(response):
    """
    Compute bit uniformity of a PUF response.

    Parameters
    ----------
    response : array_like
        Binary response vector.

    Returns
    -------
    float
        Proportion of '1' bits (ideal: 0.50).
    """
    r = np.asarray(response, dtype=np.uint8)
    return float(np.mean(r))


if __name__ == "__main__":
    # Quick self-test
    a = np.array([1, 0, 1, 1, 0, 0, 1, 0])
    b = np.array([1, 1, 1, 0, 0, 0, 1, 1])
    print(f"HD({a}, {b}) = {hamming_distance(a, b)}")
    print(f"FHD = {fractional_hamming_distance(a, b):.4f}")
    print(f"Uniformity(a) = {uniformity(a):.4f}")
    print("Self-test passed.")
