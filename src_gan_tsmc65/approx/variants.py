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
  dralm_t<k>    Yin et al. 2021 signed DR-ALM-k (logarithmic, operands truncated to k bits
                from the leading one, compensation), the paper's approximate sign units
  dralm_t6e     DR-ALM-6 core with exact two's-complement sign units (not in the paper)
  cdm_<xy>      Amirafshar et al. 2023 carry-disregard multiplier CDM8_xy (hex x, y: carries of
                columns 2..x of the A x B_L array and 2..y of the A x B_H array disregarded),
                sign-magnitude extension folded into the bit matrix (cdm.py), exact Dadda tree
  cdm_51b       ablation: CDM8_51 on the plain Baugh-Wooley array (no sign handling, cdm.py)
  ham_a, ham_c  Shi et al. 2025 hybrid log / piecewise-linear multipliers HAM-A and HAM-C (8-bit
                H7C0), the paper's sign scheme: partial complement (PACC) of the operands, sign
                compensation (SC) of the result
  ham_ae        ablation: HAM-A with exact two's-complement operand magnitudes (not in the paper)
  park_5z       Park, Kung & Lee 2023 approximate radix-4 Booth (park.py), the paper's 16-bit
                (wG, wA) = (10, 10) scaled to 8 bits: OR-gate encoders in columns 0..4, the AND
                4:2 compressor in columns 0..4, grouped 4:2 tree; zero-safe encoder (b = 0 -> 0)
  r256_6z       Zhu et al. 2022 approximate radix-256 Booth (zhu.py) scaled to 8 bits: Table III
                digit on b[5:0] (multiples x 2^-2), one exact radix-4 row for b[7:6], exact 4:2
                tree; zero-safe B_8M (b = 0 -> 0)
The dralm_* and ham_* entries are behavioural models (dralm.Dralm, ham.Ham), not dot diagrams.
"""
from functools import partial

from . import booth, cdm, dralm, ham, park, pp, tacbm, zhu
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

for _t in (4, 5, 6):
    VARIANTS[f'dralm_t{_t}'] = partial(dralm.Dralm, N, _t, 'paper')
VARIANTS['dralm_t6e'] = partial(dralm.Dralm, N, 6, 'exact')

for _x, _y in ((5, 1), (7, 3), (9, 5)):
    VARIANTS[f'cdm_{_x:x}{_y:x}'] = partial(cdm.cdm, _x, _y)
VARIANTS['cdm_51b'] = partial(cdm.cdm, 5, 1, 'bw')

VARIANTS['ham_a'] = lambda: ham.HAM8['A']
VARIANTS['ham_c'] = lambda: ham.HAM8['C']
VARIANTS['ham_ae'] = lambda: ham.HAM8['A'].with_(me='exact')
VARIANTS['park_5z'] = partial(park.park, N, 5, 5, True, True)
VARIANTS['r256_6z'] = partial(zhu.zhu, N, 6, True)
