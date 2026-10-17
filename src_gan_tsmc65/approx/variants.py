"""Structured signed 8 x 8 gan_mul8 variants (a = weight, b = activation) built from the
shared front ends and reduction tree. The approximate cells replace the exact HA / FA in
the k least significant columns only; the matching *_exact variant has the identical dot
diagram with exact cells, so the pair isolates the effect of the approximation.

  bw_exact      Baugh-Wooley AND array, Dadda tree (exact HA / FA), one CPA
  bw_axfa6      same, Venkatachalam & Ko approximate HA / FA in columns 0..5
  booth_exact   radix-4 Booth (b recoded, 4 rows of 9 bits), Dadda tree, one CPA
  booth_axfa5   same, approximate HA / FA in columns 0..4
"""
from . import booth, pp
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
}
