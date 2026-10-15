"""Chip test vectors: stories -> host weight stream + golden FP16 logits for every token.

Each story starts from zero state (the host issues STATE_RESET before its first byte).
Writes to <out>:
  plan.memh    one line per token: bit 8 = state reset before the token, bits 7..0 = byte
  stream.memh  every token's weight stream, 16-bit words in stream order
  logits.memh  every token's 128 FP16 logits
"""
import argparse
from pathlib import Path

from ..net.model import HwModel
from ..data.stream import token_stream
from ..data.weights import load_params


def write_memh(path, words, digits=4):
    Path(path).write_text(''.join(f'{int(w):0{digits}x}\n' for w in words))


def build(P, cfg, stories):
    """-> (plan words, stream words, logits words) for a list of story byte strings."""
    plan, stream, logits = [], [], []
    for story in stories:
        model = HwModel(cfg, P)
        for i, tok in enumerate(story):
            words = token_stream(P, tok)
            plan.append((0x100 if i == 0 else 0) | tok)
            stream.extend(words)
            logits.extend(model.step_stream(words)[0])
    return plan, stream, logits


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('params')
    ap.add_argument('out', type=Path)
    ap.add_argument('--story', action='append', help='repeatable; default: two short stories')
    a = ap.parse_args()
    stories = [s.encode('ascii') for s in (a.story or ['Once upon a time', 'Lily saw a dog.'])]
    cfg, P = load_params(a.params)
    plan, stream, logits = build(P, cfg, stories)
    a.out.mkdir(parents=True, exist_ok=True)
    write_memh(a.out / 'plan.memh', plan, 3)
    write_memh(a.out / 'stream.memh', stream)
    write_memh(a.out / 'logits.memh', logits)
    print(f'{len(plan)} tokens ({len(stories)} stories), {len(stream)} stream words -> {a.out}')


if __name__ == '__main__':
    main()
