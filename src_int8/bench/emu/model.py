"""The golden HwModel with every INT8 weight x activation product looked up in a mul8 table.

These are exactly the products the RTL routes through mq_mul8 (docs/mul8_swap.md): the dots of
W_in_x, W_in_z, W_x, W_dt, W_out, E_out and the two conv taps. The golden layer modules are
patched for the duration of `approx(table)`; everything else is the bit-exact golden.
"""
from contextlib import contextmanager

import numpy as np

from ...golden.layers import block, conv, proj, scan
from ...golden.ops.lane import mac, rq, sh
from ...golden.ops.nlu import sigmoid
from ...golden.layers.shifts import SH_U


def _dot(table):
    def dot(W, x, ps=0, init=0):
        assert ps == 0
        W, x = np.asarray(W, np.int64) + 128, np.asarray(x, np.int64) + 128
        return np.int64(init) + table[W, x[..., None, :]].sum(-1)
    return dot


def _in_x_conv(table, dot):
    def in_x_conv(xn, cv, L):          # golden.layers.conv.in_x_conv with the taps via the table
        xi = rq(dot(L['W_in_x'], xn), L['rq_in_x'], 8)
        acc = (table[np.asarray(L['conv_w0'], np.int64) + 128, np.asarray(cv, np.int64) + 128] +
               table[np.asarray(L['conv_w1'], np.int64) + 128, np.asarray(xi, np.int64) + 128])
        xc = rq(acc, L['rq_conv'], 16, addend=L['cb'])
        u = sh(mac(0, xc, sigmoid(xc), 0), SH_U, 8)
        return xi, u, xc
    return in_x_conv


@contextmanager
def approx(table):
    dot = _dot(np.asarray(table, np.int64))
    saved = [(m, n, getattr(m, n)) for m, n in
             ((proj, 'dot'), (scan, 'dot'), (conv, 'dot'), (block, 'in_x_conv'))]
    for m, n, _ in saved:
        setattr(m, n, _in_x_conv(table, dot) if n == 'in_x_conv' else dot)
    try:
        yield
    finally:
        for m, n, f in saved:
            setattr(m, n, f)
