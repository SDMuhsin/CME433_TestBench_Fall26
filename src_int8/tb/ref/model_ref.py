"""Spec-formula reference of one mq_chip token step (spec.md 5.2), the parameter set (3.2) and
the per-token host stream (section 7), all in Python ints.

This is Team B's stand-in for src_int8/golden: `random_params(seed)` makes an integer parameter
set that satisfies every range of spec 3.2 (random values, not a trained model), `token_stream`
packs it exactly as section 7, and `RefModel.step_stream` consumes that byte stream in the order
the microcode does, so isa_sim and the chip TB can be checked against it bit for bit.
"""
import random

from .intmath import mac, rq_w, sat, sext, sh_w
from .memmap import CFG
from . import nlu_ref as nlu

STREAM_BYTES = 54280


# ---------------------------------------------------------------- parameters
def _rq(rng, s_nom):
    return (rng.randrange(1 << 14, 1 << 15), max(1, min(47, s_nom + rng.randrange(-1, 2))))


def _w8(rng, n):
    return [rng.randrange(-127, 128) for _ in range(n)]


def random_params(seed=1, cfg=CFG):
    """Random integer parameter set in the formats of spec 3.2 (reasonable requant shifts)."""
    rng = random.Random(seed)
    D, E, V, R, N = cfg['d_model'], cfg['d_inner'], cfg['vocab'], cfg['dt_rank'], cfg['d_state']
    blocks = []
    for _ in range(cfg['n_layer']):
        blocks.append(dict(
            W_in_x=[_w8(rng, D) for _ in range(E)], RQ_in=[_rq(rng, 24) for _ in range(E)],
            w0=_w8(rng, E), w1=_w8(rng, E), RQ_conv=[_rq(rng, 19) for _ in range(E)],
            cb=[rng.randrange(-512, 512) for _ in range(E)],
            W_x=[_w8(rng, E) for _ in range(R + 2 * N)],
            RQ_x=[_rq(rng, 25) for _ in range(R + 2 * N)],
            b_dt=[rng.randrange(-1024, 1024) for _ in range(E)],
            W_dt=[_w8(rng, R) for _ in range(E)], RQ_dt=[_rq(rng, 18) for _ in range(E)],
            A=[[-max(1, round(2.0 ** rng.uniform(-6, 4) * 128)) for _ in range(N)] for _ in range(E)],
            Dd=_w8(rng, E),
            W_in_z=[_w8(rng, D) for _ in range(E)], RQ_z=[_rq(rng, 21) for _ in range(E)],
            W_out=[_w8(rng, E) for _ in range(D)], RQ_out=[_rq(rng, 22) for _ in range(D)]))
    return dict(cfg=cfg,
                E_in=[[rng.randrange(-768, 768) for _ in range(D)] for _ in range(V)],
                blocks=blocks,
                E_out=[_w8(rng, D) for _ in range(V)], RQ_e=[_rq(rng, 22) for _ in range(V)])


# ---------------------------------------------------------------- stream (section 7)
def _le(v, nbytes):
    return list((v & ((1 << (8 * nbytes)) - 1)).to_bytes(nbytes, 'little'))


def _rq_bytes(pair):
    M, s = pair
    return _le(M, 2) + [s]


def token_stream(P, token):
    """Per-token byte stream (list of 54,280 ints 0..255)."""
    cfg = P['cfg']
    D, E, V, R, N = cfg['d_model'], cfg['d_inner'], cfg['vocab'], cfg['dt_rank'], cfg['d_state']
    out = []
    for v in P['E_in'][token]:
        out += _le(v, 2)
    for L in P['blocks']:
        for d in range(E):
            out += [w & 0xFF for w in L['W_in_x'][d]] + _rq_bytes(L['RQ_in'][d])
            out += [L['w0'][d] & 0xFF, L['w1'][d] & 0xFF] + _rq_bytes(L['RQ_conv'][d]) + _le(L['cb'][d], 2)
        for j in range(R + 2 * N):
            out += [w & 0xFF for w in L['W_x'][j]] + _rq_bytes(L['RQ_x'][j])
        for d in range(E):
            out += _le(L['b_dt'][d], 2) + [w & 0xFF for w in L['W_dt'][d]] + _rq_bytes(L['RQ_dt'][d])
            for n in range(N):
                out += _le(L['A'][d][n], 2)
            out += [L['Dd'][d] & 0xFF] + [w & 0xFF for w in L['W_in_z'][d]] + _rq_bytes(L['RQ_z'][d])
        for i in range(D):
            out += [w & 0xFF for w in L['W_out'][i]] + _rq_bytes(L['RQ_out'][i])
    for v in range(V):
        out += [w & 0xFF for w in P['E_out'][v]] + _rq_bytes(P['RQ_e'][v])
    assert len(out) == STREAM_BYTES, len(out)
    return out


# ---------------------------------------------------------------- the token step (5.2)
class _Stream:
    def __init__(self, data):
        self.d, self.pos = data, 0

    def s8(self):
        self.pos += 1
        return sext(self.d[self.pos - 1], 8)

    def s16(self):
        self.pos += 2
        return sext(self.d[self.pos - 2] | self.d[self.pos - 1] << 8, 16)

    def rq(self):
        self.pos += 3
        return (self.d[self.pos - 3] | self.d[self.pos - 2] << 8, self.d[self.pos - 1])


class RefModel:
    """Integer state machine of spec 5.2; `step_stream(bytes)` -> 128 INT16 logits."""

    def __init__(self, cfg=CFG):
        self.cfg = cfg
        E, N, D = cfg['d_inner'], cfg['d_state'], cfg['d_model']
        self.H = [[[0] * N for _ in range(E)] for _ in range(cfg['n_layer'])]
        self.CONV = [[0] * E for _ in range(cfg['n_layer'])]
        self.X, self.XN, self.U, self.DBC = [0] * D, [0] * D, [0] * E, [0] * (cfg['dt_rank'] + 2 * N)
        self.LOGITS = [0] * cfg['vocab']

    def reset_state(self):
        for l in range(self.cfg['n_layer']):
            for d in range(self.cfg['d_inner']):
                self.H[l][d] = [0] * self.cfg['d_state']
            self.CONV[l] = [0] * self.cfg['d_inner']

    def rmsnorm(self):
        acc = 16
        for x in self.X:
            acc = mac(acc, x, x, 6)
        r = nlu.rsqrt(acc)
        self.XN = [sh_w(mac(0, x, r, 0), 12, 8) for x in self.X]

    def step_stream(self, data):
        cfg = self.cfg
        D, E, V, R, N = cfg['d_model'], cfg['d_inner'], cfg['vocab'], cfg['dt_rank'], cfg['d_state']
        S = _Stream(data)
        self.X = [S.s16() for _ in range(D)]
        for l in range(cfg['n_layer']):
            H, CONV = self.H[l], self.CONV[l]
            self.rmsnorm()
            for d in range(E):
                acc = 0
                for k in range(D):
                    acc = mac(acc, S.s8(), self.XN[k], 0)
                M, s = S.rq()
                xi = rq_w(acc, M, s, 8)
                acc = mac(0, S.s8(), CONV[d], 0)
                acc = mac(acc, S.s8(), xi, 0)
                CONV[d] = xi
                M, s = S.rq()
                cb = S.s16()
                xc = rq_w(acc, M, s, 16, cb)
                sig = nlu.sigmoid(xc)
                self.U[d] = sh_w(mac(0, xc, sig, 0), 19, 8)
            for j in range(R + 2 * N):
                acc = 0
                for k in range(E):
                    acc = mac(acc, S.s8(), self.U[k], 0)
                M, s = S.rq()
                self.DBC[j] = rq_w(acc, M, s, 8)
            DL, B, C = self.DBC[:R], self.DBC[R:R + N], self.DBC[R + N:]
            for d in range(E):
                b = S.s16()
                acc = 0
                for r in range(R):
                    acc = mac(acc, S.s8(), DL[r], 0)
                M, s = S.rq()
                dt_pre = rq_w(acc, M, s, 16, b)
                dt = nlu.softplus(dt_pre)
                u = self.U[d]
                for n in range(N):
                    A = S.s16()
                    bu = sh_w(mac(0, B[n], u, 0), 0, 16)
                    dA = nlu.exp2(mac(0, dt, A, 0))
                    acc = mac(0, H[d][n], dA, 15)
                    acc = mac(acc, dt, bu, 4)
                    H[d][n] = sh_w(acc, 0, 24)
                Dd = S.s8()
                acc = 0
                for n in range(N):
                    acc = mac(acc, H[d][n], C[n], 11)
                acc = mac(acc, Dd, u, 0)
                y = sh_w(acc, 1, 16)
                acc = 0
                for k in range(D):
                    acc = mac(acc, S.s8(), self.XN[k], 0)
                M, s = S.rq()
                z = rq_w(acc, M, s, 16)
                sig = nlu.sigmoid(z)
                sz = sh_w(mac(0, z, sig, 0), 15, 16)
                self.U[d] = sh_w(mac(0, y, sz, 0), 13, 8)
            for i in range(D):
                xr = self.X[i]
                acc = 0
                for k in range(E):
                    acc = mac(acc, S.s8(), self.U[k], 0)
                M, s = S.rq()
                self.X[i] = rq_w(acc, M, s, 16, xr)
        self.rmsnorm()
        for v in range(V):
            acc = 0
            for k in range(D):
                acc = mac(acc, S.s8(), self.XN[k], 0)
            M, s = S.rq()
            self.LOGITS[v] = rq_w(acc, M, s, 16)
        assert S.pos == len(data) == STREAM_BYTES
        return list(self.LOGITS)

    # ---------------------------------------------------------------- memory images
    def bmem_image(self):
        """512-byte BMEM image after a token (LOGITS alias over X/U/DBC/TMP)."""
        img = [0] * 512
        for k, v in enumerate(self.XN):
            img[k] = v & 0xFF
        for v, w in enumerate(self.LOGITS):
            img[0x40 + 2 * v], img[0x41 + 2 * v] = w & 0xFF, (w >> 8) & 0xFF
        for l in range(self.cfg['n_layer']):
            for d, v in enumerate(self.CONV[l]):
                img[0x140 + 0x60 * l + d] = v & 0xFF
        return img

    def hmem_image(self):
        """768 INT24 entries, entry = 384 l + 4 d + n."""
        out = []
        for l in range(self.cfg['n_layer']):
            for d in range(self.cfg['d_inner']):
                out += [h & 0xFFFFFF for h in self.H[l][d]]
        return out


def params(seed=1):
    return random_params(seed)


def host_image(model):
    """Host byte view (0x0000..0x11FF) of the memories: H as 4-byte slots, BMEM at 0x1000."""
    img = []
    for h in model.hmem_image():
        img += [h & 0xFF, (h >> 8) & 0xFF, (h >> 16) & 0xFF, 0]
    img += [0] * (0x1000 - len(img))
    return img + model.bmem_image()


def logits_from_host(img):
    return [sext(img[0x1040 + 2 * v] | img[0x1041 + 2 * v] << 8, 16) for v in range(128)]


__all__ = ['params', 'random_params', 'token_stream', 'RefModel', 'host_image', 'STREAM_BYTES',
           'sat']
