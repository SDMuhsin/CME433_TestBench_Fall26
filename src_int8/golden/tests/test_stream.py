"""Spec sections 6 and 7: stream length and round trip, state-safe window, memory map."""
import numpy as np

from src_int8.golden.io.memmap import (HOST_LOGITS, REGIONS, h_entry, host_address, host_image,
                                       host_to_internal, summary)
from src_int8.golden.io.params import LAYER_KEYS, check_ranges
from src_int8.golden.io.stream import (row_bytes, state_safe_bytes, stream_bytes, token_stream,
                                       unpack_stream)

from .conftest import CFG, random_params


def test_stream_length_and_rows():
    assert row_bytes(CFG) == (74, 99, 85, 99, 67)
    assert stream_bytes(CFG) == 54280
    assert state_safe_bytes(CFG) == 197


def test_random_params_pass_range_checks():
    assert check_ranges(random_params(np.random.default_rng(3)), CFG)


def test_stream_round_trip_random():
    P = random_params(np.random.default_rng(0))
    stream = token_stream(P, 65)
    assert stream.dtype == np.uint8 and len(stream) == 54280
    emb, Q = unpack_stream(stream, CFG)
    assert np.array_equal(emb, P['E_in'][65])
    assert np.array_equal(Q['E_out'], P['E_out']) and np.array_equal(Q['rq_logits'], P['rq_logits'])
    for L, M in zip(P['layers'], Q['layers']):
        for k in LAYER_KEYS:
            assert np.array_equal(L[k], M[k]), k


def test_stream_byte_order_and_first_row_layout():
    P = random_params(np.random.default_rng(5))
    s = token_stream(P, 7)
    e = int(P['E_in'][7, 0]) & 0xFFFF
    assert s[0] == e & 0xFF and s[1] == e >> 8                     # little endian embedding
    L = P['layers'][0]
    row = s[128:128 + 74]
    assert np.array_equal(row[:64], L['W_in_x'][0] & 0xFF)
    M, sh = L['rq_in_x'][0]
    assert row[64:67].tolist() == [M & 0xFF, M >> 8, sh]
    assert row[67] == L['conv_w0'][0] & 0xFF and row[68] == L['conv_w1'][0] & 0xFF
    assert s[196] == L['conv_w1'][0] & 0xFF                           # w1[0] is byte 196 (spec 8)


def test_stream_round_trip_shipped(shipped):
    cfg, P = shipped
    for tok in (0, 65, 127):
        emb, Q = unpack_stream(token_stream(P, tok), cfg)
        assert np.array_equal(emb, P['E_in'][tok])
        for L, M in zip(P['layers'], Q['layers']):
            assert all(np.array_equal(L[k], M[k]) for k in LAYER_KEYS)


def test_memory_map():
    spans = sorted((b, b + (3 * s if u == 'entry' else s) * 0 + s, u) for n, (b, s, u) in REGIONS.items()
                   if n != 'LOGITS')
    for (a0, a1, _), (b0, _, _) in zip(spans, spans[1:]):
        assert a1 <= b0
    assert REGIONS['H1'][0] == 0x180 and REGIONS['CONV1'][0] + 96 == 0x600
    assert REGIONS['LOGITS'][0] == REGIONS['X'][0] and REGIONS['LOGITS'][1] == 256
    assert REGIONS['X'][0] + 128 + 96 + 12 + 20 == REGIONS['CONV0'][0]
    assert h_entry(1, 95, 3) == 0x2FF and h_entry(0, 0, 0) == 0
    assert HOST_LOGITS == 0x1040 and host_address('H1', 0) == 0x600 and host_address('XN') == 0x1000
    assert host_to_internal(0x1040) == ('B', 0x440) and host_to_internal(0x0601) == ('H', 0x180, 1)
    assert summary()['state_bytes'] == 2496 and summary()['macros'] == 11


def test_host_image_layout():
    h = [np.arange(384) - 192, np.zeros(384, np.int64)]
    img = host_image(h, bytes(range(256)) * 2)
    assert len(img) == 0x1200
    assert img[0:4] == bytes([0x40, 0xFF, 0xFF, 0]) and img[0x600:0x604] == bytes(4)   # -192, then H1
    assert img[0x1040] == 0x40
