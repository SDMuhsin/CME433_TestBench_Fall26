"""Microcode properties the abort / reset contract relies on (spec section 7.1).

* A START or STATE_RESET that meets a held soft reset runs for one cycle (the sequencer's
  P0 of the entry uop) before the abort stops it.  Both entries therefore start with a LOOP
  uop, which has no memory, stream, lane or NLU effect in P0.
* An aborted token step keeps the SSM / conv state if fewer than SAFE_BYTES stream bytes
  were accepted: the first state write needs stream word SAFE_BYTES / 2 - 1 (conv w1[0]).
"""
from src.golden.data.memmap import memory_map
from src.golden.data.stream import token_stream
from src.golden.data.weights import load_params
from src.ucode.isa import OPS
from src.ucode.isa_sim import UcodeMachine
from src.ucode.program import CHIP_CFG, build

from .test_ucode import PARAMS

SAFE_BYTES = 262            # spec 7.1; also src/tb/abort/tb_mb_abort.sv


def test_entries_start_with_a_side_effect_free_uop():
    p = build()
    for name, pc in p.entries.items():
        assert OPS[p.uops[pc].op] in ('LOOP0', 'LOOP1'), f'entry {name} must start with a LOOP uop'


class _FirstStateWrite(UcodeMachine):
    """Records the stream words consumed when the first state word is written."""

    def __init__(self, *a, state_end, **kw):
        super().__init__(*a, **kw)
        self.state_end, self.words_at_write = state_end, None

    def _step(self, u):
        first = (self.words_at_write is None and OPS[u.op] == 'MOV' and u.wm
                 and self._addr(u) < self.state_end)
        super()._step(u)
        if first:
            self.words_at_write = self.sp          # words consumed, incl. this uop's


def test_state_safe_window():
    cfg, P = load_params(PARAMS)
    assert cfg == CHIP_CFG
    state_end = [b for n, b, _ in memory_map(cfg) if n == 'XN'][0]   # H*, CONV* occupy [0, XN)
    p = build()
    m = _FirstStateWrite(p.words(), p.entries, state_end=state_end)
    m.run('token', token_stream(P, ord('a')))
    assert m.words_at_write is not None
    assert 2 * m.words_at_write == SAFE_BYTES, \
        f'first state write after {m.words_at_write} stream words: update SAFE_BYTES (spec 7.1, TB)'
