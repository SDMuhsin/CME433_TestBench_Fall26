# Datapath RTL units (Phase 2a)

Bit-exact implementations of the arithmetic contract in `spec.md` sections 3-4. The chip (`arch.md`) instantiates `mb_lane` and `mb_nlu` and nothing else from here.

- Sources: `src/rtl/units.f` (paths relative to `src/rtl`, include dir `src/rtl/nonlin`). Verilog-2001, one clock, active-low async reset on valid bits only.
- Unit tests: `src/tb/run_unit.sh` (iverilog). Synthesis check: `src/syn/synth_units.sh` (yosys, gf180mcu_as_sc_mcu7t3v3 tt).
- The ROM is generated: `python3 -m src.scripts.gen_nlu_rom` writes `mb_nlu_rom.v` and `mb_nlu_defs.vh` from `src/golden/arith/nlu.py`. `run_unit.sh` fails if they are stale.

## Units

| File | Module | Kind | Function |
|---|---|---|---|
| `fpu/mb_fp16_mul.v` | `mb_fp16_mul` | comb | FP16 x FP16 -> exact FP32 product. Copied from `rtl/fp16_mul.v` |
| `fpu/mb_fp32_add.v` | `mb_fp32_add_align`, `_norm`, `_rne` | comb | FP32 add with RNE, split in two halves. Copied from `rtl/fp32_add_rne.v` |
| `fpu/mb_fp16_to_fp32.v` | `mb_fp16_to_fp32` | comb | Exact init conversion (exp 0 -> +0, exp 31 -> +-65504) |
| `fpu/mb_fp32_wb.v` | `mb_fp32_wb` | comb | `wb(acc, s)`: exact 2^s, FTZ below 2^-14, RNE, saturate, never -0 |
| `lane/mb_lane.v` | `mb_lane` | 3-stage pipe | MAC lane plus writeback |
| `nonlin/mb_nlu_addr.v` | `mb_nlu_addr` | comb | x, fn -> ROM index, fraction q, scale, softplus bypass |
| `nonlin/mb_nlu_frac.v` | `mb_nlu_frac` | comb | q / 2^11 -> exact FP16 |
| `nonlin/mb_nlu_rom.v` | `mb_nlu_rom` | comb | 340 x 16 b table (generated) |
| `nonlin/mb_nlu.v` | `mb_nlu` | 1 register stage | Shared nonlinear unit; feeds operands to `mb_lane` |

## mb_lane

Ports:
- `issue`, `first`, `a`, `b`, `init`: one lane step.
- `scale` (signed 8 b): applies to `y`.
- Outputs: `can_issue`, `idle`, `done`, `acc` (FP32), `y` (FP16).
- `clear` drops steps that are in flight.

```
step: acc <- RNE32(base + a*b)    base = first ? fp32(init) : acc    (init 0 -> +0)
y   = wb(acc, scale)               combinational from acc; hold `scale` while reading y
```

Timing:
- **Latency.** A step issued in cycle c has `acc`/`y` valid and `done` = 1 in cycle c+3.
- **Issue interval.** Issues must be at least 2 cycles apart (`can_issue = !issue`), because a dependent step needs the previous `acc`.
- **Throughput.** 1 step per 2 cycles. That is 8 steps per 16-clock stream word, so far more than the spec needs.

The spec ops are step sequences ("modes"). Each one is followed by reading `y` once `done` fires for its last step.

| Op | Spec use | Steps |
|---|---|---|
| GEMV row | `gemv(W, x, init)`: in_x, in_z, x_proj, dt, out (init = residual), logits | `first` + init (or 0), then K-1 plain steps |
| RMS sum | `acc = 2^-6 + sum x_i^2`, `ms = wb(acc, -6)` | init 0x2400, K steps, scale -6 |
| MUL | `mul(a, b)`: xn, SiLU, dtu, dt*A', y*SiLU(z) | one `first` step, init 0 |
| MADD2 | scan `H = wb(dA*H + dtu*B)`; conv `wb(cb + w0*prev + w1*xi)` | `first` (init 0, or cb) + 1 step |
| y dot | `wb(C0 H0 + .. + C3 H3 + D u)` | `first` + 4 steps |
| LERP | NLU interpolation | 2 steps with operands from `mb_nlu`; scale = `mb_nlu.scale` |

`a`, `b` and `init` should come from registers or from `mb_nlu` (the S1 multiplier is in their timing path).

## mb_nlu

Function codes are in `mb_nlu_defs.vh`: 0 sigmoid, 1 softplus, 2 exp2, 3 rsqrt.

```
cycle 0      ld=1, fn, x          registers (idx, q, scale, bypass, x)
step=0       a=T[i],   b=1-f      -> lane issue, first=1, init=0
step=1       a=T[i+1], b=f        -> lane issue >= 2 cycles later
result       lane scale = nlu.scale; read nlu.y (= x for softplus x >= 8, else lane y)
```

- Minimum latency from `ld` to `y` is 6 cycles: issues in cycles 1 and 3, `done` in cycle 6.
- Outputs hold until the next `ld`, so the sequencer may load x one cycle before the first issue.
- SiLU(x) is two ops: sigmoid, then MUL(x, sigmoid).
- No Newton step exists anywhere; the spec does not use one.

Address arithmetic is exact fixed point on |x| * 2^16 (floor plus sticky):
- uniform (sigmoid, softplus): floor/ceil to 2^-14;
- exp2: ceil(|x| 2^16), so p = -ceil;
- rsqrt: exponent parity.

See the header of `mb_nlu_addr.v`.

**Hardware detail beyond the spec.** The exp2 scale floor(p) is clamped to -128, which fits the 8-bit scale. This is bit-exact: the interpolated value is at most 2, so any s <= -16 flushes to +0 anyway. The rsqrt scale is in -7..7, RMSNorm uses -6, and everything else uses 0. rsqrt is only defined for x > 0 (as in golden).

## Verification (`src/tb/run_unit.sh`, about 2.5 min)

The vectors come from `src/golden` via `python3 -m src.tb.vectors <dir>` (one generator per unit in `src/tb/vectors/`). All units are bit-exact.

| TB | Vectors | Coverage |
|---|---|---|
| `tb_fp16_to_fp32` | 65,536 | exhaustive, including non-canonical codes (checked against `canon16`) |
| `tb_fpu_mac` | 300,064 | product and RNE32 sum: random codes over all exponents and realistic values; exact and near cancellation, exponent gaps, RNE ties, zeros, edge operands |
| `tb_fp32_wb` | 547,566 | every FP16 value as acc, ties of both parities, 2^-14 / 65504 / 65520 boundaries, random scaled exponents, scales -128..127 |
| `tb_lane` | 914,400 steps | GEMV K = 1..128 with and without init, MUL, scan/conv MADD2; issued at max rate plus random gaps; checks acc and y on every step |
| `tb_nlu` | 215,043 | exhaustive: every canonical FP16 input for all 4 functions (rsqrt: x > 0), through `mb_nlu` + `mb_lane`; also checks idx, q, scale and bypass |

## Synthesis (`src/syn/synth_units.sh`, yosys + abc, gf180mcu_as_sc_mcu7t3v3 tt)

No latches, and `check -assert` is clean. The script prints cells, flops and area per unit:

| Unit | Cells | Flops | Area um^2 |
|---|---|---|---|
| mb_lane (mul + add + init + wb) | 2,180 | 145 | 52,520 |
| mb_nlu (addr + ROM + frac) | 1,294 | 46 | 28,160 |
| of which mb_nlu_rom | 578 | 0 | 12,100 |

## Notes for integration

- **Critical path.** The likely critical path is `mb_nlu` idx_r -> ROM (+1 adder, 340-way decode) -> `mb_fp16_mul` -> lane `p_r`. A pre-layout OpenSTA check of `mb_nlu` + `mb_lane` (yosys/abc netlist, ss_125C_3v00, no wire load) gives a worst reg-to-reg path of 17.1 ns, i.e. 22.8 ns of slack at 40 ns. If post-layout timing is short, register the ROM output: that costs one more cycle per NLU step.
- **Accumulator range.** The lane assumes the spec's operand domain: canonical FP16 inputs and |acc| < 2^40, which holds for K <= 128. There is no FP32 overflow handling.
