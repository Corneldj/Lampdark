"""SND-13: the import tool's own tests: BS.1770 reference values, trimming, the band-cap limiter,
normalisation, and the .lbv round trip through a real Opus encode and decode.

    python3 -m unittest discover -s tools/build/voice_import/tests
"""
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lbv  # noqa: E402
import loudness  # noqa: E402
import voice_import as vi  # noqa: E402

RATE = 48000


def sine(freq, seconds, amp=1.0):
    t = np.arange(int(seconds * RATE)) / RATE
    return amp * np.sin(2 * np.pi * freq * t)


class Loudness(unittest.TestCase):
    def test_full_scale_1k_sine_is_minus_3(self):
        # BS.1770-4: a 0 dBFS 997 Hz sine reads -3.01 LKFS.
        self.assertAlmostEqual(loudness.integrated_lufs(sine(997, 3.0)), -3.01, delta=0.05)

    def test_level_scales_in_db(self):
        self.assertAlmostEqual(loudness.integrated_lufs(sine(997, 3.0, 0.1)), -23.01, delta=0.05)

    def test_gate_ignores_silence(self):
        x = np.concatenate([sine(997, 1.0, 0.1), np.zeros(RATE * 2), sine(997, 1.0, 0.1)])
        # Ungated, half the time silent would read -26; the gates drop the silent blocks, and only
        # the blocks straddling the tone's edges pull it a little under the tone's -23.
        self.assertGreater(loudness.integrated_lufs(x), -24.0)
        self.assertLessEqual(loudness.integrated_lufs(x), -23.0)

    def test_frame_rms(self):
        self.assertAlmostEqual(float(loudness.frame_rms_dbfs(sine(1000, 0.2)).max()), -3.01, delta=0.05)


class Processing(unittest.TestCase):
    def test_trim_keeps_20_ms(self):
        x = np.concatenate([np.zeros(RATE), sine(440, 0.5, 0.3), np.zeros(RATE)])
        y = vi.trim(x, 0.02, 45.0)
        self.assertAlmostEqual(len(y) / RATE, 0.54, delta=0.011)

    def test_limit_caps_every_frame(self):
        x = np.concatenate([sine(300, 0.3, 0.02), sine(300, 0.3, 0.9), sine(300, 0.3, 0.02)])
        y = vi.limit(x, -20.0)
        self.assertLessEqual(float(loudness.frame_rms_dbfs(y).max()), -20.0 + 1e-6)
        self.assertAlmostEqual(float(loudness.frame_rms_dbfs(y[:9600]).max()), float(loudness.frame_rms_dbfs(x[:9600]).max()), delta=0.01)

    def test_level_reaches_target_under_cap(self):
        rng = np.random.default_rng(3)
        x = sine(220, 1.5, 0.2) * (1 + 0.8 * np.sin(np.arange(int(1.5 * RATE)) / 3000)) + rng.normal(0, 0.01, int(1.5 * RATE))
        y = vi.level(x, -26.0, -17.0)
        self.assertAlmostEqual(loudness.integrated_lufs(y), -26.0, delta=0.1)
        self.assertLessEqual(float(loudness.frame_rms_dbfs(y).max()), -17.0 + 1e-6)


class Container(unittest.TestCase):
    def test_lbv_round_trip_through_opus(self):
        x = sine(440, 0.733, 0.2)
        data = vi.encode_lbv(x, "24k")
        pre_skip, samples, packets = lbv.read_lbv(data)
        self.assertEqual(samples, len(x))
        self.assertTrue((len(packets) - 1) * 960 < samples + pre_skip <= len(packets) * 960)
        y = vi.decode_lbv(data)
        self.assertEqual(len(y), len(x), "the decoded length is the recorded length")
        self.assertAlmostEqual(loudness.integrated_lufs(y), loudness.integrated_lufs(x), delta=0.5)

    def test_malformed(self):
        with self.assertRaises(ValueError):
            lbv.read_lbv(b"LBV1" + b"\x00" * 9)
        good = lbv.write_lbv(312, 960, [b"\x01\x02"])
        self.assertEqual(lbv.read_lbv(good), (312, 960, [b"\x01\x02"]))
        with self.assertRaises(ValueError):
            lbv.read_lbv(good + b"x")


if __name__ == "__main__":
    unittest.main()
