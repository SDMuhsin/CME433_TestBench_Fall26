"""Tanh output stage of e2e_requant: the 256-entry threshold ROM and its 8-step binary search."""
import re

import numpy as np

from ..common.paths import RTL

TM = 4 << 20                       # pre-activation clamp, +/-4.0 in Q20


def load_rom(path=RTL / 'seq' / 'e2e_tanh_rom.v'):
    """-> int64[256] thresholds T[v], parsed from the RTL case statement."""
    rom = {int(v): int(t) for v, t in re.findall(r"8'd(\d+): t = 15'd(\d+);", path.read_text())}
    assert sorted(rom) == list(range(256)), 'tanh ROM must have 256 entries'
    return np.array([rom[v] for v in range(256)], np.int64)


def tanh_pixel(pre, rom):
    """int8 pixel (pu - 128) for Q20 pre-activations `pre`, exactly as the RTL:
    idx = (clamp(pre, +/-TM) + TM) >> 8, pu = largest v with T[v] <= idx (binary search)."""
    idx = (np.clip(pre, -TM, TM) + TM) >> 8
    v = np.zeros_like(idx)
    for bit in range(7, -1, -1):
        cand = v | (1 << bit)
        v = np.where(rom[cand] <= idx, cand, v)
    return v - 128
