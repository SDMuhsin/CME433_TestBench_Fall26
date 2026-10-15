"""One Mamba block in the spec 5.2 order, and the final norm + logits rows."""
from .conv import in_x_conv
from .norm import rmsnorm
from .proj import logits, out_proj, x_proj
from .scan import channel


def mamba_block(x, conv, h, L, cfg, probe=None):
    """x [b, 64] Q7.8, conv [b, 96] XI, h [b, 96, 4] Q6.17 -> (x', conv' = xi, h').

    If `probe` is a dict, every intermediate tensor is stored in it (vector generation)."""
    xn = rmsnorm(x)
    xi, u, xc = in_x_conv(xn, conv, L)
    dl, B, C = x_proj(u, L, cfg)
    hn, g, mid = channel(dl, B, C, u, xn, h, L)
    xo = out_proj(g, x, L)
    if probe is not None:
        probe.update(xn=xn, xi=xi, xc=xc, u=u, dl=dl, B=B, C=C, g=g, x_out=xo, **mid)
    return xo, xi, hn


def final_logits(x, E_out, rq_logits):
    return logits(rmsnorm(x), E_out, rq_logits)
