"""Byte-level ASCII TinyStories: normalisation, binary corpus files and batch sampling."""
import argparse
from pathlib import Path

import numpy as np

EOS = 0  # story separator byte
_DOC_SEP = '<|endoftext|>'
_MAP = str.maketrans({'“': '"', '”': '"', '‘': "'", '’': "'",
                      '–': '-', '—': '-', '…': '...'})


def normalize_story(text):
    """Map typographic punctuation to ASCII; drop other non-ASCII and control chars except '\\n'."""
    text = text.translate(_MAP).strip()
    return ''.join(c for c in text if c == '\n' or 32 <= ord(c) < 127)


def encode_corpus(text):
    """Raw TinyStories text -> uint8 bytes, stories separated by EOS."""
    stories = (normalize_story(s) for s in text.split(_DOC_SEP))
    out = bytearray()
    for s in stories:
        if s:
            out += s.encode('ascii') + bytes([EOS])
    return np.frombuffer(bytes(out), dtype=np.uint8)


def build_bin(src, dst, chunk_chars=1 << 26):
    """Stream-convert a TinyStories .txt file into a .bin byte file (story-aligned chunks)."""
    with open(src, encoding='utf-8', errors='ignore') as f, open(dst, 'wb') as g:
        carry = ''
        while True:
            block = f.read(chunk_chars)
            text = carry + block
            cut = text.rfind(_DOC_SEP) if block else len(text)
            if cut <= 0 and block:
                carry = text
                continue
            encode_corpus(text[:cut]).tofile(g)
            carry = text[cut:]
            if not block:
                break


def load_bin(path):
    return np.memmap(path, dtype=np.uint8, mode='r')


def sample_batch(data, batch, length, rng):
    """Random crops: (inputs, targets) uint8 arrays of shape [batch, length]."""
    starts = rng.integers(0, len(data) - length - 1, size=batch)
    seq = np.stack([data[s:s + length + 1] for s in starts])
    return seq[:, :-1], seq[:, 1:]


def eval_segments(data, n, length, seed=1234):
    """Fixed evaluation crops [n, length + 1] shared by the float and golden evaluators."""
    rng = np.random.default_rng(seed)
    starts = rng.integers(0, len(data) - length - 1, size=n)
    return np.stack([data[s:s + length + 1] for s in starts]).astype(np.int64)


def main():
    ap = argparse.ArgumentParser(description=build_bin.__doc__)
    ap.add_argument('src', type=Path)
    ap.add_argument('dst', type=Path)
    a = ap.parse_args()
    build_bin(a.src, a.dst)


if __name__ == '__main__':
    main()
