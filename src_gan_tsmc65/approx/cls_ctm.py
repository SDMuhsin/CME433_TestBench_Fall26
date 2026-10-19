"""Classified truncation compensation (CTM) and the constrained level selection (CLS) search of
Wang et al. 2026, Sec. IV-A, generalised to a truncation width t.

* The t least significant product columns are truncated and replaced by a t-bit compensation
  word C chosen from the low bits of the operands (a, b two's complement, low bits unsigned).
* Candidate levels (Sec. IV-A3): the lowest t - 2 bits are fixed to 10..0 (t = 4: "10"), the
  top two bits are free: V_t = {(2m + 1) 2^(t-3), m = 0..3} (t = 4: {2, 6, 10, 14}; t = 2:
  {0, 1, 2, 3}).
* CLS (eqs. 12-16): three levels C_L < C_M < C_H from V_t and thresholds T1 <= T2 on
  S = a[1:0] + b[1:0] (eq. 17); C = C_L for S < T1, C_M for T1 <= S <= T2, C_H for S > T2.
  The parameters minimise mean |e| (NMED), ties broken by mean |e| / max(|P|, 1), with
  e = C - (P mod 2^t), the paper's low-bit replacement model (eq. 23) over the full input
  space. P mod 2^t depends only on a, b mod 2^t, so the NMED term is exact over 2^(2t) pairs
  for any n; the tie-break term uses the full space at n = 8 and 2^20 random pairs at n = 16.
* CTM1 = that three-level rule on (a1, a0, b1, b0) (eq. 19 at t = 4); CTM2 (Fig. 11) =
  the level indexed by a0 + b0 (t = 4: {a0 b0, a0 xor b0, 1, 0} = 2 + 4 (a0 + b0)).
* Table IV: explained variance EV(Z) = Var(E[P_L | Z]) / Var(P_L) of the 2-bit features.
"""
from functools import lru_cache
from itertools import combinations

import numpy as np

from .netlist import ZERO

FEATURES = {'(a0,b0)': ((0,), (0,)), '(a0,b1)': ((0,), (1,)), '(a1,b1)': ((1,), (1,)),
            '(a1,b0)': ((1,), (0,))}


def levels(t):
    return [m for m in range(4)] if t == 2 else [(2 * m + 1) << (t - 3) for m in range(4)]


def _low_space(t):
    """All (a mod 2^t, b mod 2^t) pairs and the low t product bits."""
    a = np.repeat(np.arange(1 << t, dtype=np.int64), 1 << t)
    b = np.tile(np.arange(1 << t, dtype=np.int64), 1 << t)
    return a, b, (a * b) & ((1 << t) - 1)


def _full_space(n, t):
    """Signed operands: the full space at n = 8, 2^20 random pairs otherwise."""
    if n <= 8:
        v = np.arange(-(1 << (n - 1)), 1 << (n - 1), dtype=np.int64)
        a, b = np.repeat(v, v.size), np.tile(v, v.size)
    else:
        rng = np.random.default_rng(2026)
        a = rng.integers(-(1 << (n - 1)), 1 << (n - 1), 1 << 20, dtype=np.int64)
        b = rng.integers(-(1 << (n - 1)), 1 << (n - 1), 1 << 20, dtype=np.int64)
    p = a * b
    return (a & 3) + (b & 3), p & ((1 << t) - 1), np.maximum(np.abs(p), 1)


def rule(s, lv, t1, t2):
    return np.where(s < t1, lv[0], np.where(s <= t2, lv[1], lv[2]))


@lru_cache(maxsize=None)
def search(t, n=8):
    """CLS -> (levels (C_L, C_M, C_H), T1, T2, mean |e|, tie-break term)."""
    a, b, pl = _low_space(t)
    s = (a & 3) + (b & 3)
    fs, fpl, fp = _full_space(n, t)
    best = None
    for lv in combinations(levels(t), 3):
        for t1 in range(8):
            for t2 in range(t1, 8):
                med = np.abs(rule(s, lv, t1, t2) - pl).mean()
                key = round(float(med), 9)
                if best and key > best[0]:
                    continue
                rel = float((np.abs(rule(fs, lv, t1, t2) - fpl) / fp).mean())
                if not best or (key, rel) < best[:2]:
                    best = (key, rel, lv, t1, t2)
    return best[2], best[3], best[4], best[0], best[1]


def ctm1_table(t, n=8):
    """C for every (a1 a0, b1 b0): dict {(a_lo, b_lo): C}."""
    lv, t1, t2 = search(t, n)[:3]
    return {(x, y): int(rule(np.int64(x + y), lv, t1, t2)) for x in range(4) for y in range(4)}


def ctm2_table(t, n=8):
    lv = search(t, n)[0]
    return {(x, y): lv[(x & 1) + (y & 1)] for x in range(4) for y in range(4)}


def const_table(c):
    return {(x, y): c for x in range(4) for y in range(4)}


def model(table, a, b):
    """Compensation word for operand arrays (two's complement low bits)."""
    lut = np.array([table[(x, y)] for x in range(4) for y in range(4)], np.int64)
    return lut[(a & 3) * 4 + (b & 3)]


def bits(net, a, b, t, table):
    """t output bits of the CTM as sums of minterms over (a1, a0, b1, b0); constant bits fold."""
    lits = [a[1], a[0], b[1], b[0]]                    # code bit 3 - i
    f = {x * 4 + y: c for (x, y), c in table.items()}
    out = []
    for k in range(t):
        val = {code: (c >> k) & 1 for code, c in f.items()}
        used = [i for i in range(4) if any(val[c] != val[c ^ (8 >> i)] for c in val)]
        terms = {tuple((c >> (3 - i)) & 1 for i in used) for c in val if val[c]}
        bit = ZERO
        for key in sorted(terms):
            term = 1
            for i, v in zip(used, key):
                term = net.AND(term, lits[i] if v else net.NOT(lits[i]))
            bit = net.OR(bit, term)
        out.append(bit)
    return out


def explained_variance(t=4):
    """Table IV: {feature: (EV, best MSE, E[P_L | Z] for Z = 0..3)} under the low-bit model."""
    a, b, pl = _low_space(t)
    out = {}
    for name, (ia, ib) in FEATURES.items():
        z = ((a >> ia[0]) & 1) * 2 + ((b >> ib[0]) & 1)
        mean = np.array([pl[z == k].mean() for k in range(4)])
        ev = mean[z].var() / pl.var()
        out[name] = (ev, float(((pl - mean[z]) ** 2).mean()), mean)
    return out
