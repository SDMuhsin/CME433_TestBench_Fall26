"""Instruction-level simulator of the mq_chip microcode on the spec-formula arithmetic.

Executes the encoded ROM words (not the builder objects), so it checks the encoding, the
loop / addressing semantics and the program against src_int8/tb/ref (and, once published,
src_int8/golden).  Not cycle accurate; `cycles` is the sequencer's issue estimate (2 clk per
uop plus the known writeback / stream stalls).
"""
from ..tb.ref import nlu_ref as nlu
from ..tb.ref.intmath import mac, rsh, sat, sext
from .isa import EPS_VAL, MWS, NLU_FNS, OPS, SRCS, WMODES, WWS, addr_offset, decode

HMEM_ENTRIES, BMEM_BASE, BMEM_BYTES = 768, 0x400, 512
Y_WAIT = 4                           # clk from the last MAC's P1 to the Y capture (arch.md)


class UcodeMachine:
    def __init__(self, words, entries):
        self.rom = [decode(w) for w in words]
        self.entries = entries
        self.hmem = [0] * HMEM_ENTRIES          # signed INT24 entries
        self.bmem = [0] * BMEM_BYTES            # bytes 0..255
        self.regs = [0] * 8                     # signed INT16
        self.rq = (1 << 14, 1)
        self.n = dict(base=0, i=0, f=0, sh=0, zero=0)

    # ---------------------------------------------------------------- run
    def run(self, entry, stream=()):
        """Run from an entry point to END; returns the number of uops executed."""
        self.stream, self.sp = list(stream), 0
        self.pc, self.cnt, self.lim, self.start = self.entries[entry], [0, 0], [0, 0], [0, 0]
        self.acc, self.first, self.init_v = 0, False, 0
        self.executed, self.cycles, self.last_mac = 0, 0, -10
        while OPS[self.rom[self.pc].op] != 'END':
            self._step(self.rom[self.pc])
            self.executed += 1
        self.cycles += 2
        assert self.sp == len(self.stream), f'stream not fully consumed: {self.sp}/{len(self.stream)}'
        return self.executed

    # ---------------------------------------------------------------- memory
    def _addr(self, u):
        return u.base + addr_offset(u.am, self.cnt[0], self.cnt[1])

    def mem_read(self, addr, width):
        if width == 24:
            assert addr < HMEM_ENTRIES
            return self.hmem[addr]
        assert BMEM_BASE <= addr < BMEM_BASE + BMEM_BYTES
        b = addr - BMEM_BASE
        if width == 8:
            return sext(self.bmem[b], 8)
        assert b % 2 == 0
        return sext(self.bmem[b] | self.bmem[b + 1] << 8, 16)

    def mem_write(self, addr, width, v):
        if width == 24:
            assert addr < HMEM_ENTRIES
            self.hmem[addr] = sext(v, 24)
            return
        assert BMEM_BASE <= addr < BMEM_BASE + BMEM_BYTES
        b = addr - BMEM_BASE
        self.bmem[b] = v & 0xFF
        if width == 16:
            assert b % 2 == 0
            self.bmem[b + 1] = (v >> 8) & 0xFF

    # ---------------------------------------------------------------- operands
    def _val(self, u, src, reg, side, a_val=None):
        name = SRCS[src]
        if name == 'Z':
            return 0
        if name == 'EPS':
            return EPS_VAL
        if name == 'S':
            n = u.sw
            v = int.from_bytes(bytes(self.stream[self.sp:self.sp + n]), 'little')
            self.sp += n
            return v if n == 3 else sext(v, 8 * n)
        if name == 'M':
            return self.mem_read(self._addr(u), MWS[u.mw])
        if name == 'R':
            return self.regs[reg]
        if name == 'Y':
            return self._wb(u)
        if name == 'N':
            if side == 'a':
                return nlu.ROM[self.n['base'] + self.n['i'] + u.nstep]
            return self.n['f'] if u.nstep else (1 << 11) - self.n['f']
        return sext(a_val, 16)                              # 'A'

    def _wb(self, u):
        self.cycles += max(0, self.last_mac + Y_WAIT - self.cycles)
        if OPS[u.op] == 'NLD':
            return self.acc                                 # raw 32 b
        if u.nstep:                                         # YN: NLU result
            return 0 if self.n['zero'] else sat(rsh(self.acc, self.n['sh']), 16)
        mode = WMODES[u.wmode]
        if mode in ('RQ', 'RQA'):
            M, s = self.rq
            v = (self.acc * M + (1 << (s - 1))) >> s
        else:
            v = rsh(self.acc, u.sh)
        if mode.endswith('A'):
            v += self.regs[u.ra]
        return sat(v, WWS[u.ww])

    # ---------------------------------------------------------------- execution
    def _step(self, u):
        op = OPS[u.op]
        self.cycles += 2
        if op == 'MAC':
            a = self._val(u, u.sa, u.ra, 'a')
            b = self._val(u, u.sb, u.rb, 'b', a)
            base = self.init_v if self.first else self.acc
            self.acc, self.first = mac(base, a, b, u.ps), False
            self.last_mac = self.cycles
        elif op == 'INIT':
            self.init_v, self.first = self._val(u, u.sa, u.ra, 'a'), True
        elif op == 'MOV':
            v = self._val(u, u.sa, u.ra, 'a')
            if SRCS[u.sa] == 'S' and u.sw == 3:
                M, s = v & 0xFFFF, v >> 16
                assert (1 << 14) <= M < (1 << 15) and 1 <= s <= 47, (M, s)
                self.rq = (M, s)
            if u.wr:
                self.regs[u.rb] = sext(v, 16)
            if u.wm:
                self.mem_write(self._addr(u), MWS[u.mw], v)
        elif op == 'NLD':
            x = self._val(u, u.sa, u.ra, 'a')
            fn = NLU_FNS[u.wmode]
            a = nlu.address(fn, x)
            self.n = dict(base=nlu.BASE[fn], **a)
        elif op in ('LOOP0', 'LOOP1'):
            lvl = int(op[-1])
            self.cnt[lvl], self.lim[lvl], self.start[lvl] = 0, u.base, self.pc + 1
        self._advance(u)

    def _advance(self, u):
        for lvl in (0, 1):
            if u.eol >> lvl & 1 and self.cnt[lvl] != self.lim[lvl]:
                self.cnt[lvl] += 1
                self.pc = self.start[lvl]
                return
        self.pc += 1

    # ---------------------------------------------------------------- views
    def logits(self):
        return [self.mem_read(0x440 + 2 * v, 16) for v in range(128)]
