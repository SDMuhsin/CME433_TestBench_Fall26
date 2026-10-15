"""Golden collateral for the abort / reset TB (src_int8/tb/abort/tb_mq_abort.sv).

One story from zero state; for every token the weight stream, the golden INT16 logits and the
golden on-chip state after the token in the host read-back view (spec section 6): the 768 H
entries as 4-byte LE slots (host 0x0000..0x0BFF) followed by CONV0, CONV1 (host 0x1140..0x11FF),
3,264 bytes per token.  Also maps for the coverage report: microcode pc -> program section and
the stream byte ranges of the stream sections.
Writes to <out>:
  plan.memh      one line per token: the input byte
  stream.memh    every token's weight stream (54,280 bytes per token, one per line)
  logits.memh    every token's 128 INT16 Q7.8 logits
  state.memh     every token's state after the step (3,264 host bytes per token)
  upc_sec.memh   256 lines: section id of microcode pc (0xFF = unused)
  sections.txt   "id name" per section id
  sbound.memh    stream section byte boundaries (start of each section, then the total)
  sbound.txt     "start end name" per stream section (for humans)
usage: python3 -m src_int8.tb.abort.gen_vectors <params.npz> <out> [--story TEXT]
"""
import argparse
from pathlib import Path

import numpy as np

import src_int8.ucode.program as prog
from src_int8.golden.io.memmap import host_image
from src_int8.golden.io.params import load_params
from src_int8.golden.io.stream import row_bytes, state_safe_bytes, token_stream
from src_int8.golden.model import HwModel
from src_int8.golden.vectors.common import write_memh

H_SLOT_BYTES = 768 * 4                                  # host 0x0000..0x0BFF
CONV_HOST = 0x1140                                      # CONV0 at BMEM 0x540 -> host 0x1140
CONV_BYTES = 192
STATE_BYTES = H_SLOT_BYTES + CONV_BYTES                 # 3,264 per token


def golden_run(P, cfg, story):
    """-> (stream bytes, logits, state bytes) for a story started from zero state."""
    model = HwModel(cfg, P)
    stream, logits, state = [], [], []
    for tok in story:
        data = token_stream(P, tok)
        stream.append(data)
        logits.append(model.step_stream(data)[0])
        bmem = np.zeros(512, np.uint8)
        for l, c in enumerate(model.conv):
            bmem[0x140 + 96 * l:0x140 + 96 * (l + 1)] = c[0] & 0xFF
        img = np.frombuffer(host_image([h[0].reshape(-1) for h in model.h], bmem.tobytes()), np.uint8)
        state.append(np.concatenate([img[:H_SLOT_BYTES], img[CONV_HOST:CONV_HOST + CONV_BYTES]]))
    return np.concatenate(stream), np.concatenate(logits), np.concatenate(state)


def ucode_sections():
    """-> (pc -> section name list, ordered unique names) by tracing program.build()."""
    marks = []                                          # (start pc, name)
    count = {}

    def wrap(name, fn):
        def inner(p, *a, **kw):
            i = count.get(name, 0)
            count[name] = i + 1
            marks.append((len(p.uops), f'{name}{i}'))
            fn(p, *a, **kw)
            marks.append((len(p.uops), None))
        return inner

    saved = {n: getattr(prog, n) for n in ('rmsnorm', 'in_x_conv', 'x_proj', 'channel', 'out_proj')}
    try:
        for n, fn in saved.items():
            setattr(prog, n, wrap(n, fn))
        p = prog.build()
    finally:
        for n, fn in saved.items():
            setattr(prog, n, fn)
    n_uops = len(p.uops)
    sec = ['emb'] * n_uops
    cur = None
    marks_d = {}
    for pc, name in marks:
        marks_d.setdefault(pc, []).append(name)
    after_last = 'logits'
    for pc in range(n_uops):
        for name in marks_d.get(pc, []):
            cur = name if name is not None else after_last
        if cur is not None:
            sec[pc] = cur
    if 'rmsnorm2' in sec:
        sec = [s.replace('rmsnorm2', 'normf') for s in sec]
    sec[p.entries['reset'] - 1] = 'end'
    for pc in range(p.entries['reset'], n_uops):
        sec[pc] = 'reset'
    names = list(dict.fromkeys(sec))
    return sec, names


def stream_bounds(cfg):
    D, E, V = cfg['d_model'], cfg['d_inner'], cfg['vocab']
    R, N = cfg['dt_rank'], cfg['d_state']
    in_x, x_proj, chan, out, logit = row_bytes(cfg)
    secs = [('EMB', 2 * D)]
    for l in range(cfg['n_layer']):
        secs += [(f'IN_X{l}', E * in_x), (f'X_PROJ{l}', (R + 2 * N) * x_proj),
                 (f'CHAN{l}', E * chan), (f'OUT{l}', D * out)]
    secs.append(('LOGITS', V * logit))
    bounds, pos = [], 0
    for name, nbytes in secs:
        bounds.append((pos, pos + nbytes, name))
        pos += nbytes
    return bounds


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('params')
    ap.add_argument('out', type=Path)
    ap.add_argument('--story', default='Once upon')
    a = ap.parse_args()
    cfg, P = load_params(a.params)
    story = a.story.encode('ascii')
    stream, logits, state = golden_run(P, cfg, story)
    a.out.mkdir(parents=True, exist_ok=True)
    write_memh(a.out / 'plan.memh', list(story), 2)
    write_memh(a.out / 'stream.memh', stream, 2)
    write_memh(a.out / 'logits.memh', logits, 4)
    write_memh(a.out / 'state.memh', state, 2)
    sec, names = ucode_sections()
    assert len(names) <= 15, 'the TB reserves section id 15 for idle'
    ids = [names.index(s) for s in sec] + [0xFF] * (256 - len(sec))
    write_memh(a.out / 'upc_sec.memh', ids, 2)
    (a.out / 'sections.txt').write_text(''.join(f'{i} {n}\n' for i, n in enumerate(names)))
    sb = stream_bounds(cfg)
    assert sb[-1][1] == len(stream) // len(story)
    write_memh(a.out / 'sbound.memh', [s for s, _, _ in sb] + [sb[-1][1]], 5)
    (a.out / 'sbound.txt').write_text(''.join(f'{s} {e} {n}\n' for s, e, n in sb))
    print(f'{len(story)} tokens, {len(names)} ucode sections, {len(sb)} stream sections, '
          f'state-safe window {state_safe_bytes(cfg)} B -> {a.out}')


if __name__ == '__main__':
    main()
