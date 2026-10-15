"""Microcode properties the abort / reset contract relies on (spec.md section 8, FP16 spec 7.1).

* A START or STATE_RESET that meets a held soft reset runs for one cycle (the sequencer's P0 of
  the entry uop) before the abort stops it.  Both entries therefore start with a LOOP uop, which
  has no memory, stream, lane or NLU effect in P0.
* An aborted token step keeps the SSM / conv state if fewer than SAFE_BYTES stream bytes were
  accepted: the first state write (CONV0[0] = xi) needs stream byte SAFE_BYTES - 1 (conv w1[0]).
  spec.md section 8 gives 197 B; this test derives it from the microcode.
"""
from src_int8.tb.ref import model_ref
from src_int8.tb.ref.memmap import is_state
from src_int8.ucode.isa import OPS
from src_int8.ucode.isa_sim import UcodeMachine
from src_int8.ucode.program import build

SAFE_BYTES = 197            # spec.md section 8; also src_int8/tb/abort/tb_mq_abort.sv


def test_entries_start_with_a_side_effect_free_uop():
    p = build()
    for name, pc in p.entries.items():
        assert OPS[p.uops[pc].op] in ('LOOP0', 'LOOP1'), f'entry {name} must start with a LOOP uop'


class _FirstStateWrite(UcodeMachine):
    """Records the stream bytes consumed when the first state entry / byte is written."""

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self.bytes_at_write = None

    def _step(self, u):
        first = (self.bytes_at_write is None and OPS[u.op] == 'MOV' and u.wm
                 and is_state(self._addr(u)))
        super()._step(u)
        if first:
            self.bytes_at_write = self.sp          # bytes consumed, incl. this uop's


def test_state_safe_window():
    P = model_ref.params(1)
    p = build()
    m = _FirstStateWrite(p.words(), p.entries)
    m.run('token', model_ref.token_stream(P, ord('a')))
    assert m.bytes_at_write is not None
    assert m.bytes_at_write == SAFE_BYTES, \
        f'first state write after {m.bytes_at_write} stream bytes: update SAFE_BYTES (spec 8, TB)'
