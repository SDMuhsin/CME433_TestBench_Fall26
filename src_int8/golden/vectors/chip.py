"""Chip vectors: stories -> per-token byte stream, expected INT16 logits and state dumps.

Each story starts from zero state (the host issues STATE_RESET before its first byte).
Files (format in docs/vectors.md):
  plan.memh    one line per token: bit 8 = state reset before the token, bits 7..0 = byte
  stream.memh  every token's weight stream, one byte per line (54,280 lines per token)
  logits.memh  every token's 128 logits, INT16 Q7.8, 4 hex digits
  h.memh       after every token: H0 then H1, 768 entries of INT24 Q6.17 (entry = 4 d + n), 6 digits
  conv.memh    after every token: CONV0 then CONV1, 192 bytes of INT8 (xi of this token)
  host.memh    after every token: the host-visible byte image, 0x1200 bytes (section 6 view)
"""
import numpy as np

from ..io.memmap import REGIONS, host_image
from ..io.stream import token_stream
from ..model import HwModel
from .common import write_memh


def bmem_image(model, logits):
    """BMEM 512 bytes as the chip leaves them after a token (regions of spec section 6)."""
    img = np.zeros(512, np.int64)
    b = lambda name: REGIONS[name][0] - 0x400
    z = np.asarray(logits, np.int64) & 0xFFFF
    img[b('LOGITS'):b('LOGITS') + 256] = np.stack([z & 0xFF, z >> 8], -1).reshape(-1)
    for l in range(len(model.conv)):
        img[b(f'CONV{l}'):b(f'CONV{l}') + 96] = model.conv[l][0] & 0xFF
    return img


def build(cfg, P, stories):
    """-> dict of lists: plan, stream (bytes), logits, h, conv, host."""
    out = dict(plan=[], stream=[], logits=[], h=[], conv=[], host=[])
    for story in stories:
        model = HwModel(cfg, P)
        for i, tok in enumerate(story):
            stream = token_stream(P, tok)
            z = model.step_stream(stream)[0]
            out['plan'].append((0x100 if i == 0 else 0) | tok)
            out['stream'].append(stream)
            out['logits'].append(z)
            out['h'].append(np.concatenate([h[0].reshape(-1) for h in model.h]))
            out['conv'].append(np.concatenate([c[0] for c in model.conv]))
            out['host'].append(np.frombuffer(host_image([h[0].reshape(-1) for h in model.h],
                                                        bmem_image(model, z).astype(np.uint8).tobytes()),
                                             np.uint8))
    return out


def write(out_dir, vec):
    out_dir.mkdir(parents=True, exist_ok=True)
    write_memh(out_dir / 'plan.memh', vec['plan'], 3)
    write_memh(out_dir / 'stream.memh', np.concatenate(vec['stream']), 2)
    write_memh(out_dir / 'logits.memh', np.concatenate(vec['logits']), 4)
    write_memh(out_dir / 'h.memh', np.concatenate(vec['h']), 6)
    write_memh(out_dir / 'conv.memh', np.concatenate(vec['conv']), 2)
    write_memh(out_dir / 'host.memh', np.concatenate(vec['host']), 2)


DEFAULT_STORIES = ('Once upon a time', 'Lily saw a dog.')
