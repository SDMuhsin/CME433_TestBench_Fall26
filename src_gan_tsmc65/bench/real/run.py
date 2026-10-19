"""Score generated images against real Fashion-MNIST, GAN-paper style (docs/bench.md).

python3 -m src_gan_tsmc65.bench.real.run [--n 10000] [--width 8] [--device cuda:1] [--force] [row ...]
Rows (default all, in this order): real, float, golden, then variants = RTL images of
bench/run_bench.sh <variant> --n N [--width W]; with --width 16 `golden` is the INT16 model and the
variant rows are the 16-bit chip's (cache keys golden_w16, <variant>_w16). Each row is cached in build/gan65/real/n<N>/<row>.json and is
recomputed only with --force, so the rows can be scored in separate invocations. Primary: FID / IS / KID / precision-recall vs
the 60k train set (fidelity.py). Secondary: Fashion-MNIST CNN metrics (domain.py).
Writes the table to build/gan65/real/real_n<N>.{json,md}: the rows already there, then the default rows and
the requested rows (cached ones included).
"""
import argparse
import json

from ...common.paths import BUILD
from ..variant import name as tag_of
from . import sources
from .domain import cnn_outputs, domain_metrics
from .fidelity import gan_metrics

REFS = {'real': 'Real test set (floor)', 'float': 'Float generator', 'golden': 'INT8 golden (Python)'}
VARIANTS = ('exact', 'mq:evo_1KV8', 'mq:ilm', 'example_trunc4', 'mq:evo_1KR8', 'mq:evo_1KVL', 'mq:evo_1KR3')
HEAD = ('| Images (N = {n}) | FID | IS | KID x10^3 | Precision | Recall | CNN-FID | NN-PSNR mean / median (dB) '
        '| NN label agree | CNN-IS | Conf | Label entropy (bits) |\n|---|---|---|---|---|---|---|---|---|---|---|---|')


def row(name, r):
    return (f"| {name} | {r['fid']:.2f} | {r['is_mean']:.2f} ± {r['is_std']:.2f} | "
            f"{1e3 * r['kid_mean']:.2f} ± {1e3 * r['kid_std']:.2f} | {r['precision']:.3f} | {r['recall']:.3f} | "
            f"{r['cnn_fid']:.2f} | {r['nn_psnr_mean']:.2f} / {r['nn_psnr_median']:.2f} | {100 * r['nn_label']:.1f} % | "
            f"{r['cnn_is']:.2f} | {r['conf']:.3f} | {r['entropy']:.2f} |")


def key(r, w):
    if r in ('real', 'float'):
        return r
    return tag_of(r, w)                               # golden -> golden / golden_w16


def label(r, w):
    if r in ('real', 'float') or (r == 'golden' and w == 8):
        return REFS[r]
    if r == 'golden':
        return f'INT{w} golden (Python)'
    return f'RTL `{r}`' + ('' if w == 8 else f' ({w}-bit)')


def images(r, w, train, test, n):
    if r == 'real':
        return test[:n]
    if r == 'float':
        return sources.float_gen(n)
    if r == 'golden':
        return sources.golden(n, w)
    return sources.rtl(tag_of(r, w), n)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('rows', nargs='*', default=[*REFS, *VARIANTS])
    ap.add_argument('--n', type=int, default=10000)
    ap.add_argument('--width', type=int, default=8)
    ap.add_argument('--device', default='cuda:1')
    ap.add_argument('--force', action='store_true')
    a = ap.parse_args()
    d = BUILD / 'real'
    cache = d / f'n{a.n}'
    cache.mkdir(parents=True, exist_ok=True)
    w = a.width
    todo = [r for r in a.rows if a.force or not (cache / f'{key(r, w)}.json').exists()]
    if todo:
        from torchvision import datasets
        train, test = sources.real(True), sources.real(False)
        test_lab = datasets.FashionMNIST(str(BUILD / 'data'), train=False).targets.numpy()
        train_feats, _ = cnn_outputs(train, a.device)
    for r in todo:
        u8 = images(r, w, train, test, a.n)
        # the test set is the nearest-neighbour pool, so the floor row's NN uses train[:N] instead
        nn = train[:a.n] if r == 'real' else None
        res = {**gan_metrics(u8, train, a.device), **domain_metrics(u8, train_feats, test, test_lab, a.device, nn)}
        (cache / f'{key(r, w)}.json').write_text(json.dumps(res, indent=1) + '\n')
        print(row(label(r, w), res), flush=True)
    # rows of earlier invocations (other variants, other widths) stay, in their order; new rows append
    out = d / f'real_n{a.n}.json'
    rows = json.loads(out.read_text())['rows'] if out.exists() else {}
    order = [(r, 8) for r in [*REFS, *VARIANTS]] + [(r, w) for r in a.rows]
    rows.update({label(r, rw): json.loads((cache / f'{key(r, rw)}.json').read_text())
                 for r, rw in order if (cache / f'{key(r, rw)}.json').exists()})
    out.write_text(json.dumps(dict(n=a.n, rows=rows), indent=1) + '\n')
    (d / f'real_n{a.n}.md').write_text('\n'.join([HEAD.format(n=a.n)] + [row(k, v) for k, v in rows.items()]) + '\n')


if __name__ == '__main__':
    main()
