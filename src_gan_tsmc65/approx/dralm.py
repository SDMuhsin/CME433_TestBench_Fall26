"""Dynamic-range approximate logarithmic multiplier (DR-ALM) of Yin et al., IEEE TSUSC 6(4)
2021, and Mitchell's conventional logarithmic multiplier (LM), as bit-exact integer models.

Unsigned core (Algorithm 1, eq. 7), operand X = 2^k (1 + x), k from the leading-one detector:
  dynamic truncation  x_t = the t-2 fraction bits after the leading one, then a forced 1
                      (t bits from the leading one, (t-1)-bit mantissa x_t)
  log adder           L = {k1, x1t} + {k2, x2t} + 1   (compensation 2^-(t-1))
  antilog + shifter   P = {1, L[t-2:0]} shifted by L[top:t-1] - (t-1); right shifts truncate.
LM: the full (n-1)-bit fraction, no forced bit, no compensation (eq. 6).
An operand of 0 gives a product of 0 (zero flag; the paper does not draw it, see
docs/papers/yin_2021_dralm.md).

Signed (Fig. 3): |X| by one's complement (~X for X < 0) OR-ed with a 1 in the least
significant bit, unsigned core on n-1 bits, product sign set the same way: ~|P| | 1 for a
negative product. `sign='exact'` uses exact two's-complement negation in both places
instead. A zero product stays 0.
"""
import numpy as np


def _lod(v, n):
    """Position of the leading one of v > 0 (v < 2^n)."""
    k = np.zeros(v.shape, v.dtype)
    for i in range(1, n):
        k = np.where(v >> i != 0, i, k)
    return k


def unsigned(a, b, n, t=None):
    """Approximate a * b for a, b in [0, 2^n). t = None: Mitchell LM; else DR-ALM-t.
    n > 30 works on Python-int (object) arrays, products need more than 63 bits."""
    dt = np.int64 if n <= 30 else object
    a = np.asarray(a).astype(dt)
    b = np.asarray(b).astype(dt)
    fb = n - 1 if t is None else t - 1                    # mantissa (fraction) bits
    ops = []
    for v in (a, b):
        k = _lod(np.maximum(v, 1), n)
        frac = (np.maximum(v, 1) << (n - 1 - k)) & ((1 << (n - 1)) - 1)   # n-1 fraction bits
        if t is not None:
            frac = ((frac >> (n + 1 - t)) << 1) | 1 if t <= n + 1 else frac
        ops.append((k << fb) | frac)
    L = ops[0] + ops[1] + (0 if t is None else 1)
    mant = (1 << fb) | (L & ((1 << fb) - 1))
    sh = (L >> fb) - fb
    p = np.where(sh >= 0, mant << np.maximum(sh, 0), mant >> np.maximum(-sh, 0))
    return np.where((a == 0) | (b == 0), 0, p)


def signed(a, b, n, t=None, sign='paper'):
    """Approximate a * b for a, b in [-2^(n-1), 2^(n-1)): sign-magnitude around the core."""
    a = np.asarray(a, np.int64)
    b = np.asarray(b, np.int64)
    m = (1 << n) - 1
    if sign == 'paper':
        mag = [np.where(v < 0, (~v & m) | 1, v) for v in (a, b)]
        cn = n - 1                                         # |X| <= 2^(n-1) - 1
    else:
        mag = [np.abs(v) for v in (a, b)]
        cn = n                                             # |-2^(n-1)| needs n bits
    p = unsigned(mag[0], mag[1], cn, t)
    neg = (a < 0) ^ (b < 0)
    if sign == 'paper':
        q = np.where(neg, -p - 1 | 1, p)                   # ~P | 1 in two's complement
    else:
        q = np.where(neg, -p, p)
    return np.where(p == 0, 0, q)


class Dralm:
    """Signed n x n DR-ALM-t (or LM for t = None) with the products() interface of
    mult.Multiplier, for check.py / exhaustive.py."""

    def __init__(self, n=8, t=None, sign='paper', is_signed=True):
        self.n, self.t, self.sign, self.signed = n, t, sign, is_signed

    def products(self, a, b):
        a = np.asarray(a, np.int64).ravel()
        b = np.asarray(b, np.int64).ravel()
        if self.signed:
            return signed(a, b, self.n, self.t, self.sign)
        return unsigned(a, b, self.n, self.t)


def build(n, t, sign='paper', is_signed=True):
    """Module-level builder for exhaustive.py worker pools."""
    return Dralm(n, t, sign, is_signed)
