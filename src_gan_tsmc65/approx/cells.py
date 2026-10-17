"""Adder cells for partial-product reduction: exact half / full adder and the approximate
half adder, full adder and 4:2 compressor of Venkatachalam & Ko, IEEE TVLSI 25(5) 2017,
eqs. (2)-(4). Each cell maps its inputs (x1, x2, ...) to (sum, carry); the carry has twice the
weight of the sum. Input order matters for the approximate cells and follows the paper.
"""


def ha(net, x1, x2):
    return net.XOR(x1, x2), net.AND(x1, x2)


def fa(net, x1, x2, x3):
    t = net.XOR(x1, x2)
    return net.XOR(t, x3), net.OR(net.AND(x1, x2), net.AND(t, x3))


def vk_ha(net, x1, x2):
    """(2): Sum = x1 + x2 (OR), Carry = x1 x2. Wrong (by +1) only for x1 = x2 = 1."""
    return net.OR(x1, x2), net.AND(x1, x2)


def vk_fa(net, x1, x2, x3):
    """(3): W = x1 + x2, Sum = W xor x3, Carry = W x3. Wrong (by -1) only for x1 = x2 = 1."""
    w = net.OR(x1, x2)
    return net.XOR(w, x3), net.AND(w, x3)


def vk_c42(net, x1, x2, x3, x4):
    """(4): W1 = x1 x2, W2 = x3 x4, Sum = (x1 xor x2) + (x3 xor x4) + W1 W2, Carry = W1 + W2.
    Two outputs only (no cin / cout); wrong by +-1 in 5 of 16 input cases."""
    w1, w2 = net.AND(x1, x2), net.AND(x3, x4)
    s = net.any([net.XOR(x1, x2), net.XOR(x3, x4), net.AND(w1, w2)])
    return s, net.OR(w1, w2)


# name -> (cell function, number of inputs); a cell reduces the column height by inputs - 1
CELLS = {'ha': (ha, 2), 'fa': (fa, 3), 'vk_ha': (vk_ha, 2), 'vk_fa': (vk_fa, 3),
         'vk_c42': (vk_c42, 4)}
EXACT = ('fa', 'ha')
VK_HA_FA = ('vk_fa', 'vk_ha')
VK_ALL = ('vk_c42', 'vk_fa', 'vk_ha')
