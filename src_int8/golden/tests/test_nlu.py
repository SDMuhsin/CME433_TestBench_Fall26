"""Spec 5.1: ROM image, address arithmetic edges, interpolation accuracy (exhaustive where the
spec is exhaustive: all 4,097 uniform inputs, all 2^19 exp2 fractions, 3 x 2^16 rsqrt inputs)."""
import numpy as np

from src_int8.golden.ops.nlu import (EXP2, FRAC_ONE, FUNCS, ROM, ROM_WORDS, RSQRT, SIGMOID,
                                     SOFTPLUS, addr_exp2, addr_rsqrt, addr_uniform, exp2, lerp,
                                     rsqrt, sigmoid, silu16, softplus)


def test_rom_layout_and_anchor_values():
    assert ROM_WORDS == 340 and len(ROM) == 340
    assert [(f.base, f.end) for f in FUNCS] == [(0, 129), (129, 258), (258, 291), (291, 340)]
    assert np.all((ROM >= 0) & (ROM < 65536))
    assert ROM[SIGMOID.base + 64] == 1 << 14 and ROM[SIGMOID.base + 128] == 32757 and ROM[0] == 11
    assert ROM[SOFTPLUS.base + 128] == 32767 and ROM[SOFTPLUS.base + 64] == round(np.log(2) * 4096)
    assert ROM[EXP2.base] == 1 << 14 and ROM[EXP2.base + 32] == 1 << 15
    assert ROM[RSQRT.base] == 1 << 14 and ROM[RSQRT.base + 48] == 1 << 13
    assert np.all(np.diff(ROM[SIGMOID.base:SIGMOID.end]) >= 0)
    assert np.all(np.diff(ROM[RSQRT.base:RSQRT.end]) < 0)


def test_uniform_address_edges():
    x = np.array([-100000, -2048, -2047, -1, 0, 31, 32, 2047, 2048, 100000])
    i, f, s, z = addr_uniform(x)
    assert i.tolist() == [0, 0, 0, 63, 64, 64, 65, 127, 127, 127]
    assert f.tolist() == [0, 0, 64, 31 * 64, 0, 31 * 64, 0, 31 * 64, FRAC_ONE, FRAC_ONE]
    assert np.all(s == 11) and not z.any()
    assert sigmoid(np.array([2048]))[0] == ROM[128] and sigmoid(np.array([-2048]))[0] == ROM[0]
    assert softplus(np.array([2048, 100000]))[0] == 32767 and softplus(np.array([100000]))[0] == 32767


def test_exp2_address_edges_and_zero_flag():
    q = 1 << 19
    p = np.array([5, 0, -1, -q, -q - 1, -15 * q, -16 * q + 1, -16 * q, -(1 << 31)])
    i, f, s, z = addr_exp2(p)
    assert i.tolist() == [0, 0, 31, 0, 31, 0, 0, 0, 0]
    assert f.tolist() == [0, 0, 0x7FF, 0, 0x7FF, 0, 0, 0, 0]
    assert s.tolist() == [10, 10, 11, 11, 12, 25, 26, 26, 26]
    assert z.tolist() == [False] * 7 + [True, True]
    assert exp2(p).tolist()[:4] == [32767, 32767, 32767, 1 << 14]
    assert exp2(np.array([-16 * q, -(1 << 31)])).tolist() == [0, 0]


def test_rsqrt_address_edges():
    n = np.array([16, 17, 1 << 16, (1 << 17) - 1, 1 << 17, (1 << 18) - 1, 1 << 18, (1 << 31) - 1])
    i, f, s, z = addr_rsqrt(n)
    assert s.tolist() == [10, 10, 16, 16, 16, 16, 17, 23]
    assert i.tolist() == [0, 1, 0, 15, 16, 47, 0, 15]        # 17/16 -> segment 1; 2^31-1 -> m = 2 - eps
    assert rsqrt(np.array([1 << 16, 1 << 18, 1 << 20]))[:].tolist() == [512, 256, 128]
    assert rsqrt(np.array([16]))[0] == 32767      # 64.0 saturates the signed Q6.9


def _sigma_exact(fn, x, addr):
    """Interpolated value before the output rounding, as a float of the lane Sigma."""
    i, f, s, _ = addr(x)
    sigma = ROM[fn.base + i] * (FRAC_ONE - f) + ROM[fn.base + i + 1] * f
    return sigma.astype(np.float64), s


def test_sigmoid_softplus_accuracy_all_inputs():
    x = np.arange(-2048, 2049)
    ref = 1 / (1 + np.exp(-x / 256))
    assert np.abs(sigmoid(x) / 2 ** 15 - ref).max() <= 2.1e-4
    ref = np.minimum(np.logaddexp(0, x / 256), 8 - 2 ** -12)
    assert np.abs(softplus(x) / 2 ** 12 - ref).max() <= 6.5e-4


def test_exp2_accuracy_all_fractions():
    frac = np.arange(1 << 19, dtype=np.int64)
    for e in (-1, -5, -16):                     # same fraction grid in every octave
        p = e * (1 << 19) + frac
        p = p[p > -(16 << 19)]
        sigma, s = _sigma_exact(EXP2, p, addr_exp2)
        val = sigma / 2 ** 25 * 2.0 ** (p // (1 << 19))
        ref = np.exp2(p / 2 ** 19)
        assert (np.abs(val - ref) / ref).max() <= 7.9e-5
        assert np.abs(exp2(p) - np.minimum(np.round(ref * 2 ** 15), 32767)).max() <= 5
    assert np.abs(exp2(np.array([-1, -2, -20])) - 32767).max() <= 1        # exact grid point 2^0


def test_rsqrt_accuracy_all_mantissas():
    n = np.arange(1 << 16, 1 << 18, dtype=np.int64)     # every mantissa at E = 0, plus shifted copies
    for shift in (0, 2, -2):
        m = n << shift if shift > 0 else n >> -shift
        m = m[m >= 16]
        sigma, s = _sigma_exact(RSQRT, m, addr_rsqrt)
        val = sigma / 2.0 ** (s + 9)                      # R = Sigma >> sh_fn in Q6.9
        ref = 1 / np.sqrt(m / 2 ** 16)
        assert (np.abs(val - ref) / ref).max() <= 3.6e-4


def test_silu16_definition():
    x = np.arange(-4000, 4000, 7)
    ref = (x * sigmoid(x) + (1 << 14)) >> 15
    assert np.array_equal(silu16(x), np.clip(ref, -32768, 32767))


def test_lerp_is_two_lane_macs():
    i, f = np.array([3, 127]), np.array([5, 2048])
    assert lerp(SIGMOID, i, f, np.array([11, 11])).tolist() == \
        [(ROM[3] * (2048 - 5) + ROM[4] * 5 + 1024) >> 11, ROM[128]]
