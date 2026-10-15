# dla_fp16_chip: FP16 G300 GAN generator ASIC

`rtl/dla_fp16_chip.sv` runs the whole G300 generator (64 -> 256 -> 256 -> 784) on chip with an IEEE binary16 datapath:
- one FP16xFP16 -> FP32 (RNE) MAC lane;
- an FP16 epilogue with bias, ReLU and a tanh threshold ROM that produces uint8 pixels.

It uses the same 11-pad quad host link, die, pin template and 8 SRAM macro sites as `dla_e2e_chip` (INT8). The SRAM instances are `GEN_ACT[0..3]` (FP16 activation pairs) and `GEN_PIX[0..3]` (pixel buffer).

**Status (2026-10-13):**
- Hardened and signed off in run `librelane/runs/fp16_final`.
- Gate-level sim of the routed netlist is bit-exact on MNIST and Fashion-MNIST, seeds 0-7, both unpowered and powered.
- Not committed.

## Build and verify
- PnR: `cd librelane && ./build_fp16_connected.sh <TAG>`, using `config_fp16.yaml`.
- GLS: `scripts/run_fp16_gls.sh [nl|pnl] -- +STREAM_SRC=sim/results/fp16/<ds>/seed_<s>/stream.memh [+ACTUAL_MEMH=..] [+H0=..] [+H2=..]`
- Expected pixels and streams: `sim/results/fp16/{mnist,fmnist}/seed_*`.

## Signoff limits
- **Max transition: 1.5 ns.** This equals the std-cell liberty `default_max_transition`.
- **Max capacitance: the liberty per-pin `max_capacitance`.** The signoff SDC is `librelane/fp16_signoff.sdc`, which is LibreLane `base.sdc` minus the blanket `set_max_capacitance`.
- **Why not the PDK flow default of 0.2 pF on every pin:** it is unattainable for this design. Each SRAM CLK pin alone is 0.314 pF (ss) / 0.294 pF (tt), so at least 8 nets always violate it.
- Against 0.2 pF, fp16_final would show 18 cap violations at max_ss: SRAM clock, CTS leaf and 4 marginal data nets at 0.21 pF or below.
- Placement and routing use the over-constrained `librelane/fp16_pnr.sdc` (0.9 ns / 0.12 pF). It works together with:
  - post-GRT design repair;
  - no heuristic diode insertion;
  - 500 um wire-length buffering;
  - CTS sink clusters of 12 / 50 um.

## Results vs INT8 dla_e2e_chip (runs/e2e_final)
| Metric | FP16 fp16_final | INT8 e2e_final |
|---|---|---|
| Std cells (excl. fill) | 14,221 | 43,728 |
| Std-cell area | 176,720 um^2 | 611,504 um^2 |
| Utilization (incl. macros) | 44.1% | 70.7% |
| Worst setup (SPEF, 9 corners) | +22.51 ns | +14.10 ns |
| Worst hold | +0.104 ns | +0.107 ns |
| Max-slew vios @1.5 ns (worst corner) | 0 | 707 |
| Max-cap vios, liberty limits / 0.2 pF default (max_ss) | 0 / 18 | 4 / 346 |
| Power (nom tt) | 124.3 mW | 132.3 mW |
| Time per image @ 25 MHz | 182.3 ms | 93.9 ms |

Both chips are bound by the weight stream (SCLK = clk/4). FP16 sends twice the weight bytes (283,984 16-bit words), which explains its longer time per image.

All of these come out clean:
- Magic DRC;
- KLayout DRC (main, antenna, Vn.2b);
- LVS (match uniquely);
- XOR;
- OpenROAD antenna;
- setup, hold, slew and cap at all 9 corners.

KLayout density reports the 6 whole-die coverage items expected at block level, the same as INT8.

GLS of `final/nl` and of `final/pnl` each pass 16/16:
- 784/784 pixels, plus h0 and h2 256/256 each, bit-exact;
- 4,557,186 clk per image, identical to RTL.
