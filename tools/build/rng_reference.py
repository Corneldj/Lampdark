#!/usr/bin/env python3
"""Reference implementation of LAMPBLACK's hash and RNG (FND-06), in plain Python.

It is written independently of native/src/core/rng/ and generates the golden files the
C++ and GDScript tests reproduce. Every value is a 64-bit pattern; signed values are the
same bits read as int64.
"""
MASK = (1 << 64) - 1
G = 0x9E3779B97F4A7C15


def u64(x):
    return x & MASK


def i64(x):
    x &= MASK
    return x - (1 << 64) if x >> 63 else x


def mix64(z):
    z = u64(z)
    z = u64((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9)
    z = u64((z ^ (z >> 27)) * 0x94D049BB133111EB)
    return z ^ (z >> 31)


def hash_u64(seed, domain, keys):
    h = mix64(u64(seed) ^ mix64(u64(domain + G)))
    for i, k in enumerate(keys):
        h = mix64(h ^ mix64(u64(u64(k) + u64(G * (i + 2)))))
    return h


def sub_seed(seed, domain, keys, attempt):
    return hash_u64(seed, domain, list(keys) + [attempt])


class Rng:
    def __init__(self, seed):
        self.state = u64(seed)

    def next(self):
        self.state = u64(self.state + G)
        return mix64(self.state)

    def range(self, lo, hi):
        """Inclusive [lo, hi] for signed lo <= hi; unbiased by rejection."""
        n = hi - lo + 1
        if n == 1 << 64:
            return i64(self.next())
        limit = (1 << 64) - ((1 << 64) % n)
        while True:
            x = self.next()
            if x < limit:
                return lo + x % n

    def chance_ppm(self, p):
        return self.range(0, 999999) < p

    def pick_weighted(self, weights):
        total = sum(weights)
        if total <= 0 or any(w < 0 for w in weights) or total >= 1 << 32:
            raise ValueError("bad weights")
        r = self.range(0, total - 1)
        acc = 0
        for index, w in enumerate(weights):
            acc += w
            if r < acc:
                return index
        raise AssertionError("unreachable")

    def shuffle(self, items):
        items = list(items)
        for i in range(len(items) - 1, 0, -1):
            j = self.range(0, i)
            items[i], items[j] = items[j], items[i]
        return items

    def unit_raw53(self):
        return self.next() >> 11


if __name__ == "__main__":
    r = Rng(1234567)
    print([r.next() for _ in range(5)])
