"""Long-context RTL run: >1k tokens on the simulated chip with the state carried (no reset).

Only the first token issues STATE_RESET (required after power-up). Every token's 128 logits
are compared bit for bit with src/golden (HwModel, batch 1).
  forced input:  --text-bin val.bin --offset K   feeds bytes K..K+N-1 of a corpus file
                 (TinyStories joined by EOS, so the state runs across story boundaries)
  closed loop:   (no --text-bin) samples every next byte from the chip's logits with
                 HostSampler(T, seed) and keeps going through EOS bytes
  python3 -m src.demo.host.long_run <sim> <out_dir> --tokens 1200 [--text-bin f --offset K]
<sim> is a Verilator binary (build_verilator.sh) or a .vvp image. Writes <out_dir>/long.json
and exits 0 only if every token is bit-exact and the TB reports no error.
"""
import argparse
import json
import time
from pathlib import Path

import numpy as np

from src.golden.arith.fp import value
from src.golden.net.model import HwModel
from src.golden.host.sampler import HostSampler
from src.golden.data.weights import load_params

from .chip_link import ChipSim, write_stream_tables
from .stories import PARAMS, SEED, TEMPERATURE


def feeder(args):
    """-> (description, next_byte(i, chip_logits) -> byte)."""
    if args.text_bin:
        data = np.fromfile(args.text_bin, np.uint8, count=args.tokens, offset=args.offset)
        assert len(data) == args.tokens, 'corpus too short'
        return f'forced input {args.text_bin}[{args.offset}:+{args.tokens}]', lambda i, _: int(data[i])
    prompt = args.prompt.encode('ascii')
    sampler = HostSampler(TEMPERATURE, SEED)
    return (f'closed loop, prompt {args.prompt!r}, T={TEMPERATURE} seed={SEED}, through EOS',
            lambda i, z: prompt[i] if i < len(prompt) else sampler(z))


def run(chip, golden, next_byte, n, log):
    records, logits, t0 = [], None, time.time()
    for i in range(n):
        tok = next_byte(i, logits)
        logits, cyc = chip.step(tok, reset=i == 0)
        ref = golden.step([tok])[0]
        mism = int(np.count_nonzero(logits != ref))
        hmax = max(float(np.abs(value(h)).max()) for h in golden.h)
        records.append(dict(byte=tok, mismatches=mism, max_abs_h=hmax, **cyc))
        log(f'token {i:5d} byte {tok:02x}: {128 - mism}/128 bit-exact, max|h| {hmax:.2f}, '
            f'START->done {cyc["done"]} clk, TB err {cyc["errors"]} ({time.time() - t0:.0f} s)')
    return records


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('sim', type=Path)
    ap.add_argument('out', type=Path)
    ap.add_argument('--tokens', type=int, default=1200)
    ap.add_argument('--text-bin')
    ap.add_argument('--offset', type=int, default=0)
    ap.add_argument('--prompt', default='Once upon a time')
    ap.add_argument('--params', default=PARAMS)
    a = ap.parse_args()
    cfg, P = load_params(a.params)
    base, emb = write_stream_tables(P, a.out / 'tables')
    chip = ChipSim(a.sim, base, emb, a.out, a.out / 'sim.log')
    what, next_byte = feeder(a)
    with open(a.out / 'host.log', 'w') as f:
        recs = run(chip, HwModel(cfg, P), next_byte, a.tokens, lambda s: print(s, file=f, flush=True))
    tb_errors = chip.close()
    bad = [i for i, r in enumerate(recs) if r['mismatches'] or r['errors']]
    ok = not bad and tb_errors == 0
    text = bytes(r['byte'] for r in recs)
    res = dict(mode=what, tokens=len(recs), state_resets=1, tokens_with_mismatch=len(bad),
               first_bad=bad[0] if bad else None, tb_errors=tb_errors,
               eos_in_input=text.count(0), max_abs_h=max(r['max_abs_h'] for r in recs),
               done_clk=sorted({r['done'] for r in recs}), ok=ok,
               text=text.decode('ascii', 'replace'), records=recs)
    (a.out / 'long.json').write_text(json.dumps(res, indent=1) + '\n')
    print(f'{"PASS" if ok else "FAIL"}: {what}: {len(recs)} tokens x 128 logits, {len(bad)} token(s) '
          f'with mismatches, TB errors {tb_errors}, {res["eos_in_input"]} EOS bytes crossed, '
          f'max|h| {res["max_abs_h"]:.2f}, START->done {res["done_clk"]} clk')
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
