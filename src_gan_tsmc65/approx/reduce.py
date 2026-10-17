"""Column-wise partial-product reduction (Dadda-style stages) with per-column cell sets.

Each stage has a target height d. In column i, with h bits and c carries arriving from the
cells of column i-1 in the same stage, the planner must remove h + c - d bits; it takes the
first bits of the column (in their listed order) into the largest cells first: a 4:2
compressor removes 3, a full adder 2, a half adder 1. Sums stay in the column, carries move to
column i+1. By default the next stage lists a column as [cell sums, untouched bits, incoming
carries]; `order` can override this.
When a column cannot reach the target (e.g. full adders only), later stages continue; extra
stages with target 2 run until every column has at most two bits for the final adder.

`cells_of(col)` names the cells allowed in a column (from cells.CELLS, largest first). The
Dadda height sequence is 2, 3, 4, 6, 9, ... for full adders and 2, 3, 6, 12, ... when 4:2
compressors (4 bits -> sum + carry) are allowed, which reproduces the two stages of
Venkatachalam & Ko Fig. 2.
"""
from .cells import CELLS

DADDA = [2, 3, 4, 6, 9, 13, 19, 28, 42, 63]
DADDA_C42 = [2, 3, 6, 12, 24, 48]


def targets(max_height, seq):
    return [d for d in reversed(seq) if d < max_height]


def default_order(stage, col, sums, rest, carries):
    return sums + rest + carries


def _stage(net, cols, d, cells_of, log, stage, order):
    out_sums = [[] for _ in cols]
    rest = [[] for _ in cols]
    carries = [[] for _ in range(len(cols) + 1)]
    for i, col in enumerate(cols):
        need = len(col) + len(carries[i]) - d
        pos = 0
        for name in cells_of(i):
            fn, k = CELLS[name]
            while need >= k - 1 and len(col) - pos >= k:
                s, c = fn(net, *col[pos:pos + k])
                tag = f's{stage}_c{i}_{name}{pos}'
                out_sums[i].append(net.name(s, tag + '_s'))
                carries[i + 1].append(net.name(c, tag + '_c'))
                log.append((stage, i, name))
                pos += k
                need -= k - 1
        rest[i] = col[pos:]
    return [order(stage, i, out_sums[i], rest[i], carries[i]) for i in range(len(cols))]


def reduce(net, cols, cells_of, seq=DADDA, order=default_order):
    """Reduce `cols` (lists of node ids, column i = weight 2^i) to two rows. Returns
    (x, y, log): x[i], y[i] node ids (ZERO when absent); log lists (stage, column, cell).
    Carries out of the top column are dropped (results are mod 2^len(cols)). `order` lists a
    column for the next stage (the order decides which bit is x3 of an approximate FA)."""
    log = []
    stage = 0
    for d in targets(max(map(len, cols)), seq):
        stage += 1
        cols = _stage(net, cols, d, cells_of, log, stage, order)
    while max(map(len, cols)) > 2:
        stage += 1
        cols = _stage(net, cols, 2, cells_of, log, stage, order)
    x = [c[0] if len(c) > 0 else 0 for c in cols]
    y = [c[1] if len(c) > 1 else 0 for c in cols]
    return x, y, log
