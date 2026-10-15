"""Assembler for the mq_chip micro-instruction set (see isa.py).

    p = Program()
    p.entry('token')
    with p.over_d(96):                       # level-1 loop, counter d
        p.init(Z)
        with p.over_k(64):                   # level-0 loop, counter k
            p.mac(S8, M8(XN, k))
        p.mov(RQ, S24)
        p.mov(M8(U, d), YRQ(8))

Operands: Z, EPS, S8 / S16 / S24, A, N, R(i), M8 / M16 / M24(base, k | k2 | d | d2 | d4),
Y writebacks YSH(sh, w, addend=None), YRQ(w, addend=None), YRAW (NLU input), YN (NLU result),
RQ (destination of MOV RQ <- S24).  The assembler checks the operand rules (one S and one M per
uop, 24-bit memory only on side A, widths against the memory region, address alignment) and
the loop structure, and sets the end-of-loop bits.
"""
from contextlib import contextmanager
from dataclasses import dataclass

from .isa import (AM_D, AM_D2, AM_D4, AM_K, AM_K2, MWS, NLU_FNS, OPS, SRCS, WMODES, WWS, Uop)

BMEM_BASE = 0x400


@dataclass(frozen=True)
class Src:
    kind: str
    reg: int = 0
    base: int = 0
    am: int = 0
    width: int = 0          # S: bytes; M: bits; Y: result width
    wmode: str = 'SH'
    sh: int = 0
    addend: int = -1        # Y: addend register or -1
    nmode: int = 0          # Y: NLU result mode


k, k2, d, d2, d4 = AM_K, AM_K2, AM_D, AM_D2, AM_D4
Z, EPS, A, N, RQ = Src('Z'), Src('EPS'), Src('A'), Src('N'), Src('RQ')
S8, S16, S24 = Src('S', width=1), Src('S', width=2), Src('S', width=3)
YRAW = Src('Y', width=32)
YN = Src('Y', width=16, nmode=1)


def R(i):
    assert 0 <= i < 8
    return Src('R', reg=i)


def _M(width, base, mods):
    am = 0
    for m in mods:
        assert not (am & m) and not (am & 3 and m & 3) and not (am & 12 and m & 12), 'modifier twice'
        am |= m
    if width == 24:
        assert base < BMEM_BASE and not (am & 3) == 3, 'M24 is HMEM'
    else:
        assert BMEM_BASE <= base < BMEM_BASE + 512, 'M8/M16 is BMEM'
    if width == 16:
        assert base % 2 == 0 and (am & 3) != AM_K and (am >> 2) != 1, 'M16 needs even addresses'
    return Src('M', base=base, am=am, width=width)


def M8(base, *mods):
    return _M(8, base, mods)


def M16(base, *mods):
    return _M(16, base, mods)


def M24(base, *mods):
    return _M(24, base, mods)


def YSH(sh, w, addend=None):
    assert 0 <= sh < 32 and w in (8, 16, 24)
    return Src('Y', width=w, wmode='SHA' if addend else 'SH', sh=sh,
               addend=addend.reg if addend else -1)


def YRQ(w, addend=None):
    assert w in (8, 16, 24)
    return Src('Y', width=w, wmode='RQA' if addend else 'RQ', addend=addend.reg if addend else -1)


class Program:
    def __init__(self):
        self.uops, self.entries = [], {}
        self._loops = []

    # ---------------------------------------------------------------- structure
    def entry(self, name):
        assert not self._loops and name not in self.entries
        self.entries[name] = len(self.uops)

    @contextmanager
    def over_k(self, n):
        with self._loop('k', 0, n):
            yield

    @contextmanager
    def over_d(self, n):
        assert 'k' not in self._loops, 'over_d inside over_k'
        with self._loop('d', 1, n):
            yield

    @contextmanager
    def _loop(self, name, level, n):
        assert name not in self._loops and 1 <= n <= 256
        self._emit(Uop(op=OPS.index(f'LOOP{level}'), base=n - 1))
        start = len(self.uops)
        self._loops.append(name)
        yield
        self._loops.pop()
        assert len(self.uops) > start, 'empty loop body'
        last = self.uops[-1]
        assert not last.eol >> level & 1
        last.eol |= 1 << level

    # ---------------------------------------------------------------- instructions
    def mac(self, a, b, ps=0, step=0):
        assert 'Y' not in (a.kind, b.kind) and 0 <= ps < 16
        assert not (b.kind == 'M' and b.width == 24), 'HMEM operand only on side A'
        assert not (b.kind == 'S' and b.width == 3) and not (a.kind == 'S' and a.width == 3)
        u = Uop(op=OPS.index('MAC'), ps=ps, nstep=step)
        self._src(u, 'a', a)
        self._src(u, 'b', b)
        kinds = (a.kind, b.kind)
        assert kinds.count('S') <= 1 and kinds.count('M') <= 1, 'one S and one M per uop'
        self._emit(u)

    def init(self, a):
        assert a.kind in ('Z', 'EPS')
        u = Uop(op=OPS.index('INIT'))
        self._src(u, 'a', a)
        self._emit(u)

    def mov(self, dst, src):
        dsts = dst if isinstance(dst, tuple) else (dst,)
        u = Uop(op=OPS.index('MOV'))
        assert src.kind not in ('A', 'N') and src.width != 32
        self._src(u, 'a', src)
        for t in dsts:
            if t.kind == 'RQ':
                assert src.kind == 'S' and src.width == 3 and len(dsts) == 1
            elif t.kind == 'R':
                assert src.kind != 'Y' or src.width <= 16
                u.wr, u.rb = 1, t.reg
            else:
                assert t.kind == 'M' and src.kind != 'M', 'MOV M <- M is not supported'
                assert src.kind != 'Y' or src.width == t.width or (src.width == 8 and t.width == 16)
                assert src.kind != 'S' or 8 * src.width <= t.width
                u.wm, u.base, u.am, u.mw = 1, t.base, t.am, MWS.index(t.width)
                self._check_am(t.am)
        self._emit(u)

    def nld(self, fn, src):
        assert src.kind == 'R' or (src.kind == 'Y' and src.width == 32)
        u = Uop(op=OPS.index('NLD'), wmode=NLU_FNS.index(fn))
        u.sa = SRCS.index(src.kind)
        u.ra = src.reg
        self._emit(u)

    def nlu(self, fn, src, dst):
        """dst = fn(src) on the shared NLU: load, two interpolation steps, writeback (5 uops)."""
        self.nld(fn, src)
        self.init(Z)
        self.mac(N, N, 0, step=0)
        self.mac(N, N, 0, step=1)
        self.mov(dst, YN)

    def end(self):
        assert not self._loops
        self._emit(Uop(op=OPS.index('END')))

    # ---------------------------------------------------------------- helpers
    def _src(self, u, side, s):
        assert not (side == 'a' and s.kind == 'A')
        setattr(u, f's{side}', SRCS.index(s.kind))
        if s.kind == 'R':
            setattr(u, f'r{side}', s.reg)
        elif s.kind == 'S':
            u.sw = s.width
        elif s.kind == 'M':
            u.base, u.am, u.mw = s.base, s.am, MWS.index(s.width)
            self._check_am(s.am)
        elif s.kind == 'Y':
            assert side == 'a'
            u.wmode, u.sh, u.ww, u.nstep = WMODES.index(s.wmode), s.sh, WWS.index(s.width), s.nmode
            if s.addend >= 0:
                u.ra = s.addend

    def _check_am(self, am):
        assert not (am & 3) or 'k' in self._loops, 'k used outside over_k'
        assert not (am >> 2) or 'd' in self._loops, 'd used outside over_d'

    def _emit(self, u):
        self.uops.append(u)

    def words(self):
        assert not self._loops and self.uops and OPS[self.uops[-1].op] == 'END'
        return [u.encode() for u in self.uops]
