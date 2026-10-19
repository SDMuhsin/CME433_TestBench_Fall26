"""Wang, Yao, Xiang, Xu, Wu, Gao, Chen, Chen, Liang & Xu, "A CLS-Based Driven Classified
Truncation Approximate Booth Multiplier for High-Fidelity Image Processing", IEEE TVLSI 34(9)
2026 (ABMCT1 / ABMCT2 / ABMFT1, Figs. 12-13), generalised to n x n signed with a truncation
width t and an approximation band of w columns (paper: n = 8, t = 4, w = 4).

Signed radix-4 Booth (b recoded, n/2 rows, strict neg: digit 111 gives a zero row):
* columns < t are truncated (data bits and the neg bits of rows with 2i < t); the CTM word
  (cls_ctm.py) is placed in product bits t-1..0 (no carry into column t);
* columns t .. t+w-1 (the approximation band): data bits from the approximate encoder
  (cls_cells: CAE1 / CAE2); each column is reduced by approximate 4:2 compressors (A4T2C_1 /
  A4T2C_2) on its first four bits, in row order, then the neg bits, then the carries of the
  compressors of column c-1 of the same stage (the authors' RTL: column 5 of the 8-bit design
  takes carry4 as x4); leftovers and sums go to the next stage, repeated while a band column
  has >= 4 bits; the carry of the band's top column goes to column t+w;
* the error compensation module of ABMCT (Fig. 12): AND of the four inputs of each A4T2C_1 in
  the band's top column, added in column t+w;
* columns >= t+w: exact Booth bits, sign extension E E ~E (row 0) / ~E 1 (rows i > 0) as in the
  authors' RTL, exact 4:2 tree (park_tree.py) and one carry-propagate adder.
With t = 4, w = 4, n = 8 the netlist equals the authors' published RTL (simulated exhaustively,
docs/papers/wang_2026_cls.md). `zero_fix` (not in the paper) gates the CTM word with OR(b) and
uses the zero-safe CAE2, so b = 0 gives exactly 0.
"""
from . import booth, cls_cells, cls_ctm
from .mult import Multiplier
from .netlist import ONE, Net
from .park_tree import reduce

# the paper's 8-bit designs (Sec. IV-B) and the ablation rows of Table VI
PAPER = {
    'abmct1': dict(enc='cae1', comp='a4t2c1', ctm='ctm2', and4=True),
    'abmct2': dict(enc='cae2', comp='a4t2c1', ctm='ctm2', and4=True),
    'abmft1': dict(enc='cae2', comp='a4t2c2', ctm=None, and4=False),
    'exact_ctm': dict(enc='exact', comp='exact', ctm='ctm2', and4=False),
    'cae1_only': dict(enc='cae1', comp='exact', ctm='ctm2', and4=False),
    'cae2_only': dict(enc='cae2', comp='exact', ctm='ctm2', and4=False),
    'a4t2c1_only': dict(enc='exact', comp='a4t2c1', ctm='ctm2', and4=True),
    'a4t2c2_only': dict(enc='exact', comp='a4t2c2', ctm='ctm2', and4=False),
}


def ctm_table(ctm, t, n):
    if ctm is None:
        return cls_ctm.const_table(0)
    if isinstance(ctm, int):
        return cls_ctm.const_table(ctm)
    return {'ctm1': cls_ctm.ctm1_table, 'ctm2': cls_ctm.ctm2_table}[ctm](t, n)


def columns(net, a, b, t, w, enc, zero_fix):
    """Partial-product columns (columns < t empty); bits in row order, then the neg bits."""
    n = len(a)
    cols = [[] for _ in range(2 * n)]
    negs = []
    encode = None if enc == 'exact' else cls_cells.ENCODERS['cae2z' if zero_fix and enc == 'cae2'
                                                               else enc]
    for i, digit in enumerate(booth.encode(net, b, strict_neg=True)):
        hi, mid, lo = b[2 * i + 1], b[2 * i], b[2 * i - 1] if i else 0
        bits = booth.row_bits(net, a, digit, i)
        for j in range(n):
            c = 2 * i + j
            if c >= t:
                band = c < t + w and encode
                cols[c].append(net.name(encode(net, hi, mid, lo, a[j]), f'pc_{i}_{j}')
                               if band else bits[j])
        e = bits[n]
        sign = ([(n, e), (n + 1, e), (n + 2, net.NOT(e))] if i == 0 else
                [(2 * i + n, net.NOT(e)), (2 * i + n + 1, ONE)])
        for c, bit in sign:
            if c < 2 * n:
                cols[c].append(bit)
        if 2 * i >= t:
            negs.append((2 * i, digit[2]))
    for c, bit in negs:
        cols[c].append(bit)
    return cols


def band_stages(net, cols, t, w, comp, and4, log):
    """Approximate compressor stages in columns t .. t+w-1 (see the module docstring)."""
    cell = cls_cells.COMPRESSORS[comp]
    top = t + w - 1
    k = 0
    while any(len(cols[c]) >= 4 for c in range(t, t + w)):
        k += 1
        nxt = [[] if t <= c <= top else list(col) for c, col in enumerate(cols)]
        chain = []
        for c in range(t, t + w):
            bits, carries, rest = list(cols[c]) + chain, [], []
            while len(bits) >= 4:
                x, bits = bits[:4], bits[4:]
                s, cy = cell(net, *x)
                log.append((f'b{k}', c, comp))
                nxt[c].append(s)
                carries.append(cy)
                if and4 and c == top:
                    nxt[c + 1].append(net.AND(net.AND(x[0], x[1]), net.AND(x[2], x[3])))
                    log.append((f'b{k}', c, 'and4'))
            rest = bits
            nxt[c] += rest
            if c < top:
                chain = carries
            else:
                nxt[c + 1] += carries
        cols = nxt
    return cols


def cls(n=8, t=4, w=4, enc='cae1', comp='a4t2c1', ctm='ctm2', and4=True, zero_fix=False):
    """Signed n x n CLS-truncated approximate Booth multiplier (netlist + Python model)."""
    assert n % 2 == 0 and 2 <= t and t + w <= n
    net = Net()
    a, b = net.bus('a', n), net.bus('b', n)
    cols = columns(net, a, b, t, w, enc, zero_fix)
    log = []
    if comp != 'exact':
        cols = band_stages(net, cols, t, w, comp, and4 and comp == 'a4t2c1', log)
    word = cls_ctm.bits(net, a, b, t, ctm_table(ctm, t, n))
    nz = net.any(b) if zero_fix else ONE
    for c, bit in enumerate(word):
        cols[c].append(net.name(net.AND(bit, nz), f'ctm_{c}'))
    x, y, tree = reduce(net, [cols], 0)
    return Multiplier(net, n, True, x, y, log + tree)


def paper(name, n=8, t=4, w=4, zero_fix=False):
    return cls(n, t, w, zero_fix=zero_fix, **PAPER[name])
