"""SND-13: loudness per ITU-R BS.1770-4 (K-weighting, 400 ms blocks every 100 ms, the -70 LUFS
absolute and -10 LU relative gates), and the 20 ms frame RMS that SND-07's band cap limits.

The K-weighting filters run exactly as linear IIR filters, applied in the frequency domain with
enough zero padding (1 s) that their tails decay completely. A line shorter than one 400 ms block
is measured as one block over its whole length (BS.1770 defines no shorter block; Proposed).
"""
import numpy as np

RATE = 48000
# BS.1770-4's K-weighting at 48 kHz: the high shelf, then the RLB high-pass.
SHELF_B = [1.53512485958697, -2.69169618940638, 1.19839281085285]
SHELF_A = [1.0, -1.69065929318241, 0.73248077421585]
HP_B = [1.0, -2.0, 1.0]
HP_A = [1.0, -1.99004745483398, 0.99007225036621]


def _response(b, a, n):
    z = np.exp(-1j * np.pi * np.arange(n // 2 + 1) / (n // 2))
    return (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)


def k_weight(x):
    x = np.asarray(x, dtype=np.float64)
    n = 1
    while n < len(x) + RATE:
        n *= 2
    h = _response(SHELF_B, SHELF_A, n) * _response(HP_B, HP_A, n)
    return np.fft.irfft(np.fft.rfft(x, n) * h, n)[:len(x)]


def integrated_lufs(x):
    y = k_weight(x)
    block, step = int(0.4 * RATE), int(0.1 * RATE)
    if len(y) < block:
        powers = np.array([np.mean(y * y)])
    else:
        starts = range(0, len(y) - block + 1, step)
        powers = np.array([np.mean(y[s:s + block] ** 2) for s in starts])
    loud = -0.691 + 10.0 * np.log10(np.maximum(powers, 1e-20))
    gated = powers[loud > -70.0]
    if len(gated) == 0:
        return -70.0
    relative = -0.691 + 10.0 * np.log10(np.mean(gated)) - 10.0
    gated = powers[(loud > -70.0) & (loud > relative)]
    return float(-0.691 + 10.0 * np.log10(np.mean(gated)))


def frame_rms_dbfs(x, frame=960):
    """Each 20 ms frame's RMS in dBFS (a full-scale square wave is 0)."""
    x = np.asarray(x, dtype=np.float64)
    n = len(x) // frame
    if n == 0:
        return np.array([20.0 * np.log10(max(np.sqrt(np.mean(x * x)), 1e-10))])
    f = x[:n * frame].reshape(n, frame)
    return 20.0 * np.log10(np.maximum(np.sqrt(np.mean(f * f, axis=1)), 1e-10))
