"""Python side of the closed-loop chip simulation: runs tb_mb_demo behind two named pipes.

The simulator is either an iverilog image (`*.vvp`, run with `vvp -n`) or a Verilator binary
(`src/demo/tb/build_verilator.sh`), which is about 20x faster.
"""
import os
import subprocess
from pathlib import Path

import numpy as np

from src.golden.data.stream import token_stream
from src.golden.host.vectors import write_memh


def write_stream_tables(P, out):
    """Token-independent stream (base) + E_in table -> memh files the TB loads."""
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    write_memh(out / 'base.memh', token_stream(P, 0))
    write_memh(out / 'emb.memh', np.asarray(P['E_in'], np.uint16).reshape(-1))
    return out / 'base.memh', out / 'emb.memh'


def sim_argv(sim):
    """Simulator command line: `vvp -n x.vvp` for iverilog, else the Verilator binary itself."""
    sim = str(sim)
    return ['vvp', '-n', sim] if sim.endswith('.vvp') else [sim]


class ChipSim:
    """step(byte, reset) -> (128 FP16 logit bit patterns read back from the chip, cycle info dict)."""

    def __init__(self, sim, base, emb, workdir, log):
        work = Path(workdir)
        work.mkdir(parents=True, exist_ok=True)
        self.cmd_path, self.rsp_path = work / 'cmd.fifo', work / 'rsp.fifo'
        for p in (self.cmd_path, self.rsp_path):
            if p.exists():
                p.unlink()
            os.mkfifo(p)
        self.log = open(log, 'w')
        self.proc = subprocess.Popen(
            sim_argv(sim) + [f'+BASE={base}', f'+EMB={emb}', f'+CMD={self.cmd_path}',
             f'+RSP={self.rsp_path}'], stdout=self.log, stderr=subprocess.STDOUT)
        self.cmd = open(self.cmd_path, 'w')     # same order as the TB: CMD, then RSP
        self.rsp = open(self.rsp_path, 'r')

    def step(self, byte, reset=False):
        self.cmd.write(f'{(0x100 if reset else 0) | byte:03x}\n')
        self.cmd.flush()
        head = self.rsp.readline().split()
        if not head or head[0] != 'T':
            raise RuntimeError(f'chip TB stopped (see {self.log.name}): {head}')
        done, stream, total, waits, errors = map(int, head[1:])
        logits = np.array([int(w, 16) for w in self.rsp.readline().split()], np.uint16)
        return logits, dict(done=done, stream=stream, total=total, waits=waits, errors=errors)

    def close(self):
        """-> TB error count reported at the end of simulation."""
        self.cmd.write('200\n')
        self.cmd.flush()
        tail = self.rsp.readline().split()
        self.proc.wait()
        self.log.close()
        for p in (self.cmd_path, self.rsp_path):
            p.unlink()
        return int(tail[2]) if tail and tail[0] == 'E' else -1
