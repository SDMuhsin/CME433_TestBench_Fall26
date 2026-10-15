"""Layer tests: every golden layer op fed with the same integer inputs as the QAT fake-quant op
(torch, float64), compared at low tolerance.  The torch side uses the exporter's integer weights
dequantised with the exporter's float64 row scales (the float32 fake-quant of training rounds one
E_out weight differently at an exact .5 tie; the exporter is the authority).  The only differences
allowed are the LUT interpolation error (sigmoid / softplus / rsqrt <= 1 LSB of the result,
softplus <= 3 LSB of DT, exp2 <= 5 LSB of DA) and the 2^-14 (M, s) approximation.
"""
import numpy as np
import pytest

from src_int8.golden.io.weights import load_float_params, quantise, row_scales
from src_int8.golden.layers.conv import in_x_conv
from src_int8.golden.layers.norm import rmsnorm
from src_int8.golden.layers.proj import logits, out_proj, x_proj
from src_int8.golden.layers.scan import dt_of, gate, scan_step, y_of
from src_int8.golden.model import HwModel
from src_int8.golden.ops.formats import ACT, PARAM

from .conftest import QAT_CKPT

torch = pytest.importorskip('torch')
from src_int8.model.qat.qmamba import H_CLIP, q_sigmoid, q_softplus  # noqa: E402
from src_int8.model.qat.ste import fq  # noqa: E402

TEXT = b'Once upon a time, there was a little girl named Lily who liked to play.'


@pytest.fixture(scope='module')
def setup():
    if not QAT_CKPT.exists():
        pytest.skip('no QAT checkpoint')
    cfg, Pf = load_float_params(QAT_CKPT)
    P = quantise(Pf, cfg)
    model = HwModel(cfg, P)
    hist = []
    for t in TEXT:
        pr = []
        rec = dict(x=P['E_in'][[t]], h0=[h.copy() for h in model.h], conv0=[c.copy() for c in model.conv])
        model.step([t], pr)
        rec['probes'] = pr
        hist.append(rec)
    return cfg, P, Pf, hist


def T(a, scale=1.0):
    return torch.as_tensor(np.asarray(a, dtype=np.float64) * scale)


def deq(q, w_float):
    """Exporter INT8 weights -> float64 torch tensor q * s_row(w_float)."""
    return T(q * row_scales(w_float)[..., None])


def conv_deq(L, Lf):
    s = row_scales(np.stack([Lf['conv_w0'], Lf['conv_w1']], -1))
    return T(L['conv_w0'] * s), T(L['conv_w1'] * s)


def fixed(q, fmt):
    return T(q, fmt.scale)


def assert_close(golden, torch_val, fmt, tol):
    d = np.abs(np.asarray(golden) - torch_val.detach().double().numpy() * 2 ** fmt.frac)
    assert d.max() <= tol, f'max diff {d.max()} LSB > {tol}'


def x_in(rec, l):
    return rec['x'] if l == 0 else rec['probes'][0]['x_out']


def test_rmsnorm_vs_torch(setup):
    cfg, P, Pf, hist = setup
    for rec in hist:
        for l, pr in enumerate(rec['probes']):
            x = T(x_in(rec, l), 2 ** -8)
            r = fq(torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + 2 ** -12), ACT['R'])
            assert_close(pr['xn'], fq(x * r, ACT['XN']), ACT['XN'], 1)
            assert np.array_equal(pr['xn'], rmsnorm(x_in(rec, l)))


def test_in_x_conv_vs_torch(setup):
    cfg, P, Pf, hist = setup
    for rec in hist:
        for l, pr in enumerate(rec['probes']):
            L, Lf = P['layers'][l], Pf['layers'][l]
            xn = T(pr['xn'], 2 ** -5)
            assert_close(pr['xi'], fq(xn @ deq(L['W_in_x'], Lf['W_in_x']).t(), ACT['XI']), ACT['XI'], 1)
            w0, w1 = conv_deq(L, Lf)
            xc = fq(fixed(L['cb'], PARAM['CB']) + w0 * T(rec['conv0'][l], 2 ** -4) + w1 * T(pr['xi'], 2 ** -4), ACT['XC'])
            assert_close(pr['xc'], xc, ACT['XC'], 1)
            xc_t = T(pr['xc'], 2 ** -8)
            assert_close(pr['u'], fq(xc_t * q_sigmoid(xc_t), ACT['U']), ACT['U'], 1)
            xi, u, _ = in_x_conv(pr['xn'], rec['conv0'][l], L)
            assert np.array_equal(xi, pr['xi']) and np.array_equal(u, pr['u'])


def test_x_proj_and_dt_vs_torch(setup):
    cfg, P, Pf, hist = setup
    R, N = cfg['dt_rank'], cfg['d_state']
    for rec in hist:
        for l, pr in enumerate(rec['probes']):
            L, Lf = P['layers'][l], Pf['layers'][l]
            dbc = T(pr['u'], 2 ** -4) @ deq(L['W_x'], Lf['W_x']).t()
            assert_close(pr['dl'], fq(dbc[..., :R], ACT['DL']), ACT['DL'], 1)
            assert_close(pr['B'], fq(dbc[..., R:R + N], ACT['B']), ACT['B'], 1)
            assert_close(pr['C'], fq(dbc[..., R + N:], ACT['C']), ACT['C'], 1)
            dt_pre = fq(T(pr['dl'], 2 ** -3) @ deq(L['W_dt'], Lf['W_dt']).t() + fixed(L['b_dt'], PARAM['B_DT']),
                        ACT['DT_PRE'])
            assert_close(pr['dt_pre'], dt_pre, ACT['DT_PRE'], 1)
            assert_close(pr['dt'], q_softplus(T(pr['dt_pre'], 2 ** -8)), ACT['DT'], 3)
            dt, dt_pre_g = dt_of(pr['dl'], L)
            assert np.array_equal(dt, pr['dt']) and np.array_equal(dt_pre_g, pr['dt_pre'])


def test_scan_y_gate_vs_torch(setup):
    cfg, P, Pf, hist = setup
    for rec in hist:
        for l, pr in enumerate(rec['probes']):
            L, Lf = P['layers'][l], Pf['layers'][l]
            dt, u = T(pr['dt'], 2 ** -12), T(pr['u'], 2 ** -4)
            p = dt[..., None] * fixed(L['A2'], PARAM['A2'])
            dA = torch.where(p <= -16.0, torch.zeros_like(p), fq(torch.exp2(p), ACT['DA']))
            assert_close(pr['dA'], dA, ACT['DA'], 5)
            dA_g = T(pr['dA'], 2 ** -15)                               # continue with the golden dA
            h = dA_g * T(rec['h0'][l], 2 ** -17) + (dt * u)[..., None] * T(pr['B'], 2 ** -5)[:, None, :]
            hn, _, _ = scan_step(rec['h0'][l], pr['u'], pr['dt'], pr['B'], L)
            assert_close(hn, fq(h.clamp(-H_CLIP, H_CLIP), ACT['H']), ACT['H'], 1)
            y = (T(hn, 2 ** -17) * T(pr['C'], 2 ** -4)[:, None, :]).sum(-1) + fixed(L['D'], PARAM['D']) * u
            assert_close(pr['y'], fq(y, ACT['Y']), ACT['Y'], 1)
            assert np.array_equal(y_of(hn, pr['u'], pr['C'], L), pr['y'])
            z = fq(T(pr['xn'], 2 ** -5) @ deq(L['W_in_z'], Lf['W_in_z']).t(), ACT['Z'])
            assert_close(pr['z'], z, ACT['Z'], 1)
            z_t = T(pr['z'], 2 ** -8)
            assert_close(pr['sz'], fq(z_t * q_sigmoid(z_t), ACT['SZ']), ACT['SZ'], 1)
            assert_close(pr['g'], fq(T(pr['y'], 2 ** -9) * T(pr['sz'], 2 ** -8), ACT['G']), ACT['G'], 1)
            g, _, _ = gate(pr['y'], pr['xn'], L)
            assert np.array_equal(g, pr['g'])


def test_out_proj_and_logits_vs_torch(setup):
    cfg, P, Pf, hist = setup
    E_out = deq(P['E_out'], Pf['E_out'])
    for rec in hist:
        for l, pr in enumerate(rec['probes']):
            L, Lf = P['layers'][l], Pf['layers'][l]
            xo = fq(T(x_in(rec, l), 2 ** -8) + T(pr['g'], 2 ** -4) @ deq(L['W_out'], Lf['W_out']).t(), ACT['X'])
            assert_close(pr['x_out'], xo, ACT['X'], 1)
            assert np.array_equal(out_proj(pr['g'], x_in(rec, l), L), pr['x_out'])
        xn = rmsnorm(rec['probes'][-1]['x_out'])
        assert_close(logits(xn, P['E_out'], P['rq_logits']), fq(T(xn, 2 ** -5) @ E_out.t(), ACT['LOGITS']),
                     ACT['LOGITS'], 1)


def test_fake_quant_weights_equal_exporter_up_to_float32_ties(setup, qat_model):
    """Training's float32 per-row quantisation and the float64 exporter agree on every weight
    except exact .5 ties (one E_out entry in the shipped checkpoint)."""
    from src_int8.model.qat.ste import fq_rows, row_scales as t_scales
    cfg, P, Pf, _ = setup
    with torch.no_grad():
        w = qat_model.embed.weight * qat_model.norm_f.weight[None, :]
        q = torch.round(w / t_scales(w)).numpy()
    diff = np.argwhere(q != P['E_out'])
    assert len(diff) <= 1
    for v, k in diff:
        assert abs(abs(Pf['E_out'][v, k] / row_scales(Pf['E_out'])[v]) % 1 - 0.5) < 1e-5
