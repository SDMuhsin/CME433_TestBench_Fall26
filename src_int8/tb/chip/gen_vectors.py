"""Chip vectors from the spec-formula reference (tb/ref) in the golden format, for running the
chip TB without src_int8/golden (random integer parameters, spec 3.2 ranges).

    python3 -m src_int8.tb.chip.gen_vectors <out_dir> [--seed N] [--story S]...

Files (same as src_int8/golden/vectors/chip.py): plan.memh, stream.memh, logits.memh, h.memh,
conv.memh, host.memh.  The TB does not care which generator wrote them.
"""
import argparse
from pathlib import Path

from ..ref import model_ref

DEFAULT_STORIES = ('Once upon a time', 'Lily saw a dog.')


def _memh(path, values, digits):
    mask = (1 << (4 * digits)) - 1
    Path(path).write_text(''.join(f'{v & mask:0{digits}x}\n' for v in values))


def build(P, stories):
    out = dict(plan=[], stream=[], logits=[], h=[], conv=[], host=[])
    for story in stories:
        model = model_ref.RefModel()
        for i, tok in enumerate(story):
            stream = model_ref.token_stream(P, tok)
            z = model.step_stream(stream)
            out['plan'].append((0x100 if i == 0 else 0) | tok)
            out['stream'] += stream
            out['logits'] += z
            out['h'] += model.hmem_image()
            out['conv'] += [v for l in range(len(model.CONV)) for v in model.CONV[l]]
            out['host'] += model_ref.host_image(model)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('out', type=Path)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--story', action='append')
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    stories = [s.encode('ascii') for s in (a.story or DEFAULT_STORIES)]
    vec = build(model_ref.params(a.seed), stories)
    for name, digits in (('plan', 3), ('stream', 2), ('logits', 4), ('h', 6), ('conv', 2), ('host', 2)):
        _memh(a.out / f'{name}.memh', vec[name], digits)
    print(f'chip (ref, seed {a.seed}): {len(vec["plan"])} tokens ({len(stories)} stories) -> {a.out}')


if __name__ == '__main__':
    main()
