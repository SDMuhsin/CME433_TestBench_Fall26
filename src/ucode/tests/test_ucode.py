"""Microcode: encoding round trip, generated RTL up to date, ISA-level run bit-exact vs golden."""
from pathlib import Path

import numpy as np

from src.golden.data.memmap import memory_map
from src.golden.net.model import HwModel
from src.golden.data.stream import token_stream
from src.golden.data.weights import load_params
from src.ucode import gen_rom
from src.ucode.isa import decode
from src.ucode.isa_sim import UcodeMachine
from src.ucode.program import CHIP_CFG, build

ROOT = Path(__file__).resolve().parents[2]
PARAMS = ROOT / 'golden' / 'params' / 'mamba_e96_fp16.npz'


def test_encode_decode_round_trip():
    for u in build().uops:
        assert decode(u.encode()).encode() == u.encode()


def test_generated_rtl_is_current(tmp_path):
    gen_rom.main(tmp_path)
    for name in ('mb_ucode_rom.v', 'mb_ucode_defs.vh'):
        assert (tmp_path / name).read_text() == (ROOT / 'rtl' / 'seq' / name).read_text(), \
            f'{name} is stale: rerun python3 -m src.ucode.gen_rom'


def test_token_steps_match_golden_with_state_reset():
    cfg, P = load_params(PARAMS)
    assert cfg == CHIP_CFG
    p = build()
    m = UcodeMachine(p.words(), p.entries)
    m.mem[:] = 0x3C00                                  # garbage state before the first reset
    lo, hi = [(b, b + s) for n, b, s in memory_map(cfg) if n == 'LOGITS'][0]
    for story in (b'Once', b'Lily'):
        m.run('reset')
        ref = HwModel(cfg, P)
        for tok in story:
            words = token_stream(P, tok)
            m.run('token', words)
            assert np.array_equal(m.mem[lo:hi], ref.step_stream(words)[0])
