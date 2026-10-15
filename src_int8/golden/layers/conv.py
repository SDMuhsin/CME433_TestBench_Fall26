"""in_x projection, width-2 depthwise conv and SiLU (spec 5.2 'in_x + conv')."""
from ..ops.lane import dot, mac, rq, sh
from ..ops.nlu import sigmoid
from .shifts import SH_U


def in_x_conv(xn, conv, L):
    """xn [b, 64] XN, conv [b, 96] previous xi -> (xi [b, 96] XI, u [b, 96] U, xc [b, 96] XC)."""
    xi = rq(dot(L['W_in_x'], xn), L['rq_in_x'], 8)
    acc = mac(mac(0, L['conv_w0'], conv, 0), L['conv_w1'], xi, 0)
    xc = rq(acc, L['rq_conv'], 16, addend=L['cb'])
    u = sh(mac(0, xc, sigmoid(xc), 0), SH_U, 8)
    return xi, u, xc
