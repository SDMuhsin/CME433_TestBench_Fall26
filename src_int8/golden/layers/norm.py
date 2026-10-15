"""RMSNorm (spec 5.2): acc = 16 + sum rsh(x_i^2, 6); r = rsqrt(acc); XN_i = sh_8(x_i * r, 12)."""
import numpy as np

from ..ops.formats import EPS_INIT, fits, rsh
from ..ops.lane import mac, sh
from ..ops.nlu import rsqrt
from .shifts import PS_MS, SH_XN


def mean_square(x):
    """Mean square + 2^-12 in Q.16 (UINT32): per-term rounding of x_i^2 >> 6, order independent."""
    x = np.asarray(x, dtype=np.int64)
    assert fits(x, 16)
    acc = EPS_INIT + rsh(x * x, PS_MS).sum(-1)
    assert fits(acc, 32)
    return acc


def rmsnorm(x):
    """x [..., 64] Q7.8 -> XN [..., 64] INT8 (s = 2^-5). The gain is folded into the weights."""
    r = rsqrt(mean_square(x))
    return sh(mac(0, x, r[..., None], 0), SH_XN, 8)
