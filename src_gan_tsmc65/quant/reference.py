"""Plain-integer reference of the chip pipeline (Python ints, one latent, no numpy arithmetic):
an independent check of golden/model.py used when the reference vectors are written."""


def _wrap(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def _layer(W, b, x, ma, mb, s, acc_w):
    out = []
    for r in range(len(W)):
        acc = _wrap(sum(int(w) * int(v) for w, v in zip(W[r], x)), acc_w)
        out.append((acc * ma + int(b[r]) * mb + (1 << (s - 1))) >> s)
    return out


def _pixel(pre, rom):
    tm = 4 << 20
    idx = (min(max(pre, -tm), tm) + tm) >> 8
    v = 0
    for bit in range(7, -1, -1):
        if rom[v | 1 << bit] <= idx:
            v |= 1 << bit
    return v - 128


def pixels(zq, m):
    s, aw, qm = m['S'], m['acc_w'], (1 << (m['width'] - 1)) - 1
    relu = lambda xs: [min(max(x, 0), qm) for x in xs]
    h0 = relu(_layer(m['W0'], m['b0'], zq, m['MA0'], m['MB0'], s, aw))
    h2 = relu(_layer(m['W2'], m['b2'], h0, m['MA2'], m['MB2'], s, aw))
    rom = [int(t) for t in m['rom']]
    return [_pixel(p, rom) for p in _layer(m['W4'], m['b4'], h2, m['MW4'], m['MB4'], s, aw)]
