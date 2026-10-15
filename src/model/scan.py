"""Chunked parallel selective scan (training only; the golden model runs it token by token)."""
import torch


def selective_scan(u, dt, A, B, C, chunk=16):
    """h_t = exp(dt_t A) h_{t-1} + dt_t B_t u_t ;  y_t = C_t . h_t   (D term added by the caller).

    u, dt: [b, T, E]; A: [E, N]; B, C: [b, T, N]. Returns y [b, T, E].
    """
    b, T, E = u.shape
    N = A.shape[1]
    h = u.new_zeros(b, E, N)
    ys = []
    for t0 in range(0, T, chunk):
        sl = slice(t0, min(t0 + chunk, T))
        L = sl.stop - sl.start
        la = dt[:, sl, :, None] * A                                  # log dA  [b, L, E, N]
        cum = la.cumsum(1)
        seg = cum[:, :, None] - cum[:, None]                         # [b, t, s, E, N]
        causal = torch.ones(L, L, dtype=torch.bool, device=u.device).tril()
        decay = torch.exp(seg.masked_fill(~causal[None, :, :, None, None], float('-inf')))
        x = (dt[:, sl] * u[:, sl])[..., None] * B[:, sl, None, :]   # dt B u  [b, L, E, N]
        hs = torch.einsum('btsen,bsen->bten', decay, x) + torch.exp(cum) * h[:, None]
        ys.append(torch.einsum('bten,btn->bte', hs, C[:, sl]))
        h = hs[:, -1]
    return torch.cat(ys, 1)
