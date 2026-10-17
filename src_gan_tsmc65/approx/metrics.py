"""Error metrics of an approximate multiplier, accumulated over chunks of operands.

E = approx - exact. ER = P(E != 0); MED = mean |E|; NMED = MED / max |exact| (normalised
by the largest product, (2^n - 1)^2 unsigned); NED = MED / max |E| (Liang et al. 2013:
normalised by the largest error distance of the design); MRED = mean |E| / |exact| over
exact != 0; bias = mean E; MAE = MED. `zero_hits` counts exact == 0 with approx != 0.
"""
import numpy as np


class ErrorStats:
    def __init__(self, max_out):
        self.max_out = max_out
        self.n = self.nz = self.err = self.zero_hits = 0
        self.sum_abs = self.sum_e = 0
        self.sum_red = 0.0
        self.max_abs = 0

    def add(self, approx, exact):
        e = np.asarray(approx, np.int64) - np.asarray(exact, np.int64)
        ae = np.abs(e)
        nz = exact != 0
        self.n += e.size
        self.nz += int(nz.sum())
        self.err += int((e != 0).sum())
        self.zero_hits += int(((~nz) & (e != 0)).sum())
        self.sum_abs += int(ae.sum())
        self.sum_e += int(e.sum())
        self.sum_red += float((ae[nz] / np.abs(exact[nz])).sum())
        self.max_abs = max(self.max_abs, int(ae.max(initial=0)))
        return self

    def result(self):
        med = self.sum_abs / self.n
        return dict(n=self.n, ER=self.err / self.n, MED=med, NMED=med / self.max_out,
                    NED=med / self.max_abs if self.max_abs else 0.0,
                    MRED=self.sum_red / self.nz, bias=self.sum_e / self.n,
                    max_abs=self.max_abs, zero_hits=self.zero_hits)


def table_stats(table, exact, mask=None, max_out=None):
    """Metrics of a full product table (optionally over mask, e.g. b >= 0)."""
    t, x = np.asarray(table), np.asarray(exact)
    if mask is not None:
        t, x = t[mask], x[mask]
    return ErrorStats(max_out or int(np.abs(x).max())).add(t, x).result()
