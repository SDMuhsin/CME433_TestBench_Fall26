"""Byte-level ASCII TinyStories: normalisation and binary corpus files (same mapping as the FP16 chip)."""
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
