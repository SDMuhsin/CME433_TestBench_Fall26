#!/usr/bin/env python3
"""Host-side inputs for dla_e2e_chip: the STREAM_Q payload and the requant CSR bytes.

Writes (one hex byte per line, $readmemh format):
  <out>/e2e_stream.memh   283,984 B: zq[64], then per layer (L0 64 tiles, L2 64, L4 196)
                          4 bias bytes + 4 weight rows (row-major [out][in]) per tile --
                          the same layout tb/dla_e2e_chip_tb.sv:build_stream() produces
  <out>/csr.memh          (only with --csr / --csr-json) 24 B = MA0,MB0,MA2,MB2,MW4,MB4
                          as 32-bit little-endian, i.e. WR_CSR 0x02 payload from addr 0x10

Feed them to the chip TB with +STREAM_SRC=<out>/e2e_stream.memh (or +WDIR/+ZQ, which
builds the same stream inside the TB) and +CSR_MEMH=<out>/csr.memh.

Usage (repo root):
  python3 scripts/gen_e2e_stream.py <outdir> [--wdir weights_vh/mnist_gan_mlp]
      [--zq tb/data/g300_int8/g300_zq.memh]
      [--csr MA0 MB0 MA2 MB2 MW4 MB4 | --csr-json csr_constants.json]
"""
import argparse
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CSR_NAMES = ('MA0', 'MB0', 'MA2', 'MB2', 'MW4', 'MB4')
TOTAL = 283984


def rd8(p):
    v = [int(t, 16) & 0xFF for t in Path(p).read_text().split()]
    return v


def build_stream(wdir, zq):
    w = {n: rd8(Path(wdir) / f'G300_{n}.memh')
         for n in ('0_weight', '0_bias', '2_weight', '2_bias', '4_weight', '4_bias')}
    assert len(zq) == 64, f'zq has {len(zq)} bytes, expected 64'
    s = list(zq)
    for layer, n_in, n_out in (('0', 64, 256), ('2', 256, 256), ('4', 256, 784)):
        W, B = w[f'{layer}_weight'], w[f'{layer}_bias']
        assert len(W) == n_in * n_out and len(B) == n_out, f'layer {layer} size mismatch'
        for t in range(n_out // 4):
            s += B[4 * t:4 * t + 4]
            for r in range(4):
                s += W[(4 * t + r) * n_in:(4 * t + r + 1) * n_in]
    assert len(s) == TOTAL, len(s)
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('outdir')
    ap.add_argument('--wdir', default=str(REPO / 'weights_vh/mnist_gan_mlp'))
    ap.add_argument('--zq', default=str(REPO / 'tb/data/g300_int8/g300_zq.memh'))
    g = ap.add_mutually_exclusive_group()
    g.add_argument('--csr', type=int, nargs=6, metavar=CSR_NAMES)
    g.add_argument('--csr-json', help='JSON with {"csr": {"MA0": {"value": n}, ...}} or {"MA0": n, ...}')
    a = ap.parse_args()

    out = Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    s = build_stream(a.wdir, rd8(a.zq))
    (out / 'e2e_stream.memh').write_text(''.join(f'{b:02x}\n' for b in s))
    print(f'{out}/e2e_stream.memh: {len(s)} B')

    vals = a.csr
    if a.csr_json:
        d = json.loads(Path(a.csr_json).read_text())
        d = d.get('csr', d)
        vals = [d[k]['value'] if isinstance(d[k], dict) else int(d[k]) for k in CSR_NAMES]
    if vals:
        bs = []
        for name, v in zip(CSR_NAMES, vals):
            assert 0 <= v < 1 << 32, f'{name}={v} does not fit a 32-bit CSR'
            bs += [(v >> (8 * i)) & 0xFF for i in range(4)]
        (out / 'csr.memh').write_text(''.join(f'{b:02x}\n' for b in bs))
        print(f'{out}/csr.memh: ' + ' '.join(f'{n}={v}' for n, v in zip(CSR_NAMES, vals)))


if __name__ == '__main__':
    main()
