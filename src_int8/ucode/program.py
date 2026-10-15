"""The mq_chip microcode: one token step (spec.md 5.2) and the state-reset routine.

Entry 'token' consumes the 54,280-byte weight stream in spec order (section 7) and leaves the
128 INT16 logits at LOGITS; entry 'reset' zeroes the SSM and conv state (H0, H1, CONV0, CONV1).
Per-scalar op order follows spec 5.2 exactly (it is normative); memory map: spec section 6.
"""
from .asm import EPS, A, M8, M16, M24, N, Program, R, RQ, S8, S16, S24, YN, YRAW, YRQ, YSH, Z
from .asm import d, d2, d4, k, k2

CHIP_CFG = dict(vocab=128, d_model=64, n_layer=2, d_inner=96, d_state=4, dt_rank=4)
MEM = dict(H0=0x000, H1=0x180, XN=0x400, X=0x440, U=0x4C0, DBC=0x520, CONV0=0x540, CONV1=0x5A0,
           LOGITS=0x440)
STREAM_BYTES = 54280

# register allocation (R0..R7, 16 b)
T0, DT, UD, T3, T4, DA, DD = (R(i) for i in range(7))


def rmsnorm(p, D):
    """acc = 16 + sum rsh(x^2, 6); r = rsqrt(acc); XN[i] = sh_8(x[i] * r, 12)."""
    p.init(EPS)
    with p.over_k(D):
        p.mac(M16(MEM['X'], k2), A, ps=6)
    p.nlu('rsqrt', YRAW, T0)                           # r (Q6.9)
    with p.over_k(D):
        p.init(Z)
        p.mac(M16(MEM['X'], k2), T0)
        p.mov(M8(MEM['XN'], k), YSH(12, 8))


def in_x_conv(p, l, D, E):
    """xi = rq_8(W_in_x xn); xc = rq_16(w0 conv + w1 xi, cb); CONV = xi; U = sh_8(xc sig(xc), 19)."""
    conv = MEM[f'CONV{l}']
    with p.over_d(E):
        p.init(Z)
        with p.over_k(D):
            p.mac(S8, M8(MEM['XN'], k))
        p.mov(RQ, S24)
        p.mov(T0, YRQ(8))                              # xi
        p.init(Z)
        p.mac(S8, M8(conv, d))                         # w0 * CONV[d]
        p.mac(S8, T0)                                  # w1 * xi
        p.mov(M8(conv, d), T0)                         # CONV[d] = xi  (first state write: byte 197)
        p.mov(RQ, S24)
        p.mov(T3, S16)                                 # cb
        p.mov(T3, YRQ(16, addend=T3))                  # xc
        p.nlu('sigmoid', T3, T4)
        p.init(Z)
        p.mac(T3, T4)
        p.mov(M8(MEM['U'], d), YSH(19, 8))             # u


def x_proj(p, E, J):
    """DBC[j] = rq_8(W_x[j] . u)."""
    with p.over_d(J):
        p.init(Z)
        with p.over_k(E):
            p.mac(S8, M8(MEM['U'], k))
        p.mov(RQ, S24)
        p.mov(M8(MEM['DBC'], d), YRQ(8))


def channel(p, l, D, E, R_, N_):
    """dt, selective scan, D skip, z gate per channel d; U[d] <- g = sh_8(y * SiLU(z), 13)."""
    H, U, DBC = MEM[f'H{l}'], MEM['U'], MEM['DBC']
    B, C = DBC + R_, DBC + R_ + N_
    with p.over_d(E):
        p.mov(T0, S16)                                 # b_dt
        p.init(Z)
        with p.over_k(R_):
            p.mac(S8, M8(DBC, k))                      # W_dt[d, r] * DL[r]
        p.mov(RQ, S24)
        p.mov(T0, YRQ(16, addend=T0))                  # dt_pre
        p.nlu('softplus', T0, DT)                      # dt (Q3.12)
        p.mov(UD, M8(U, d))                            # u
        with p.over_k(N_):
            p.init(Z)
            p.mac(M8(B, k), UD)
            p.mov(T4, YSH(0, 16))                      # bu = B[n] u
            p.init(Z)
            p.mac(DT, S16)                             # dt * A'[d, n]
            p.nlu('exp2', YRAW, DA)                    # dA (Q0.15)
            p.init(Z)
            p.mac(M24(H, d4, k), DA, ps=15)            # dA * H
            p.mac(DT, T4, ps=4)                        # dt * bu
            p.mov(M24(H, d4, k), YSH(0, 24))
        p.mov(DD, S8)                                  # D[d]
        p.init(Z)
        with p.over_k(N_):
            p.mov(T3, M8(C, k))
            p.mac(M24(H, d4, k), T3, ps=11)            # H[d, n] * C[n]
        p.mac(DD, UD)                                  # D[d] * u
        p.mov(T0, YSH(1, 16))                          # y (Q6.9)
        p.init(Z)
        with p.over_k(D):
            p.mac(S8, M8(MEM['XN'], k))
        p.mov(RQ, S24)
        p.mov(T3, YRQ(16))                             # z
        p.nlu('sigmoid', T3, T4)
        p.init(Z)
        p.mac(T3, T4)
        p.mov(T4, YSH(15, 16))                         # SiLU(z)
        p.init(Z)
        p.mac(T0, T4)
        p.mov(M8(U, d), YSH(13, 8))                    # g


def out_proj(p, D, E):
    """X[i] = rq_16(W_out[i] . g, X[i])."""
    with p.over_d(D):
        p.mov(T0, M16(MEM['X'], d2))
        p.init(Z)
        with p.over_k(E):
            p.mac(S8, M8(MEM['U'], k))
        p.mov(RQ, S24)
        p.mov(M16(MEM['X'], d2), YRQ(16, addend=T0))


def build(cfg=CHIP_CFG):
    """-> assembled Program with entries 'token' and 'reset'."""
    D, E, V = cfg['d_model'], cfg['d_inner'], cfg['vocab']
    R_, N_ = cfg['dt_rank'], cfg['d_state']
    p = Program()

    p.entry('token')
    with p.over_k(D):
        p.mov(M16(MEM['X'], k2), S16)                  # embedding row
    for l in range(cfg['n_layer']):
        rmsnorm(p, D)
        in_x_conv(p, l, D, E)
        x_proj(p, E, R_ + 2 * N_)
        channel(p, l, D, E, R_, N_)
        out_proj(p, D, E)
    rmsnorm(p, D)
    with p.over_d(V):
        p.init(Z)
        with p.over_k(D):
            p.mac(S8, M8(MEM['XN'], k))
        p.mov(RQ, S24)
        p.mov(M16(MEM['LOGITS'], d2), YRQ(16))
    p.end()

    p.entry('reset')
    with p.over_d(cfg['n_layer'] * E):                 # 768 H entries = 192 x 4
        with p.over_k(N_):
            p.mov(M24(MEM['H0'], d4, k), Z)
    with p.over_k(cfg['n_layer'] * E):                 # CONV0, CONV1: 192 contiguous bytes
        p.mov(M8(MEM['CONV0'], k), Z)
    p.end()
    return p
