"""Exhaustive accuracy of the hardware decay dA = exp2(p), p = FP16(dt * A'), against float.

For every legal negative FP16 p, compare the LUT result with exact 2^p:
  * relative error of dA itself;
  * relative error of the decay rate 1 - dA, i.e. of the state time constant
    tau = -1 / ln(dA) (tokens); dA == 1 means the channel never decays (tau = inf).
Results are grouped by the true time constant, then weighted by how often each p occurs
in a golden run (`src.longctx.long_eval` saves the observed p histogram).
`free_decay` adds the FP16 state: h <- wb(dA * h) with no input, the slowest case.
"""
import argparse

import numpy as np

from src.golden.arith.fp import dot, to_fp16, value, writeback
from src.golden.arith.nlu import exp2

TAU_EDGES = (0, 1, 10, 100, 1e3, 1e4, 1e5, np.inf)


def all_negative_p():
    """Every canonical FP16 code with value in [-13, 0) (2^p is a normal FP16 there) -> (bits, float64 values)."""
    b = np.arange(0x8400, 0xCA01, dtype=np.uint32).astype(np.uint16)   # -2^-14 .. -13
    return b, value(b).astype(np.float64)


def decay_errors(p_bits, p):
    """-> dict of per-input arrays: hardware dA, exact dA, rel errors, tau true / hw."""
    hw = value(exp2(p_bits)).astype(np.float64)
    ref = np.exp2(p)
    tau_ref = -1.0 / (p * np.log(2.0))
    with np.errstate(divide='ignore'):
        tau_hw = np.where(hw >= 1.0, np.inf, -1.0 / np.log(np.where(hw > 0, hw, 1e-300)))
    rate_ref, rate_hw = -np.expm1(p * np.log(2.0)), 1.0 - hw
    return dict(hw=hw, ref=ref, rel_dA=(hw - ref) / ref, rel_rate=(rate_hw - rate_ref) / rate_ref,
                tau_ref=tau_ref, tau_hw=tau_hw, frozen=hw >= 1.0,
                rel_dA_fp16=(value(to_fp16(ref)) - ref) / ref)


def by_tau(err, weight=None):
    """Rows (tau range, n codes, max |rel dA|, max |rel rate|, mean rel rate, frozen, weight)."""
    rows = []
    for lo, hi in zip(TAU_EDGES[:-1], TAU_EDGES[1:]):
        m = (err['tau_ref'] >= lo) & (err['tau_ref'] < hi)
        if not m.any():
            continue
        w = None if weight is None else float(weight[m].sum() / weight.sum())
        rr = err['rel_rate'][m]
        rows.append((lo, hi, int(m.sum()), float(np.abs(err['rel_dA'][m]).max()),
                     float(np.abs(rr).max()), float(rr.mean()), int(err['frozen'][m].sum()), w))
    return rows


def free_decay(tau, h0, max_steps=200000):
    """Steps for FP16 h <- wb(dA*h) to fall below h0/e, dA = hw exp2(FP16(-1/(tau ln 2))).

    h0: FP16 bits of the start values; -> (dA value, steps per start value; -1 = never).
    """
    dA = exp2(to_fp16(-1.0 / (tau * np.log(2.0))))
    h, goal = h0.copy(), value(h0).astype(np.float64) / np.e
    steps = np.full(len(h0), -1)
    for t in range(1, max_steps + 1):
        nh = writeback(dot([(np.broadcast_to(dA, h.shape), h)]))
        done = (steps < 0) & (value(nh) <= goal)
        steps[done] = t
        if np.all(steps >= 0) or np.array_equal(nh, h):
            break
        h = nh
    return float(value(dA)), steps


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--hist', help='npz from golden_eval with observed p code counts')
    a = ap.parse_args()
    b, p = all_negative_p()
    err = decay_errors(b, p)
    weight = None
    if a.hist:
        counts = np.load(a.hist)['p_counts'].astype(np.float64)   # [65536] per FP16 code
        weight = counts[b]
        print(f'observed p codes: {int(counts.sum())} samples, '
              f'{counts[b].sum() / counts.sum():.6f} in [-13, 0)')
    print(f'max |rel dA| over p in [-13,0): {np.abs(err["rel_dA"]).max():.3e} '
          f'(ideal FP16 rounding of 2^p: {np.abs(err["rel_dA_fp16"]).max():.3e})')
    print(f'p codes with dA == 1 (frozen state): {int(err["frozen"].sum())}, '
          f'largest such |p| = {(-p[err["frozen"]]).max():.3e}')
    print('tau range [tokens]   codes  max|rel dA|  max|rel(1-dA)|  mean rel(1-dA)  frozen  usage')
    for lo, hi, n, edA, er, mr, fz, w in by_tau(err, weight):
        ws = '' if w is None else f'{w:.2e}'
        print(f'[{lo:>6g}, {hi:>6g})  {n:6d}  {edA:10.2e}  {er:13.2e}  {mr:+13.2e}  {fz:6d}  {ws}')
    h0 = to_fp16(np.exp2(np.linspace(-3, 3, 97)))       # start values 1/8 .. 8, many mantissas
    print('free decay of the FP16 state, steps to 1/e:  tau  dA(hw)  min / median / max  (stuck)')
    for tau in (10, 30, 100, 300, 1000, 2000, 3000, 5000):
        dA, st = free_decay(tau, h0)
        ok = st[st > 0]
        rng = f'{ok.min():6d} / {int(np.median(ok)):6d} / {ok.max():6d}' if len(ok) else '   - / - / -'
        print(f'  {tau:5d}  {dA:.6f}  {rng}  ({int(np.sum(st < 0))}/{len(st)} never reach 1/e)')


if __name__ == '__main__':
    main()
