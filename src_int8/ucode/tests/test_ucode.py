"""Microcode: encoding round trip, generated RTL up to date, ISA-level run bit-exact vs the
spec-formula reference (src_int8/tb/ref; switch to src_int8/golden when its HwModel lands)."""
from pathlib import Path

from src_int8.tb.ref import model_ref
from src_int8.ucode import gen_rom
from src_int8.ucode.isa import decode
from src_int8.ucode.isa_sim import UcodeMachine
from src_int8.ucode.program import STREAM_BYTES, build

ROOT = Path(__file__).resolve().parents[2]


def test_encode_decode_round_trip():
    for u in build().uops:
        assert decode(u.encode()).encode() == u.encode()


def test_program_fits_the_pc_csr():
    assert len(build().words()) < 256


def test_generated_rtl_is_current(tmp_path):
    gen_rom.main(tmp_path)
    for name in ('mq_ucode_rom.v', 'mq_ucode_defs.vh'):
        assert (tmp_path / name).read_text() == (ROOT / 'rtl' / 'seq' / name).read_text(), \
            f'{name} is stale: rerun python3 -m src_int8.ucode.gen_rom'


def test_reset_routine_zeroes_the_state_only():
    p = build()
    m = UcodeMachine(p.words(), p.entries)
    m.hmem = [0x123456] * len(m.hmem)
    m.bmem = [0xAB] * len(m.bmem)
    m.run('reset')
    assert all(h == 0 for h in m.hmem)
    assert m.bmem[0x140:0x200] == [0] * 192 and m.bmem[:0x140] == [0xAB] * 0x140


def test_token_steps_match_reference_with_state_reset():
    P = model_ref.params(1)
    p = build()
    m = UcodeMachine(p.words(), p.entries)
    m.hmem = [0x7FFFFF] * len(m.hmem)                     # garbage state before the first reset
    for story in (b'Once', b'Lily'):
        m.run('reset')
        ref = model_ref.RefModel()
        for tok in story:
            data = model_ref.token_stream(P, tok)
            assert len(data) == STREAM_BYTES
            m.run('token', data)
            assert m.logits() == ref.step_stream(data)
            assert [h & 0xFFFFFF for h in m.hmem] == ref.hmem_image()
            assert m.bmem == ref.bmem_image()
