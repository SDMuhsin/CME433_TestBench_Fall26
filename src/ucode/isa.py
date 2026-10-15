"""Micro-instruction set of the mb_chip sequencer: field layout, codes, encoder, decoder.

One 36-bit micro-op (uop) per ROM word.  Every uop runs in two phases (P0: stall check,
SRAM read, operand capture; P1: execute) so the minimum issue rate is one uop per 2 clk.

  field  bits  meaning
  op       3   MAC | INIT | MOV | NLD | LOOP0 | LOOP1 | END
  eol      2   bit l set: last uop of a level-l loop body (inner level 0 is checked first)
  sa,ra  3+3   source A and its register index
  sb,rb  3+3   source B and its register index (MOV: rb = destination register)
  wr       1   MOV: write register rb
  wm       1   MOV: write memory at the address operand
  mode     2   MOV: writeback scale (WB0: 0, WB6: -6, WBN: NLU scale + softplus bypass)
               NLD: NLU function (0 sigmoid, 1 softplus, 2 exp2, 3 rsqrt)
  nstep    1   NLU interpolation step selected for sources N
  base    11   address operand base word (LOOPx: iteration count - 1)
  am       3   address modifiers: +k (level-0 counter), +d (level-1 counter), d x4

Sources: Z (+0), EPS (2^-6, the RMSNorm accumulator init), S (next stream word), M (SRAM word
at the address operand), R (register), Y (lane writeback, per `mode`; stalls until the lane
is idle), N (NLU interpolation operand: side A -> table value, side B -> fraction), A (side B
only: the same value as side A).  At most one S and one M per uop.

  MAC   a, b     lane step a*b; the first MAC after an INIT starts the accumulation
  INIT  a        latch the accumulator init value a; the next MAC is the first step
  MOV   dst, a   R[rb] and/or MEM[addr] <- a
  NLD   fn, R    load the NLU with R[ra]
  LOOPl n        run the following body n times (level l counter 0 .. n-1)
  END            stop; STATUS.done
"""
from dataclasses import dataclass, fields

OPS = ('MAC', 'INIT', 'MOV', 'NLD', 'LOOP0', 'LOOP1', 'END')
SRCS = ('Z', 'EPS', 'S', 'M', 'R', 'Y', 'N', 'A')
MODES = ('WB0', 'WB6', 'WBN')
NLU_FNS = ('sigmoid', 'softplus', 'exp2', 'rsqrt')
AM_K, AM_D, AM_D4 = 1, 2, 4
EPS_BITS = 0x2400

# (name, width) from LSB upward
LAYOUT = (('am', 3), ('base', 11), ('nstep', 1), ('mode', 2), ('wm', 1), ('wr', 1),
          ('rb', 3), ('sb', 3), ('ra', 3), ('sa', 3), ('eol', 2), ('op', 3))
UOP_W = sum(w for _, w in LAYOUT)


@dataclass
class Uop:
    op: int
    eol: int = 0
    sa: int = 0
    ra: int = 0
    sb: int = 0
    rb: int = 0
    wr: int = 0
    wm: int = 0
    mode: int = 0
    nstep: int = 0
    base: int = 0
    am: int = 0
    note: str = ''

    def encode(self):
        word, pos = 0, 0
        for name, width in LAYOUT:
            v = getattr(self, name)
            assert 0 <= v < (1 << width), f'{name}={v} does not fit {width} bits'
            word |= v << pos
            pos += width
        return word


def decode(word):
    """ROM word -> Uop (without note)."""
    vals, pos = {}, 0
    for name, width in LAYOUT:
        vals[name] = (word >> pos) & ((1 << width) - 1)
        pos += width
    return Uop(**vals)


def field_positions():
    """-> {field: (lsb, width)}."""
    out, pos = {}, 0
    for name, width in LAYOUT:
        out[name] = (pos, width)
        pos += width
    return out


def addr_text(u):
    """Address operand of a uop as text, e.g. 0x180+4d+k."""
    parts = [f'0x{u.base:03X}']
    if u.am & AM_D:
        parts.append('4d' if u.am & AM_D4 else 'd')
    if u.am & AM_K:
        parts.append('k')
    return '+'.join(parts)


def disasm(u):
    """One-line assembly text of a uop."""
    def src(s, r, side):
        name = SRCS[s]
        if name == 'R':
            return f'R{r}'
        if name == 'M':
            return f'M[{addr_text(u)}]'
        if name == 'Y':
            return f'Y.{MODES[u.mode]}'
        if name == 'N':
            return f'N{side}{u.nstep}'
        return name
    op = OPS[u.op]
    if op == 'MAC':
        text = f'MAC   {src(u.sa, u.ra, "a")}, {src(u.sb, u.rb, "b")}'
    elif op == 'INIT':
        text = f'INIT  {src(u.sa, u.ra, "a")}'
    elif op == 'MOV':
        dst = ([f'R{u.rb}'] if u.wr else []) + ([f'M[{addr_text(u)}]'] if u.wm else [])
        text = f'MOV   {"+".join(dst)} <- {src(u.sa, u.ra, "a")}'
    elif op == 'NLD':
        text = f'NLD   {NLU_FNS[u.mode]}, R{u.ra}'
    elif op.startswith('LOOP'):
        text = f'{op} {u.base + 1}'
    else:
        text = op
    if u.eol:
        text += '   ; end ' + ' '.join(f'L{l}' for l in (0, 1) if u.eol >> l & 1)
    return text


assert UOP_W == 36 and {f.name for f in fields(Uop)} - {'note'} == {n for n, _ in LAYOUT}
