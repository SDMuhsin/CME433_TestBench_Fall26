"""Fake-quantisation primitives with straight-through gradients (spec section 9).

`fq(x, fmt)` rounds a float tensor to a `Fmt` of golden/ops/formats.py (clip, then round to
the format LSB) and `fq_rows(w)` applies the exporter's per-row symmetric INT8 rule to a
weight matrix, with the row scale recomputed from the current weights (max-abs, detached).
"""
import torch

from ...golden.ops.formats import W_MAX


def round_ste(x):
    """round() in the forward pass, identity gradient."""
    return x + (torch.round(x) - x).detach()


def fq(x, fmt):
    """Clip x to fmt's range and round to its LSB (gradient 1 inside the range, 0 outside)."""
    q = torch.clamp(x * (2.0 ** fmt.frac), float(fmt.lo), float(fmt.hi))
    return round_ste(q) * fmt.scale


def row_scales(w):
    """Exporter rule: s_row = max_k |w[row, k]| / 127; an all-zero row gets 1."""
    s = w.detach().abs().amax(-1, keepdim=True) / W_MAX
    return torch.where(s > 0, s, torch.ones_like(s))


def fq_rows(w):
    """Per-row symmetric INT8 fake quantisation of w [..., rows, k] (scale detached)."""
    s = row_scales(w)
    return round_ste(torch.clamp(w / s, -W_MAX, W_MAX)) * s
