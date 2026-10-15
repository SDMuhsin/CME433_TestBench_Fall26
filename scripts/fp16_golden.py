#!/usr/bin/env python3
"""Bit-accurate golden model of the FP16 e2e chip (spec: fp16/spec.md, section 3).

Arithmetic (normative, must match RTL bit for bit):
  * storage: IEEE binary16. On every FP16 *input* (z, W, b): exp==0 -> +0 (FTZ, sign dropped),
    exp==31 -> sign|0x7BFF (saturate, +-65504).  The exporter already applies this, so the
    hardware never sees such codes from a well-formed stream.
  * neuron r of a layer:  acc = fp32(b[r])                                 (exact)
                          for k = 0 .. K-1 (ascending):  acc = RNE32(acc + w[r,k]*x[k])
                          (the FP16xFP16 product is exact in FP32; one rounding per step)
    No FP32 subnormal / inf can occur (all non-zero values are multiples of 2^-48, |acc| < 2^40);
    exact cancellation gives +0.  The model asserts these invariants.
  * y = fp16(acc): |acc| < 2^-14 -> +0 (FTZ before rounding), else RNE to 10 fraction bits,
    rounded magnitude > 65504 -> +-65504 (saturate, never Inf).
  * ReLU layers: h = 0x0000 if sign(y) else y.
  * tanh layer: pix = #{ v in 1..255 : key(y) >= T[v] }, key = sign ? ~bits : bits|0x8000
    (16-bit ordered key); T = fp16_tanh_thresholds.memh, derived from
    pix(y) = clamp(floor((tanh(y)+1)*127.5 + 0.5), 0, 255) in float64 over every legal y.
Library module (repo copy of the phase-1 scratch golden_fp16.py, identical arithmetic).
Used by scripts/gen_fp16_stream.py and scripts/gen_fp16_tanh_rom.py. Needs numpy + torch (checkpoint load).
"""
from pathlib import Path
import numpy as np

REPO = Path(__file__).resolve().parent.parent
MNIST_CKPT = REPO / 'weights/mnist_gan_mlp/G--300.ckpt'
F16, F32, U16 = np.float16, np.float32, np.uint16


# ----------------------------------------------------------------------------- FP16 helpers
def canon16(bits):
    """FP16 input canonicalisation (FTZ + saturate), on uint16 bit patterns."""
    b = np.asarray(bits, dtype=U16).copy()
    e = (b >> 10) & 31
    b[e == 0] = 0
    s = e == 31
    b[s] = (b[s] & 0x8000) | 0x7BFF
    return b


def to_fp16_bits(x):
    """float64/float32 -> FP16 for export (host side): RNE, FTZ, saturate."""
    x = np.asarray(x, dtype=np.float64)
    with np.errstate(over='ignore'):
        h = x.astype(F16)           # RNE (numpy rounds directly from float64)
    b = h.view(U16).copy()
    b[np.isinf(h)] = (b[np.isinf(h)] & 0x8000) | 0x7BFF
    return canon16(b)


def f32_to_f16(acc):
    """Hardware output conversion: FTZ before rounding, RNE, saturate; +0 for zero."""
    acc = np.asarray(acc, dtype=F32)
    with np.errstate(over='ignore'):
        h = acc.astype(F16)         # IEEE RNE float32 -> float16
    b = h.view(U16).copy()
    b[np.isinf(h)] = (b[np.isinf(h)] & 0x8000) | 0x7BFF
    b[np.abs(acc) < F32(2.0 ** -14)] = 0   # FTZ on |acc| < 2^-14 (covers acc==0 -> +0)
    return b


def b16(bits):
    return np.asarray(bits, dtype=U16).view(F16).astype(F32)


def key16(bits):
    b = np.asarray(bits, dtype=np.uint32)
    return np.where(b & 0x8000, (~b) & 0xFFFF, b | 0x8000).astype(np.uint32)


# ----------------------------------------------------------------------------- tanh ROM
def pix_ref(y64):
    return np.clip(np.floor((np.tanh(y64) + 1.0) * 127.5 + 0.5), 0, 255).astype(np.int64)


def build_tanh_rom():
    allb = np.arange(65536, dtype=np.uint32).astype(U16)
    legal = canon16(allb) == allb            # FTZ'd/saturated codes never reach the tanh unit
    legal &= allb != 0x8000                  # -0 is never produced (zero results are +0)
    bl = allb[legal]
    k = key16(bl); order = np.argsort(k); bl, k = bl[order], k[order]
    p = pix_ref(b16(bl).astype(np.float64))
    assert np.all(np.diff(p) >= 0), 'pixel map not monotone in key order'
    T = np.zeros(256, dtype=np.uint32)
    for v in range(1, 256):
        idx = np.searchsorted(p, v, side='left')
        T[v] = k[idx] if idx < len(k) else 0x10000   # all 255 levels are reachable (asserted below)
    assert np.all(T[1:] < 0x10000) and np.all(np.diff(T[1:]) >= 0)
    # exhaustive check of the threshold search against the direct formula
    assert np.array_equal(tanh_pix(bl, T), p), 'threshold ROM mismatch'
    return T[1:].astype(np.uint32)            # 255 x 16 b, T[v] at index v-1


def tanh_pix(ybits, T):
    """Hardware: 8-step binary search == count of thresholds <= key (T ascending)."""
    TT = T[1:] if len(T) == 256 else T
    return np.searchsorted(TT, key16(ybits), side='right').astype(np.int64)


# ----------------------------------------------------------------------------- core layer
def layer(Wb, bb, xb, relu):
    """Wb [O,K] uint16, bb [O] uint16, xb [K] uint16 -> (y bits [O], acc fp32 [O])."""
    W = b16(canon16(Wb)); x = b16(canon16(xb))
    acc = b16(canon16(bb)).copy()                  # +0 for zero bias
    for k in range(W.shape[1]):                    # FIXED ORDER: bias first, then k = 0..K-1
        p = W[:, k] * x[k]                         # exact in fp32
        acc = (acc + p).astype(F32)                # one RNE per step (numpy fp32 add, no FMA)
    a = np.abs(acc)
    assert np.all(np.isfinite(acc)) and not np.any((a > 0) & (a < F32(2.0 ** -126))), 'fp32 invariant'
    acc = acc + F32(0.0)                           # canonical +0 (never -0 in HW; no-op otherwise)
    y = f32_to_f16(acc)
    if relu:
        y = np.where(y & 0x8000, 0, y).astype(U16)
    return y, acc


def run(P, zb, T):
    h0, a0 = layer(P['W0'], P['b0'], zb, True)
    h2, a2 = layer(P['W2'], P['b2'], h0, True)
    y4, a4 = layer(P['W4'], P['b4'], h2, False)
    return dict(h0=h0, h2=h2, y4=y4, pix=tanh_pix(y4, T), a0=a0, a2=a2, a4=a4)


# ----------------------------------------------------------------------------- export / I/O
def wr16(path, words):
    Path(path).write_text(''.join(f'{int(w):04x}\n' for w in words))


def load_params(ck):
    import torch
    sd = torch.load(ck, map_location='cpu', weights_only=False)
    sd = sd.get('state_dict', sd)
    f = {k: sd[k].double().numpy() for k in sd}
    P = {'W0': f['0.weight'], 'b0': f['0.bias'], 'W2': f['2.weight'], 'b2': f['2.bias'],
         'W4': f['4.weight'], 'b4': f['4.bias']}
    Q = {k: to_fp16_bits(v) for k, v in P.items()}
    st = {}
    for k, v in P.items():
        nz = v != 0
        st[k] = dict(max_abs=float(np.abs(v).max()),
                     ftz_flushed=int(np.sum(nz & (Q[k] == 0))),
                     saturated=int(np.sum(np.abs(v) > 65504)))
    return P, Q, st


def float_forward(P, z):
    h = np.maximum(P['W0'] @ z + P['b0'], 0)
    h = np.maximum(P['W2'] @ h + P['b2'], 0)
    return (np.tanh(P['W4'] @ h + P['b4']) + 1.0) * 127.5   # unrounded, chip 0..255 scale


def stream_words(Q, zb):
    """Host word stream (16-bit words; on the wire MSB byte first):
       z[0..63], then per layer, per output neuron r: b[r], W[r,0..K-1]."""
    w = [zb]
    for Wn, bn in (('W0', 'b0'), ('W2', 'b2'), ('W4', 'b4')):
        Wm, bv = Q[Wn], Q[bn]
        w.append(np.concatenate([bv[:, None], Wm], axis=1).reshape(-1))
    return np.concatenate(w).astype(U16)
