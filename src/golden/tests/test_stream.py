"""Weight-stream order round trip and memory-map sanity."""
import numpy as np

from src.golden.data.memmap import memory_map, sram_summary
from src.golden.data.stream import stream_words, token_stream, unpack_stream
from src.golden.data.weights import LAYER_KEYS

CFG = dict(vocab=128, d_model=64, n_layer=2, d_inner=64, d_state=4, dt_rank=4)
SHAPES = dict(W_in_x=(64, 64), W_in_z=(64, 64), conv_b=(64,), conv_w0=(64,), conv_w1=(64,),
              W_x=(12, 64), W_dt=(64, 4), b_dt=(64,), A2=(64, 4), D=(64,), W_out=(64, 64))


def _random_params(rng):
    r16 = lambda shape: rng.integers(0, 0x7BFF, size=shape).astype(np.uint16)
    return {'E_in': r16((128, 64)), 'E_out': r16((128, 64)),
            'layers': [{k: r16(SHAPES[k]) for k in LAYER_KEYS} for _ in range(2)]}


def test_stream_round_trip():
    P = _random_params(np.random.default_rng(0))
    words = token_stream(P, 65)
    assert len(words) == stream_words(CFG) == 36032
    emb, Q = unpack_stream(words, CFG)
    assert np.array_equal(emb, P['E_in'][65]) and np.array_equal(Q['E_out'], P['E_out'])
    for L, M in zip(P['layers'], Q['layers']):
        assert all(np.array_equal(L[k], M[k]) for k in LAYER_KEYS)


def test_memory_map_disjoint_and_fits():
    regions = [r for r in memory_map(CFG) if r[0] != 'LOGITS']
    spans = sorted((b, b + s) for _, b, s in regions)
    assert all(a[1] == b[0] for a, b in zip(spans, spans[1:]))
    assert sram_summary(CFG) == dict(state_bytes=1280, act_bytes=424, total_bytes=1704,
                                     macro_pairs=4, macros=8)
