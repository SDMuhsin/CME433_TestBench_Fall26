"""The requantised GEMV rows: x_proj, out_proj (with residual addend) and the logits rows."""
from ..ops.lane import dot, rq


def x_proj(u, L, cfg):
    """u [b, 96] -> (DL [b, R], B [b, N], C [b, N]) INT8."""
    R, N = cfg['dt_rank'], cfg['d_state']
    dbc = rq(dot(L['W_x'], u), L['rq_x'], 8)
    return dbc[..., :R], dbc[..., R:R + N], dbc[..., R + N:R + 2 * N]


def out_proj(g, x, L):
    """X[i] = rq_16(sum_d W_out[i, d] g[d], addend X[i])."""
    return rq(dot(L['W_out'], g), L['rq_out'], 16, addend=x)


def logits(xn, E_out, rq_logits):
    """LOGITS[v] = rq_16(sum_k E_out[v, k] XN[k])."""
    return rq(dot(E_out, xn), rq_logits, 16)
