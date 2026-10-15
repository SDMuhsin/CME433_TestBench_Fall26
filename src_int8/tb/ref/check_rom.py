"""Check the generated NLU ROM RTL (rtl/nonlin/mq_nlu_rom.v, team A's scripts/gen_nlu_rom.py)
word for word against the spec 5.1 tables computed here: python3 -m src_int8.tb.ref.check_rom."""
import re
import sys
from pathlib import Path

from .nlu_ref import ROM

ROM_V = Path(__file__).resolve().parents[2] / 'rtl' / 'nonlin' / 'mq_nlu_rom.v'


def main():
    words = [int(w, 16) for w in re.findall(r"9'd\d+: t = 16'h([0-9a-f]{4});", ROM_V.read_text())]
    if words == ROM:
        print('PASS nlu_rom: mq_nlu_rom.v matches the spec 5.1 tables (340 words)')
        return 0
    bad = [i for i, (a, b) in enumerate(zip(words, ROM)) if a != b]
    print(f'FAIL nlu_rom: {len(words)} words read, {len(bad)} differ from tb/ref/nlu_ref.py '
          f'(first: {bad[:5]})')
    return 1


if __name__ == '__main__':
    sys.exit(main())
