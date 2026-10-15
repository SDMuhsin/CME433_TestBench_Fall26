"""Assembler for the mb_chip micro-instruction set (see isa.py).

Programs are written with a small Python builder:

    p = Program()
    p.entry('token')
    with p.over_d(96):                 # level-1 loop, counter d
        p.init(Z)
        with p.over_k(64):             # level-0 loop, counter k
            p.mac(S, M(XN, k))
        p.mov(M(U, d), Y())

Operands: Z, EPS, S, A, R(i), M(base, k | d | d4 ...), Y(scale 0 | -6), YN (NLU result),
N (NLU operand; the step is given to mac()).  The assembler checks the operand rules and the
loop structure and sets the end-of-loop bits of the last uop of each body.
"""
from contextlib import contextmanager
from dataclasses import dataclass

from .isa import AM_D, AM_D4, AM_K, MODES, NLU_FNS, OPS, SRCS, Uop


@dataclass(frozen=True)
class Src:
    kind: str
    reg: int = 0
    base: int = 0
    am: int = 0
    mode: str = 'WB0'


k, d, d4 = AM_K, AM_D, AM_D | AM_D4
Z, EPS, S, A, N = Src('Z'), Src('EPS'), Src('S'), Src('A'), Src('N')
YN = Src('Y', mode='WBN')


def R(i):
    assert 0 <= i < 8
    return Src('R', reg=i)


def M(base, *mods):
    am = 0
    for m in mods:
        assert not (am & m), 'address modifier used twice'
        am |= m
    return Src('M', base=base, am=am)


def Y(scale=0):
    return Src('Y', mode={0: 'WB0', -6: 'WB6'}[scale])


class Program:
    def __init__(self):
        self.uops, self.entries = [], {}
        self._loops = []                       # stack of 'k' / 'd'

    # ---------------------------------------------------------------- structure
    def entry(self, name):
        assert not self._loops and name not in self.entries
        self.entries[name] = len(self.uops)

    @contextmanager
    def over_k(self, n):
        """Level-0 loop: body runs n times with k = 0 .. n-1 (innermost only)."""
        with self._loop('k', 0, n):
            yield

    @contextmanager
    def over_d(self, n):
        """Level-1 loop: body runs n times with d = 0 .. n-1 (may contain over_k loops)."""
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
    def mac(self, a, b, step=0):
        assert 'Y' not in (a.kind, b.kind), 'MAC operands cannot be Y'
        u = Uop(op=OPS.index('MAC'), nstep=step)
        self._src(u, 'a', a)
        self._src(u, 'b', b)
        self._mem_rule(a, b)
        self._emit(u)

    def init(self, a):
        u = Uop(op=OPS.index('INIT'))
        self._src(u, 'a', a)
        self._emit(u)

    def mov(self, dst, src):
        dsts = dst if isinstance(dst, tuple) else (dst,)
        u = Uop(op=OPS.index('MOV'))
        self._src(u, 'a', src)
        for t in dsts:
            if t.kind == 'R':
                u.wr, u.rb = 1, t.reg
            else:
                assert t.kind == 'M' and src.kind != 'M', 'MOV M <- M is not supported'
                u.wm, u.base, u.am = 1, t.base, t.am
                self._check_am(t.am)
        self._emit(u)

    def nld(self, fn, r):
        assert r.kind == 'R'
        self._emit(Uop(op=OPS.index('NLD'), ra=r.reg, mode=NLU_FNS.index(fn)))

    def nlu(self, fn, x, dst):
        """dst = fn(x) on the shared NLU: load, two interpolation steps, writeback."""
        self.nld(fn, x)
        self.init(Z)
        self.mac(N, N, step=0)
        self.mac(N, N, step=1)
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
        if s.kind == 'Y':
            u.mode = MODES.index(s.mode)
        if s.kind == 'M':
            u.base, u.am = s.base, s.am
            self._check_am(s.am)

    @staticmethod
    def _mem_rule(a, b):
        kinds = (a.kind, b.kind)
        assert kinds.count('S') <= 1 and kinds.count('M') <= 1, 'one S and one M per uop'

    def _check_am(self, am):
        assert not (am & AM_K) or 'k' in self._loops, 'k used outside over_k'
        assert not (am & AM_D) or 'd' in self._loops, 'd used outside over_d'

    def _emit(self, u):
        self.uops.append(u)

    def words(self):
        assert not self._loops and self.uops and OPS[self.uops[-1].op] == 'END'
        return [u.encode() for u in self.uops]
