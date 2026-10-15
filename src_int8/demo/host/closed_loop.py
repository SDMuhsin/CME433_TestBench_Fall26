"""Closed-loop story generation on the simulated chip.

The host feeds the prompt byte by byte, reads back the chip's 128 INT16 logits after every
token and samples the next byte from *those* logits (HostSampler T=0.8, seed 0).  Every
token's logits are also compared bit for bit with the golden model, and the final text is
compared with src_int8.demo.host.stories (golden-only generation).

  python3 -m src_int8.demo.host.closed_loop <sim> <build_dir> --prompt "Once upon a time" [--max-bytes 200]
<sim> is a Verilator binary (tb/build_verilator.sh) or a .vvp image.
Writes <build_dir>/<tag>.json (story, per-token cycles, mismatches); exit 0 only if bit-exact.
"""
import argparse
import json
import re
from pathlib import Path

import numpy as np

from src_int8.golden.host.sampler import HostSampler
from src_int8.golden.io.params import load_params
from src_int8.golden.model import HwModel
from src_int8.model.data.corpus import EOS

from .chip_link import ChipSim, write_stream_tables
from .stories import MAX_BYTES, PARAMS, SEED, TEMPERATURE, golden_story


def run_story(chip, cfg, P, prompt, max_bytes, log=print):
    """-> (story text, per-token records). Same loop as src_int8.golden.host.generate."""
    golden, sampler = HwModel(cfg, P), HostSampler(TEMPERATURE, SEED)
    text, records = list(prompt.encode('ascii')), []
    tok, pos = text[0], 1
    while True:
        logits, cyc = chip.step(tok, reset=not records)
        ref = golden.step([tok])[0]
        mism = int(np.count_nonzero(logits != ref))
        records.append(dict(byte=tok, mismatches=mism, **cyc))
        log(f'token {len(records) - 1:3d} byte {tok:02x}: {128 - mism}/128 bit-exact, '
            f'START->done {cyc["done"]} clk, incl. readback {cyc["total"]} clk')
        if pos < len(prompt):                   # still feeding the prompt
            tok, pos = text[pos], pos + 1
            continue
        tok = sampler(logits)                   # sample from the chip's logits
        if tok == EOS:
            break
        text.append(tok)
        if len(text) >= max_bytes:              # the last byte is not fed back
            break
    return bytes(text).decode('ascii'), records


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('sim', type=Path)
    ap.add_argument('build', type=Path)
    ap.add_argument('--prompt', default='Once upon a time')
    ap.add_argument('--max-bytes', type=int, default=MAX_BYTES)
    ap.add_argument('--params', default=PARAMS)
    a = ap.parse_args()
    cfg, P = load_params(a.params)
    tag = re.sub(r'\W+', '_', a.prompt).strip('_').lower()
    base, emb = write_stream_tables(P, a.build / 'tables')
    work = a.build / tag
    chip = ChipSim(a.sim, base, emb, work, work / 'sim.log')
    with open(work / 'host.log', 'w') as f:
        story, recs = run_story(chip, cfg, P, a.prompt, a.max_bytes, lambda s: print(s, file=f, flush=True))
    tb_errors = chip.close()
    expect = golden_story(cfg, P, a.prompt, a.max_bytes)
    bad = sum(r['mismatches'] != 0 for r in recs)
    ok = bad == 0 and tb_errors == 0 and story == expect
    res = dict(prompt=a.prompt, story=story, matches_golden_story=story == expect, tokens=len(recs),
               tokens_with_mismatch=bad, tb_errors=tb_errors,
               avg_done_clk=sum(r['done'] for r in recs) / len(recs),
               avg_total_clk=sum(r['total'] for r in recs) / len(recs),
               done_clk=sorted({r['done'] for r in recs}), records=recs, ok=ok)
    (a.build / f'{tag}.json').write_text(json.dumps(res, indent=1) + '\n')
    print(f'{"PASS" if ok else "FAIL"}: {a.prompt!r}: {len(recs)} tokens x 128 logits, '
          f'{bad} token(s) with mismatches, TB errors {tb_errors}, text {"==" if story == expect else "!="} golden; '
          f'avg START->done {res["avg_done_clk"]:.0f} clk, incl. readback {res["avg_total_clk"]:.0f} clk')
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
