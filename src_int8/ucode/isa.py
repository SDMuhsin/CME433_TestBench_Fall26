"""Micro-instruction set of the mq_chip sequencer: field layout, codes, encoder, decoder.

One 53-bit micro-op (uop) per ROM word (arch.md estimated 48; the byte-addressed INT16 arrays
need x2 address scaling, and MAC `ps` / MOV `sh` are kept as separate fields for readability).
Every uop runs in two phases (P0: stall check, SRAM read, stream pop, operand capture; P1:
execute), so the minimum issue rate is one uop per 2 clk.

  field  bits  meaning
  op       3   MAC | INIT | MOV | NLD | LOOP0 | LOOP1 | END
  eol      2   bit l set: last uop of a level-l loop body (inner level 0 is checked first)
  sa,ra  3+3   source A and its register index (MOV Y: ra = addend register for SHA / RQA)
  sb,rb  3+3   source B and its register index (MOV: rb = destination register)
  wr       1   MOV: write register rb
  wm       1   MOV: write memory at the address operand (width mw)
  sw       2   stream pop width in bytes: 1, 2 or 3 (3 = MOV RQ <- S, the requant pair)
  mw       2   memory access width: 0 = 8 b, 1 = 16 b (BMEM, even address), 2 = 24 b (HMEM)
  ps       4   MAC: product shift (acc <- base + rsh(a * b, ps))
  wmode    2   MOV Y: SH (>> sh) | RQ (x M >> s) | SHA (SH + R[ra]) | RQA (RQ + R[ra])
               NLD: the NLU function (0 sigmoid, 1 softplus, 2 exp2, 3 rsqrt)
  sh       5   MOV Y: immediate shift of SH / SHA
  ww       2   MOV Y: result width 0 = sat 8, 1 = sat 16, 2 = sat 24, 3 = raw 32 (NLU input)
  nstep    1   MAC: NLU interpolation step of sources N; MOV Y: 1 = NLU result mode
               (shift = NLU sh_fn, exp2 zero flag forces 0, width 16)
  base    12   address operand base (internal byte / entry address; LOOPx: count - 1)
  am       4   address modifiers: [1:0] k scale (0 none, 1 +k, 2 +2k), [3:2] d scale
               (0 none, 1 +d, 2 +2d, 3 +4d)

Sources: Z (0), EPS (the constant 16: RMSNorm accumulator init), S (next stream bytes, LE,
sign-extended; width sw), M (memory at the address operand; width mw, sign-extended), R
(register, 16 b), Y (lane writeback per wmode / sh / ww; stalls until the lane and the
writeback pipe have drained), N (NLU operand: side A -> ROM word, side B -> fraction), A (side
B only: the value of side A).  Side A is 24 bits wide (HMEM entries), side B 16 bits.  At most
one S and one M per uop.

  MAC   a, b, ps  lane step acc <- base + rsh(a * b, ps); the first MAC after an INIT starts
                  the accumulation from the INIT value
  INIT  a         latch the accumulator init value (Z or EPS)
  MOV   dst, a    R[rb] and/or MEM[addr] <- a;  MOV RQ <- S (sw = 3) loads the requant pair
  NLD   fn, a     load the NLU with a (R, sign-extended, or Y raw 32 b)
  LOOPl n         run the following body n times (level l counter 0 .. n-1)
  END             stop; STATUS.done
"""
from dataclasses import dataclass, fields

OPS = ('MAC', 'INIT', 'MOV', 'NLD', 'LOOP0', 'LOOP1', 'END')
SRCS = ('Z', 'EPS', 'S', 'M', 'R', 'Y', 'N', 'A')
WMODES = ('SH', 'RQ', 'SHA', 'RQA')
WWS = (8, 16, 24, 32)                 # ww code -> width
MWS = (8, 16, 24)                     # mw code -> width
NLU_FNS = ('sigmoid', 'softplus', 'exp2', 'rsqrt')
EPS_VAL = 16
AM_K, AM_K2 = 1, 2                    # am[1:0]
AM_D, AM_D2, AM_D4 = 1 << 2, 2 << 2, 3 << 2   # am[3:2]

# (name, width) from LSB upward
LAYOUT = (('am', 4), ('base', 12), ('nstep', 1), ('ww', 2), ('sh', 5), ('wmode', 2), ('ps', 4),
          ('mw', 2), ('sw', 2), ('wm', 1), ('wr', 1), ('rb', 3), ('sb', 3), ('ra', 3), ('sa', 3),
          ('eol', 2), ('op', 3))
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
    sw: int = 0
    mw: int = 0
    ps: int = 0
    wmode: int = 0
    sh: int = 0
    ww: int = 0
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


def addr_offset(am, k, d):
    """Address modifier value for loop counters k, d."""
    off = (0, k, 2 * k, 0)[am & 3]
    off += (0, d, 2 * d, 4 * d)[am >> 2 & 3]
    return off


def addr_text(u):
    parts = [f'0x{u.base:03X}']
    parts += [('', 'd', '2d', '4d')[u.am >> 2 & 3]] if u.am >> 2 & 3 else []
    parts += [('', 'k', '2k', '?')[u.am & 3]] if u.am & 3 else []
    return '+'.join(parts)


def disasm(u):
    """One-line assembly text of a uop."""
    def src(s, r, side):
        name = SRCS[s]
        if name == 'R':
            return f'R{r}'
        if name == 'M':
            return f'M{MWS[u.mw]}[{addr_text(u)}]'
        if name == 'S':
            return 'RQ:S24' if u.sw == 3 else f'S{8 * u.sw}'
        if name == 'Y':
            if u.nstep:
                return 'YN'
            t = f'Y.{WMODES[u.wmode]}'
            t += f'({u.sh})' if WMODES[u.wmode] in ('SH', 'SHA') else ''
            t += f'+R{u.ra}' if WMODES[u.wmode].endswith('A') else ''
            return t + f'.w{WWS[u.ww]}'
        if name == 'N':
            return f'N{side}{u.nstep}'
        return name
    op = OPS[u.op]
    if op == 'MAC':
        text = f'MAC   {src(u.sa, u.ra, "a")}, {src(u.sb, u.rb, "b")}, ps={u.ps}'
    elif op == 'INIT':
        text = f'INIT  {src(u.sa, u.ra, "a")}'
    elif op == 'MOV':
        dst = ([f'R{u.rb}'] if u.wr else []) + ([f'M{MWS[u.mw]}[{addr_text(u)}]'] if u.wm else [])
        if not dst and SRCS[u.sa] == 'S' and u.sw == 3:
            dst = ['RQ']
        text = f'MOV   {"+".join(dst)} <- {src(u.sa, u.ra, "a")}'
    elif op == 'NLD':
        text = f'NLD   {NLU_FNS[u.wmode]}, {"Y.raw" if SRCS[u.sa] == "Y" else src(u.sa, u.ra, "a")}'
    elif op.startswith('LOOP'):
        text = f'{op} {u.base + 1}'
    else:
        text = op
    if u.eol:
        text += '   ; end ' + ' '.join(f'L{l}' for l in (0, 1) if u.eol >> l & 1)
    return text


assert UOP_W == 53 and {f.name for f in fields(Uop)} - {'note'} == {n for n, _ in LAYOUT}
