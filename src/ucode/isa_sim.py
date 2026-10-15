"""Instruction-level simulator of the mb_chip microcode on the golden arithmetic.

Executes the encoded ROM words (not the builder objects), so it checks the encoding, the
loop/addressing semantics and the program against src/golden.  Not cycle accurate.
"""
import numpy as np

from src.golden.arith import nlu
from src.golden.arith.fp import mac, value, writeback
from src.golden.data.memmap import WORDS_PER_PAIR

from .isa import AM_D, AM_D4, AM_K, EPS_BITS, MODES, NLU_FNS, OPS, SRCS, decode


class UcodeMachine:
    def __init__(self, words, entries, mem_words=5 * WORDS_PER_PAIR):
        self.rom = [decode(w) for w in words]
        self.entries = entries
        self.mem = np.zeros(mem_words, np.uint16)
        self.regs = np.zeros(8, np.uint16)

    def run(self, entry, stream=()):
        """Run from an entry point to END; returns the number of uops executed."""
        self.stream, self.sp = np.asarray(stream, np.uint16), 0
        self.pc, self.cnt, self.lim, self.start = self.entries[entry], [0, 0], [0, 0], [0, 0]
        self.acc, self.first, self.init_v = np.float32(0), False, 0
        executed = 0
        while OPS[self.rom[self.pc].op] != 'END':
            self._step(self.rom[self.pc])
            executed += 1
        assert self.sp == len(self.stream), 'stream not fully consumed'
        return executed

    # ---------------------------------------------------------------- execution
    def _addr(self, u):
        a = u.base
        if u.am & AM_K:
            a += self.cnt[0]
        if u.am & AM_D:
            a += self.cnt[1] * (4 if u.am & AM_D4 else 1)
        return a

    def _val(self, u, src, reg, side, a_val=None):
        name = SRCS[src]
        if name == 'Z':
            return 0
        if name == 'EPS':
            return EPS_BITS
        if name == 'S':
            self.sp += 1
            return int(self.stream[self.sp - 1])
        if name == 'M':
            return int(self.mem[self._addr(u)])
        if name == 'R':
            return int(self.regs[reg])
        if name == 'Y':
            return self._wb(MODES[u.mode])
        if name == 'N':
            if side == 'a':
                return int(nlu.ROM[self.n_base + self.n_i + u.nstep])
            return int(self.n_f if u.nstep else self.n_omf)
        return a_val                                    # 'A'

    def _wb(self, mode):
        if mode == 'WBN':
            if self.n_byp:
                return self.n_x
            return int(writeback(self.acc, int(self.n_scale)))
        return int(writeback(self.acc, -6 if mode == 'WB6' else 0))

    def _step(self, u):
        op = OPS[u.op]
        if op == 'MAC':
            a = self._val(u, u.sa, u.ra, 'a')
            b = self._val(u, u.sb, u.rb, 'b', a)
            base = value(self.init_v) if self.first else self.acc
            self.acc, self.first = mac(base, a, b), False
        elif op == 'INIT':
            self.init_v, self.first = self._val(u, u.sa, u.ra, 'a'), True
        elif op == 'MOV':
            v = self._val(u, u.sa, u.ra, 'a')
            if u.wr:
                self.regs[u.rb] = v
            if u.wm:
                self.mem[self._addr(u)] = v
        elif op == 'NLD':
            self._nld(NLU_FNS[u.mode], int(self.regs[u.ra]))
        elif op in ('LOOP0', 'LOOP1'):
            lvl = int(op[-1])
            self.cnt[lvl], self.lim[lvl], self.start[lvl] = 0, u.base, self.pc + 1
        self._advance(u)

    def _nld(self, fn_name, x):
        fn = nlu.FUNCS[NLU_FNS.index(fn_name)]
        i, f, omf, scale = nlu.address(fn, np.uint16(x))
        self.n_base, self.n_i, self.n_f, self.n_omf = fn.base, int(i), int(f), int(omf)
        self.n_scale, self.n_x = int(scale), x
        self.n_byp = fn is nlu.SOFTPLUS and float(value(np.uint16(x))) >= fn.hi

    def _advance(self, u):
        for lvl in (0, 1):
            if u.eol >> lvl & 1 and self.cnt[lvl] != self.lim[lvl]:
                self.cnt[lvl] += 1
                self.pc = self.start[lvl]
                return
        self.pc += 1
