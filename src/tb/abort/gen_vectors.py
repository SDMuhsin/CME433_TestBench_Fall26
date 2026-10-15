"""Golden collateral for the abort / reset TB (src/tb/abort/tb_mb_abort.sv).

One story from zero state; for every token the weight stream, the golden FP16 logits and the
golden on-chip state after the token (H0, H1, CONV0, CONV1 = memory words 0 .. 959 in the
spec section 6 layout).  Also maps for the coverage report: microcode pc -> program section
and the stream byte ranges of the stream sections.
Writes to <out>:
  plan.memh      one line per token: the input byte
  stream.memh    every token's weight stream (49,920 words per token)
  logits.memh    every token's 128 FP16 logits
  state.memh     every token's state after the step (960 words per token)
  upc_sec.memh   256 lines: section id of microcode pc (0xFF = unused)
  sections.txt   "id name" per section id
  sbound.memh    stream section byte boundaries (start of each section, then the total)
  sbound.txt     "start end name" per stream section (for humans)
usage: python3 -m src.tb.abort.gen_vectors <params.npz> <out> [--story TEXT]
"""
import argparse
from pathlib import Path

import numpy as np

import src.ucode.program as prog
from src.golden.data.memmap import memory_map
from src.golden.net.model import HwModel
from src.golden.data.stream import token_stream
from src.golden.host.vectors import write_memh
from src.golden.data.weights import load_params


def golden_run(P, cfg, story):
    """-> (stream words, logits words, state words) for a story started from zero state."""
    mm = {n: (b, s) for n, b, s in memory_map(cfg)}
    model = HwModel(cfg, P)
    stream, logits, state = [], [], []
    for tok in story:
        words = token_stream(P, tok)
        stream.extend(words)
        logits.extend(model.step_stream(words)[0])
        mem = np.zeros(mm['XN'][0], np.uint16)          # state occupies [0, XN)
        for l in range(cfg['n_layer']):
            hb, hs = mm[f'H{l}']
            cb, cs = mm[f'CONV{l}']
            mem[hb:hb + hs] = model.h[l][0].reshape(-1)  # [d][n]
            mem[cb:cb + cs] = model.conv[l][0]
        state.extend(mem)
    return stream, logits, state


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
    secs = [('EMB', D)]
    for l in range(cfg['n_layer']):
        secs += [(f'IN_X{l}', E * (D + 3)), (f'X_PROJ{l}', (R + 2 * N) * E),
                 (f'CHAN{l}', E * (1 + R + N + 1 + D)), (f'OUT{l}', D * E)]
    secs.append(('LOGITS', V * D))
    out, pos = [], 0
    for name, words in secs:
        out.append((2 * pos, 2 * (pos + words), name))
        pos += words
    return out


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
    write_memh(a.out / 'plan.memh', story, 2)
    write_memh(a.out / 'stream.memh', stream)
    write_memh(a.out / 'logits.memh', logits)
    write_memh(a.out / 'state.memh', state)
    sec, names = ucode_sections()
    ids = [names.index(s) for s in sec] + [0xFF] * (256 - len(sec))
    write_memh(a.out / 'upc_sec.memh', ids, 2)
    (a.out / 'sections.txt').write_text(''.join(f'{i} {n}\n' for i, n in enumerate(names)))
    sb = stream_bounds(cfg)
    write_memh(a.out / 'sbound.memh', [s for s, _, _ in sb] + [sb[-1][1]], 5)
    (a.out / 'sbound.txt').write_text(''.join(f'{s} {e} {n}\n' for s, e, n in sb))
    print(f'{len(story)} tokens, {len(names)} ucode sections, {len(sb)} stream sections -> {a.out}')


if __name__ == '__main__':
    main()
