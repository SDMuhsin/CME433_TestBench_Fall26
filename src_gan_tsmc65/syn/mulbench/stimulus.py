"""Operand streams of the multiplier-bench power runs (one {a, b} hex word of 2N bits per line).

  python3 syn/mulbench/stimulus.py <width> <uniform|gan> <signed|unsigned> <count> <out.memh>
uniform  a, b uniform over all N-bit patterns (same words for signed and unsigned designs).
gan      a = weight ~ round(N(0, s)), s = 2^(N-1) / 4 (|a| <= 4 s = full scale; clipped);
         b = activation >= 0: 0 with probability 0.65, else round(|N(0, s)|) clipped to
         2^(N-1) - 1 (ReLU outputs). Unsigned designs get |a| (same magnitudes).
Seeded (RandomState(433 + set index)); plain numpy, Python 3.6 compatible.
"""
import sys

import numpy as np

P_ZERO = 0.65


def stream(n, kind, signed, count):
    rng = np.random.RandomState(433 + ('uniform', 'gan').index(kind))
    if kind == 'uniform':
        return rng.randint(0, 1 << n, count), rng.randint(0, 1 << n, count)
    s = (1 << (n - 1)) / 4.0
    hi = (1 << (n - 1)) - 1
    a = np.clip(np.round(rng.normal(0, s, count)), -hi - 1, hi).astype(np.int64)
    act = np.clip(np.round(np.abs(rng.normal(0, s, count))), 0, hi).astype(np.int64)
    b = np.where(rng.random_sample(count) < P_ZERO, 0, act)
    if not signed:
        a = np.abs(a)
    return a & ((1 << n) - 1), b


def main():
    n, kind, sign, count, out = sys.argv[1:6]
    n, count = int(n), int(count)
    a, b = stream(n, kind, sign == 'signed', count)
    with open(out, 'w') as f:
        for x, y in zip(a, b):
            f.write('%0*x%0*x\n' % (n // 4, x, n // 4, y))


if __name__ == '__main__':
    main()
