"""Compare the pixels of a gate-level run with the golden model emulating the same multiplier.

python3 -m src_gan_tsmc65.sim.gls.check_pix <variant> <pix.memh> [seed=0]

run_gls.csh only checks against the exact-multiplier golden pixels; for an approximate
variant this shows that the netlist matches the variant's own integer model (bit-exact).
"""
import sys
import tempfile

from ...bench.mul_table import mul8_table
from ...common.memh import read_memh
from ...common.paths import MODEL
from ...golden.model import forward, load_model


def main(variant, pix_file, seed=0):
    zq = read_memh(MODEL / f'ref_vectors/seed_{seed}/zq.memh')
    table = None
    if variant != 'exact':
        with tempfile.TemporaryDirectory() as work:
            table = mul8_table(variant, work)
    want = forward(zq, load_model(), table)['pix'][0]
    got = read_memh(pix_file)
    mism = int((got != want).sum())
    print(f'{"PASS" if mism == 0 else "FAIL"} {variant} seed_{seed}: {784 - mism}/784 pixels match the emulation')
    return 0 if mism == 0 else 1


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 0))
