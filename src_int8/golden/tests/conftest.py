"""Shared fixtures: the shipped parameter set, the QAT checkpoint and the validation corpus."""
import os
from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[2]
PARAMS = ROOT / 'golden' / 'params' / 'mamba_e96_int8.npz'
QAT_CKPT = ROOT / 'model' / 'checkpoints' / 'mamba_e96_qat.pt'
# Validation corpus: data/tinystories/val.bin (git-ignored; build it with scripts/prep_tinystories.sh)
VAL_BIN = Path(os.environ.get('MAMBA_VAL_BIN', ROOT.parent / 'data' / 'tinystories' / 'val.bin'))
CFG = dict(vocab=128, d_model=64, n_layer=2, d_inner=96, d_state=4, dt_rank=4)


@pytest.fixture(scope='session')
def shipped():
    from src_int8.golden.io.params import load_params
    if not PARAMS.exists():
        pytest.skip('no shipped parameters')
    return load_params(PARAMS)


@pytest.fixture(scope='session')
def qat_model():
    torch = pytest.importorskip('torch')
    if not QAT_CKPT.exists():
        pytest.skip('no QAT checkpoint')
    from src_int8.model.train.common import load_checkpoint
    return load_checkpoint(QAT_CKPT)


@pytest.fixture(scope='session')
def val_segments():
    from src_int8.model.data import eval_segments, load_bin
    if not VAL_BIN.exists():
        pytest.skip('no validation corpus')
    return eval_segments(load_bin(VAL_BIN), 256, 1024)


def random_params(rng, cfg=CFG):
    """A parameter set with random integers in the legal ranges (passes check_ranges)."""
    from src_int8.golden.io.params import LAYER_KEYS, shapes
    top, layer = shapes(cfg)

    def arr(k, shape):
        if k.startswith('rq_'):
            return np.stack([rng.integers(1 << 14, 1 << 15, shape[0]), rng.integers(1, 48, shape[0])], -1)
        if k == 'A2':
            return rng.integers(-32768, 0, shape)
        if k in ('E_in', 'cb', 'b_dt'):
            return rng.integers(-32768, 32768, shape)
        return rng.integers(-127, 128, shape)

    P = {k: arr(k, s).astype(np.int64) for k, s in top.items()}
    P['layers'] = [{k: arr(k, layer[k]).astype(np.int64) for k in LAYER_KEYS} for _ in range(cfg['n_layer'])]
    return P
