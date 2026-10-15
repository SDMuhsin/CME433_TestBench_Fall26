"""Product shifts and writeback shifts of spec 5.2, derived from the format table and asserted
against the spec's literal values so a format change surfaces here first."""
from ..ops.formats import ACT, PARAM

F = {k: v.frac for k, v in ACT.items()}
PF = {k: v.frac for k, v in PARAM.items()}

PS_MS = 6                                  # mean of 64 squares: sum >> 6, Q.16 result
SH_XN = F['X'] + F['R'] - F['XN']          # x Q7.8 * r Q6.9 -> XN 2^-5
SH_U = F['XC'] + F['SIG'] - F['U']         # xc Q7.8 * sig Q0.15 -> U 2^-4
PS_HDA = F['DA']                           # H Q.17 * dA Q0.15 -> Q.17
PS_DTBU = F['DT'] + F['BU'] - F['H']       # dt Q.12 * bu 2^-9 -> Q.17
PS_HC = F['H'] + F['C'] - (PF['D'] + F['U'])   # H Q.17 * C 2^-4 -> 2^-10 (D * u units)
SH_Y = PF['D'] + F['U'] - F['Y']           # 2^-10 -> Y 2^-9
SH_SZ = F['Z'] + F['SIG'] - F['SZ']        # z Q7.8 * sig Q0.15 -> SZ Q7.8
SH_G = F['Y'] + F['SZ'] - F['G']           # y Q6.9 * sz Q7.8 -> G 2^-4

assert 2 * F['X'] == F['MS'] and 1 << PS_MS == 64, 'mean square of 64 Q7.8 values is Q.16'
assert (SH_XN, SH_U, PS_HDA, PS_DTBU, PS_HC, SH_Y, SH_SZ, SH_G) == (12, 19, 15, 4, 11, 1, 15, 13)
assert F['BU'] == F['B'] + F['U'] and F['P'] == F['DT'] + PF['A2']
