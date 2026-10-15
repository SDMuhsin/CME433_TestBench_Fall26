"""Per-channel section of spec 5.2: dt, the selective-scan step, y, z, the gate -> G."""
from ..ops.formats import sat
from ..ops.lane import dot, mac, rq, sh
from ..ops.nlu import exp2, silu16, softplus
from .shifts import PS_DTBU, PS_HC, PS_HDA, SH_G, SH_Y


def dt_of(dl, L):
    """dt_pre = rq_16(W_dt dl, b_dt); dt = softplus(dt_pre) Q3.12 -> (dt, dt_pre) [b, 96]."""
    dt_pre = rq(dot(L['W_dt'], dl), L['rq_dt'], 16, addend=L['b_dt'])
    return softplus(dt_pre), dt_pre


def scan_step(h, u, dt, B, L):
    """h [b, 96, 4] Q6.17 -> h' (INT24); also returns dA [b, 96, 4] and p for probes."""
    bu = sat(mac(0, B[:, None, :], u[:, :, None], 0), 16)            # exact product, 2^-9
    p = mac(0, dt[..., None], L['A2'][None], 0)                        # Q11.19
    dA = exp2(p)
    hn = sat(mac(mac(0, h, dA, PS_HDA), dt[..., None], bu, PS_DTBU), 24)
    return hn, dA, p


def y_of(hn, u, C, L):
    """y = sh_16(sum_n rsh(h[d, n] C[n], 11) + D[d] u[d], 1) Q6.9."""
    acc = 0
    for n in range(hn.shape[-1]):
        acc = mac(acc, hn[..., n], C[..., n:n + 1], PS_HC)
    return sh(mac(acc, L['D'], u, 0), SH_Y, 16)


def gate(y, xn, L):
    """z = rq_16(W_in_z xn); sz = SiLU(z); G = sh_8(y * sz, 13)."""
    z = rq(dot(L['W_in_z'], xn), L['rq_z'], 16)
    sz = silu16(z)
    return sh(mac(0, y, sz, 0), SH_G, 8), z, sz


def channel(dl, B, C, u, xn, h, L):
    """The whole per-d section: -> (h', G [b, 96]) plus a dict of the intermediates."""
    dt, dt_pre = dt_of(dl, L)
    hn, dA, p = scan_step(h, u, dt, B, L)
    y = y_of(hn, u, C, L)
    g, z, sz = gate(y, xn, L)
    return hn, g, dict(dt=dt, dt_pre=dt_pre, dA=dA, p=p, y=y, z=z, sz=sz)
