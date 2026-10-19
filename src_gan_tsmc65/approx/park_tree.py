"""Grouped 4:2-compressor reduction of Park, Kung & Lee, IEEE TCAS-II 70(3) 2023 (Fig. 1).

Cells (eqs. 2-3):
  c42       exact 4:2 compressor with horizontal carry: inputs p0..p3 + cin, outputs sum
            (column i), carry (column i + 1, next stage) and cout (column i + 1, the cin of the
            next compressor of the same group); cout does not depend on cin.
  c42_park  the paper's approximate compressor: sum = p0, carry = p2 p3 (p1 ignored, no
            cin / cout). Used in the wA least significant columns.
  fa, ha    exact full / half adders (Fig. 1 keeps them exact in the approximate region).

Stages follow Fig. 1: a stage has a target height d (Dadda, 2, 4, 8, ...); the first stage
works on groups of four partial-product rows (each group has its own compressor carry chain),
later stages on one group. In column i the planner must remove h - d bits (h counts the bits
of all groups, the pending cins and the carries arriving from column i - 1); per group, in
group order:
  pending cin: >= 3 bits -> c42 (padded with 0), 2 bits -> fa(b0, b1, cin), 1 bit -> ha, 0 -> cin
               stays as a bit (the chain must be closed);
  else, need >= 2: a compressor on the first 4 bits (c42_park in an approximate column, where 3
               bits are padded with a constant 0 as the '0' dots of Fig. 1; c42 with cin = 0
               otherwise), or fa on 3 bits in an exact column;
  else, need >= 1 and >= 2 bits: ha.
The next stage lists column i as [group-0 sums, group-0 rest, carries into column i,
group-1 sums, group-1 rest, ...]; a compressor takes the first four bits of its group as
(p0, p1, p2, p3). With the Booth rows of park.py this reproduces every cell of Fig. 1.
"""
from .cells import fa, ha
from .netlist import ZERO


def _mux(net, s, x1, x0):
    return net.OR(net.AND(s, x1), net.AND(net.NOT(s), x0))


def c42(net, p0, p1, p2, p3, cin):
    """Exact 4:2 compressor, eq. (2): (sum, carry, cout)."""
    x01 = net.XOR(p0, p1)
    x4 = net.XOR(x01, net.XOR(p2, p3))
    return net.XOR(x4, cin), _mux(net, x4, cin, p3), _mux(net, x01, p2, p0)


def c42_park(net, p0, p1, p2, p3):
    """Approximate 4:2 compressor, eq. (3): (sum, carry) = (p0, p2 p3)."""
    return p0, net.AND(p2, p3)


def _cells(net, bits, cin, i, need, wa, tag, log):
    """Cells of one group in column i -> (sums, rest, carries, cout, bits removed)."""
    k = len(bits)
    if cin is not None:
        if k >= 3:
            s, c, co = c42(net, *(bits + [ZERO])[:4], cin)
            log.append((tag, i, 'c42'))
            return [s], bits[4:], [c], co, min(k, 4)
        if k == 2:
            s, c = fa(net, bits[0], bits[1], cin)
            log.append((tag, i, 'fa'))
            return [s], [], [c], None, 2
        if k == 1:
            s, c = ha(net, bits[0], cin)
            log.append((tag, i, 'ha'))
            return [s], [], [c], None, 1
        return [], [cin], [], None, 0
    if need >= 2 and i < wa and k >= 3:
        s, c = c42_park(net, *(bits + [ZERO])[:4])
        log.append((tag, i, 'c42_park'))
        return [s], bits[4:], [c], None, min(k, 4) - 1
    if need >= 2 and k >= 4:
        s, c, co = c42(net, *bits[:4], ZERO)
        log.append((tag, i, 'c42'))
        return [s], bits[4:], [c], co, 3
    if need >= 2 and k == 3:
        s, c = fa(net, *bits)
        log.append((tag, i, 'fa'))
        return [s], [], [c], None, 2
    if need >= 1 and k >= 2:
        s, c = ha(net, bits[0], bits[1])
        log.append((tag, i, 'ha'))
        return [s], bits[2:], [c], None, 1
    return [], bits, [], None, 0


def stage(net, groups, d, wa, tag, log):
    """One reduction stage over `groups` (lists of columns) -> the next stage's columns."""
    width = len(groups[0])
    out = []
    carries = [[] for _ in range(width + 1)]
    cins = [None] * len(groups)
    for i in range(width):
        h = (sum(len(g[i]) for g in groups) + len(carries[i])
             + sum(c is not None for c in cins))
        need = h - d
        col = []
        for gi, g in enumerate(groups):
            sums, rest, cs, cins[gi], removed = _cells(net, list(g[i]), cins[gi], i, need,
                                                       wa, f'{tag}g{gi}', log)
            need -= removed
            carries[i + 1] += cs
            col += sums + rest + (carries[i] if gi == 0 else [])
        out.append(col)
    return out


def reduce(net, groups, wa):
    """Reduce grouped columns to two rows -> (x, y, log); carries out of the top column drop."""
    log = []
    height = max(sum(len(g[i]) for g in groups) for i in range(len(groups[0])))
    k = 0
    for d in [h for h in (32, 16, 8, 4, 2) if h < height]:
        k += 1
        groups = [stage(net, groups, d, wa, f's{k}', log)]
    while max(map(len, groups[0])) > 2:
        k += 1
        groups = [stage(net, groups, 2, wa, f's{k}', log)]
    cols = groups[0]
    x = [c[0] if len(c) > 0 else ZERO for c in cols]
    y = [c[1] if len(c) > 1 else ZERO for c in cols]
    return x, y, log
