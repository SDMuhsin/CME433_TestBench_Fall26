"""End to end: golden BPB on the FP16 chip's validation crops (acceptance: <= 1.3955), and the
golden vs QAT fake-quant gap on a subset.  Slow (~1 min); select with -m e2e or run all."""
import math

import numpy as np
import pytest

from src_int8.golden.host.evaluate import bits_per_byte

TARGET_BPB = 1.3955


@pytest.mark.e2e
def test_golden_bpb_meets_target(shipped, val_segments):
    cfg, P = shipped
    bpb = bits_per_byte(cfg, P, val_segments)
    print(f'golden bpb {bpb:.4f}')
    assert bpb <= TARGET_BPB


@pytest.mark.e2e
def test_golden_close_to_fake_quant(shipped, qat_model, val_segments):
    torch = pytest.importorskip('torch')
    import torch.nn.functional as F
    from src_int8.model.qat.qmamba import q_forward
    cfg, P = shipped
    segs = val_segments[:32, :257]
    g = bits_per_byte(cfg, P, segs)
    with torch.no_grad():
        s = torch.as_tensor(segs)
        loss = F.cross_entropy(q_forward(qat_model, s[:, :-1]).flatten(0, 1), s[:, 1:].flatten()).item()
    q = loss / math.log(2)
    print(f'golden {g:.4f} fake-quant {q:.4f}')
    assert abs(g - q) / q < 0.01
