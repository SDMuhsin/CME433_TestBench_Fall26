"""Structured signed 8 x 8 gan_mul8 variants (a = weight, b = activation) built from the
shared front ends and reduction tree. The approximate cells replace the exact HA / FA in
the k least significant columns only; the matching *_exact variant has the identical dot
diagram with exact cells, so the pair isolates the effect of the approximation.

  bw_exact      Baugh-Wooley AND array, Dadda tree (exact HA / FA), one CPA
  bw_axfa6      same, Venkatachalam & Ko approximate HA / FA in columns 0..5
  booth_exact   radix-4 Booth (b recoded, 4 rows of 9 bits), Dadda tree, one CPA
  booth_axfa5   same, approximate HA / FA in columns 0..4
  booth_trunc5  booth_exact with columns 0..4 truncated and a constant 1 in column 5
                (constant compensation in the sense of Aizaz & Khare 2022, see tacbm.py)
  booth_akc     Aizaz & Khare 2022 TACBM at the paper's 8-bit point w = 6: columns 0..5
                truncated, compensation carry t^1_6 = P05 + P13 P21 in column 6, neg_i OR-ed
                with each row's first bit (strict-neg Booth encoder), exact Dadda tree
"""
from . import booth, pp, tacbm
from .cells import EXACT, VK_HA_FA
from .mult import build
from .netlist import Net
from .reduce import DADDA

N = 8


def _signed(front, approx_cols, n=N):
    net = Net()
    a, b = net.bus('a', n), net.bus('b', n)
    cols = front(net, a, b).columns()
    return build(net, a, b, cols, lambda i: VK_HA_FA if i < approx_cols else EXACT, DADDA,
                 signed=True)


VARIANTS = {
    'bw_exact': lambda: _signed(pp.baugh_wooley, 0),
    'bw_axfa6': lambda: _signed(pp.baugh_wooley, 6),
    'booth_exact': lambda: _signed(booth.matrix, 0),
    'booth_axfa5': lambda: _signed(booth.matrix, 5),
    'booth_trunc5': lambda: _signed(
        lambda net, a, b: tacbm.matrix(net, a, b, 5, (), neg_or=False, const=1 << 5), 0),
    'booth_akc': lambda: _signed(lambda net, a, b: tacbm.matrix(net, a, b, 6), 0),
}
