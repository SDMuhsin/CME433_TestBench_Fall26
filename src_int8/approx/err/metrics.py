"""Error metrics of a signed 8 x 8 multiplier from its full 256 x 256 product table.

E = approx - exact (signed error). Definitions follow the approximate-multiplier literature
(e.g. Strollo et al., TCAS-I 2022, Sec. II):
  ER    P(E != 0)
  MED   mean |E|;  NMED = MED / MaxOut,  MaxOut = 2^(2n-2) = 16384 for signed n = 8
  MRED  mean |E| / |exact| over exact != 0;  PRED = P(RED > 2 %) over exact != 0
  bias  mean E;  NM = mean(exact - approx) / MaxOut  (the papers' sign convention)
  NoEB  2n - log2(1 + RMS(E))
An optional operand histogram w[a + 128, b + 128] gives the same metrics weighted by a real
operand distribution (the chip's weight x activation products).
"""
import numpy as np

R = np.arange(-128, 128)
EXACT = R[:, None] * R[None, :]
MAXOUT = 2 ** 14


def metrics(table, w=None):
    e = (np.asarray(table, np.int64) - EXACT).astype(np.float64)
    w = np.ones_like(e) if w is None else np.asarray(w, np.float64)
    w = w / w.sum()
    nz = EXACT != 0
    wn = w * nz / (w * nz).sum()
    red = np.where(nz, np.abs(e) / np.maximum(np.abs(EXACT), 1), 0.0)
    med = float((w * np.abs(e)).sum())
    rms = float(np.sqrt((w * e * e).sum()))
    bias = float((w * e).sum())
    return dict(
        ER=float((w * (e != 0)).sum()),
        MED=med, NMED=med / MAXOUT,
        MRED=float((wn * red).sum()), PRED=float((wn * (red > 0.02)).sum()),
        max_abs_error=int(np.abs(e[w > 0]).max()), NmaxED=float(np.abs(e[w > 0]).max() / MAXOUT),
        bias=bias, NM=-bias / MAXOUT,
        RMS=rms, NoEB=16 - float(np.log2(1 + rms)),
        error_at_zero_operand=int(np.abs(e[~nz]).max()))
