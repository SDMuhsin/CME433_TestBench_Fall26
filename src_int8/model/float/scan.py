"""Chunked parallel selective scan (training only; the golden model runs it token by token).

Two entry points: `selective_scan` takes the continuous A (dA = exp(dt A)), as the float
model; `scan_with_decay` takes the per-step decay factors dA directly (the QAT model, whose
dA is the fake-quantised exp2 LUT output), with an optional state clip.
"""
import torch

LOG2_ZERO = -64.0   # log2 of a zero decay factor: 2^-64 * anything in range underflows to 0


def scan_with_decay(u, dt, dA, B, C, chunk=16, h_clip=None):
    """h_t = dA_t h_{t-1} + dt_t B_t u_t ;  y_t = C_t . h_t   (D term added by the caller).

    u, dt: [b, T, E]; dA: [b, T, E, N] in [0, 1]; B, C: [b, T, N]. Returns y [b, T, E].
    h_clip: if given, the state is clamped to +-h_clip at every position (spec section 9).
    """
    b, T, E = u.shape
    N = dA.shape[-1]
    h = u.new_zeros(b, E, N)
    la = torch.where(dA > 0, torch.log2(dA.clamp_min(1e-30)), torch.full_like(dA, LOG2_ZERO))
    ys = []
    for t0 in range(0, T, chunk):
        sl = slice(t0, min(t0 + chunk, T))
        L = sl.stop - sl.start
        cum = la[:, sl].cumsum(1)                                   # [b, L, E, N]
        seg = cum[:, :, None] - cum[:, None]                        # [b, t, s, E, N]
        causal = torch.ones(L, L, dtype=torch.bool, device=u.device).tril()
        decay = torch.exp2(seg.masked_fill(~causal[None, :, :, None, None], float('-inf')))
        x = (dt[:, sl] * u[:, sl])[..., None] * B[:, sl, None, :]  # dt B u  [b, L, E, N]
        hs = torch.einsum('btsen,bsen->bten', decay, x) + torch.exp2(cum) * h[:, None]
        if h_clip is not None:
            hs = hs.clamp(-h_clip, h_clip)
        ys.append(torch.einsum('bten,btn->bte', hs, C[:, sl]))
        h = hs[:, -1]
    return torch.cat(ys, 1)


def selective_scan(u, dt, A, B, C, chunk=16):
    """Float model: dA = exp(dt A) with A [E, N] negative."""
    return scan_with_decay(u, dt, torch.exp(dt[..., None] * A), B, C, chunk)
