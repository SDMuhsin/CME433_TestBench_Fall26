"""The mb_chip microcode: one token step (spec section 5) and the state-reset routine.

Entry 'token' consumes the weight stream in spec order (src/golden/data/stream.py) and leaves the
128 FP16 logits at LOGITS; entry 'reset' zeroes the SSM and conv state (H*, CONV*).
Per-scalar op order follows src/golden/net/layers.py exactly (it is normative).
"""
from src.golden.data.memmap import memory_map

from .asm import EPS, A, M, N, Program, R, S, Y, YN, Z, d, d4, k

CHIP_CFG = dict(vocab=128, d_model=64, n_layer=2, d_inner=96, d_state=4, dt_rank=4)

# register allocation (R0..R7)
T0, DT, DTU, T3, T4 = R(0), R(1), R(2), R(3), R(4)


def rmsnorm(p, mm, D):
    """XN = X * rsqrt(2^-6 * (2^-6 + sum X^2)), gain folded into the next weights."""
    p.init(EPS)
    with p.over_k(D):
        p.mac(M(mm['X'], k), A)
    p.mov(T0, Y(-6))                                   # ms
    p.nlu('rsqrt', T0, T0)                             # r
    with p.over_k(D):
        p.init(Z)
        p.mac(M(mm['X'], k), T0)
        p.mov(M(mm['XN'], k), Y())


def in_x_conv(p, mm, l, D, E):
    """xi = W_in_x xn; u = SiLU(cb + w0 * CONV + w1 * xi); CONV = xi."""
    conv, U = mm[f'CONV{l}'], mm['U']
    with p.over_d(E):
        p.init(Z)
        with p.over_k(D):
            p.mac(S, M(mm['XN'], k))
        p.mov(T0, Y())                                 # xi
        p.init(S)                                      # cb
        p.mac(S, M(conv, d))                           # w0 * prev
        p.mac(S, T0)                                   # w1 * xi
        p.mov(T3, Y())                                 # xc
        p.mov(M(conv, d), T0)
        p.nlu('sigmoid', T3, T4)
        p.init(Z)
        p.mac(T3, T4)
        p.mov(M(U, d), Y())                            # u = SiLU(xc)


def x_proj(p, mm, E, J):
    """DBC[j] = W_x[j] . u  (dt_low | B | C)."""
    with p.over_d(J):
        p.init(Z)
        with p.over_k(E):
            p.mac(S, M(mm['U'], k))
        p.mov(M(mm['DBC'], d), Y())


def channel(p, mm, l, D, E, R_, N_):
    """dt, selective scan, D skip and gating per channel d; U[d] <- y * SiLU(z)."""
    H, U, DBC = mm[f'H{l}'], mm['U'], mm['DBC']
    with p.over_d(E):
        p.init(S)                                      # b_dt
        with p.over_k(R_):
            p.mac(S, M(DBC, k))                        # W_dt[d, r] * dl[r]
        p.mov(T0, Y())
        p.nlu('softplus', T0, DT)                      # dt
        p.init(Z)
        p.mac(DT, M(U, d))
        p.mov(DTU, Y())                                # dtu = dt * u
        with p.over_k(N_):
            p.init(Z)
            p.mac(DT, S)                               # dt * A'[d, n]
            p.mov(T3, Y())
            p.nlu('exp2', T3, T3)                      # dA
            p.init(Z)
            p.mac(T3, M(H, d4, k))                     # dA * H
            p.mac(DTU, M(DBC + R_, k))                 # dtu * B[n]
            p.mov(M(H, d4, k), Y())
        p.init(Z)
        with p.over_k(N_):
            p.mov(T3, M(H, d4, k))
            p.mac(M(DBC + R_ + N_, k), T3)             # C[n] * H[d, n]
        p.mac(S, M(U, d))                              # D[d] * u
        p.mov(T0, Y())                                 # y
        p.init(Z)
        with p.over_k(D):
            p.mac(S, M(mm['XN'], k))
        p.mov(T3, Y())                                 # z
        p.nlu('sigmoid', T3, T4)
        p.init(Z)
        p.mac(T3, T4)
        p.mov(T4, Y())                                 # SiLU(z)
        p.init(Z)
        p.mac(T0, T4)
        p.mov(M(U, d), Y())                            # y * SiLU(z)


def out_proj(p, mm, D, E):
    """X[i] = X[i] + W_out[i] . U  (residual is the accumulator init)."""
    with p.over_d(D):
        p.init(M(mm['X'], d))
        with p.over_k(E):
            p.mac(S, M(mm['U'], k))
        p.mov(M(mm['X'], d), Y())


def build(cfg=CHIP_CFG):
    """-> assembled Program with entries 'token' and 'reset'."""
    mm = {name: base for name, base, _ in memory_map(cfg)}
    D, E, V = cfg['d_model'], cfg['d_inner'], cfg['vocab']
    R_, N_ = cfg['dt_rank'], cfg['d_state']
    p = Program()

    p.entry('token')
    with p.over_k(D):
        p.mov(M(mm['X'], k), S)                        # embedding row
    for l in range(cfg['n_layer']):
        rmsnorm(p, mm, D)
        in_x_conv(p, mm, l, D, E)
        x_proj(p, mm, E, R_ + 2 * N_)
        channel(p, mm, l, D, E, R_, N_)
        out_proj(p, mm, D, E)
    rmsnorm(p, mm, D)
    with p.over_d(V):
        p.init(Z)
        with p.over_k(D):
            p.mac(S, M(mm['XN'], k))
        p.mov(M(mm['LOGITS'], d), Y())
    p.end()

    p.entry('reset')
    state_words = mm['XN']                             # H*, CONV* occupy [0, XN)
    assert state_words % 4 == 0 and all(mm[f'{r}{l}'] < state_words for r in ('H', 'CONV')
                                        for l in range(cfg['n_layer']))
    with p.over_d(state_words // 4):
        with p.over_k(4):
            p.mov(M(0, d4, k), Z)
    p.end()
    return p
