# 16-bit round: post-2020 signed Booth approximate multipliers, consolidated

Three papers reproduced on the standalone multiplier bench at N = 16 (`syn/mulbench/`, same flow
for every row: DC topographical ss at 2.5 ns = 400 MHz and 4.0 ns, tight 1.2 ns for the a -> p
delay and min period, Formality, SDF GLS + PrimePower tt for the uniform and the GAN-like
stimulus, `mul_core` cells only; energy/op = power x 2.5 ns):
- `park_*`: Park, Kung & Lee 2023, approximate radix-4 encoder + AND 4:2 compressor
  (`park_2023_r4.md`); `park_0` is the exact radix-4 / 4:2 twin of the hand-written Booth rows;
- `r256_*`: Zhu et al. 2022, approximate radix-256 digit (`zhu_2022_r256.md`);
- `cls_*`: Wang et al. 2026, CLS classified truncation + CAE / A4T2C band (`wang_2026_cls.md`);
- `tacbm_12`: Aizaz & Khare 2022 truncated Booth with carry compensation, w = 12
  (`aizaz_khare_2022.md`), the closest prior truncation design;
- the earlier signed rows (HAM H9C1, sign-magnitude CDM16, DR-ALM) from `mul16_feasibility.md`,
  `shi_2025_ham.md`, `amirafshar_2023_cdm.md`, `yin_2021_dralm.md`.
A `z` suffix = zero-safe variant (not in the paper): b = 0 (the activation) gives exactly 0.

Error: 1,000,000 uniform random signed pairs (`approx/results/mulbench_w16_error.md`), MRED over
non-zero products, NMED = MED / 2^30, bias = mean(approx - exact); for the cls / tacbm rows the
exhaustive MRED (2^32 pairs) in brackets (MRED of truncated designs is heavy-tailed). Hardware:
`syn/mulbench/results/table_w16.md`, % vs DesignWare `s_exact`.

| Design | MRED | NMED | bias | area @2.5 ns | @4.0 ns | a->p delay | min period | power uniform | power GAN-like | energy/op uniform / GAN (pJ) |
|---|---|---|---|---|---|---|---|---|---|---|
| `s_exact` | 0.000 % | 0.000e+00 | +0 | 2132 | 1892 | 1.056 | 1.472 | 0.880 | 0.788 | 2.200 / 1.969 |
| `park_0` | 0.000 % | 0.000e+00 | +0 | 2944 (+38.1 %) | 2614 (+38.2 %) | 1.335 (+26.4 %) | 1.744 (+18.4 %) | 1.646 (+87.1 %) | 0.853 (+8.3 %) | 4.116 / 2.133 |
| `park_10` | 0.014 % | 4.380e-06 | -4375 | 2297 (+7.8 %) | 1961 (+3.7 %) | 1.158 (+9.6 %) | 1.585 (+7.6 %) | 1.022 (+16.2 %) | 0.524 (-33.4 %) | 2.556 / 1.311 |
| `park_12` | 0.045 % | 6.075e-06 | -4437 | 2069 (-2.9 %) | 1718 (-9.2 %) | 1.142 (+8.1 %) | 1.559 (+5.9 %) | 0.915 (+4.0 %) | 0.478 (-39.4 %) | 2.287 / 1.194 |
| `park_14` | 0.164 % | 1.834e-05 | -1.596e+04 | 1824 (-14.4 %) | 1630 (-13.8 %) | 1.127 (+6.7 %) | 1.557 (+5.7 %) | 0.808 (-8.2 %) | 0.419 (-46.8 %) | 2.020 / 1.048 |
| `park_10z` | 0.015 % | 4.465e-06 | -4573 | 2284 (+7.2 %) | 1982 (+4.8 %) | 1.169 (+10.7 %) | 1.590 (+8.0 %) | 1.022 (+16.1 %) | 0.500 (-36.5 %) | 2.554 / 1.251 |
| `park_14z` | 0.182 % | 2.084e-05 | -1.99e+04 | 1833 (-14.0 %) | 1661 (-12.2 %) | 1.121 (+6.1 %) | 1.546 (+5.0 %) | 0.761 (-13.5 %) | 0.387 (-50.9 %) | 1.902 / 0.967 |
| `r256_8` | 0.182 % | 9.165e-05 | -56.9 | 2043 (-4.1 %) | 1760 (-7.0 %) | 1.190 (+12.7 %) | 1.612 (+9.5 %) | 1.075 (+22.2 %) | 0.614 (-22.1 %) | 2.689 / 1.535 |
| `r256_8z` | 0.182 % | 9.119e-05 | -43.1 | 2052 (-3.7 %) | 1932 (+2.2 %) | 1.220 (+15.5 %) | 1.637 (+11.2 %) | 1.108 (+25.9 %) | 0.559 (-29.1 %) | 2.770 / 1.396 |
| `r256_6z` | 0.044 % | 2.241e-05 | +10.05 | 2515 (+18.0 %) | 2207 (+16.7 %) | 1.301 (+23.2 %) | 1.737 (+18.0 %) | 1.349 (+53.3 %) | 0.699 (-11.3 %) | 3.372 / 1.747 |
| `r256_10z` | 0.759 % | 3.658e-04 | -683.3 | 1648 (-22.7 %) | 1414 (-25.3 %) | 1.093 (+3.5 %) | 1.522 (+3.4 %) | 0.853 (-3.1 %) | 0.429 (-45.6 %) | 2.132 / 1.071 |
| `cls_ct1` | 0.653 % (0.686 %) | 4.993e-05 | +8913 | 2186 (+2.5 %) | 1757 (-7.1 %) | 1.328 (+25.7 %) | 1.745 (+18.5 %) | 0.972 (+10.5 %) | 0.508 (-35.6 %) | 2.430 / 1.269 |
| `cls_ct2` | 1.301 % (1.529 %) | 6.503e-05 | +5.568e+04 | 2159 (+1.3 %) | 1709 (-9.7 %) | 1.330 (+25.9 %) | 1.743 (+18.4 %) | 0.966 (+9.8 %) | 0.562 (-28.7 %) | 2.415 / 1.405 |
| `cls_ft1` | 0.772 % (1.001 %) | 5.026e-05 | -7287 | 1856 (-12.9 %) | 1449 (-23.4 %) | 1.269 (+20.1 %) | 1.679 (+14.0 %) | 0.785 (-10.7 %) | 0.445 (-43.5 %) | 1.964 / 1.112 |
| `cls_ct1z` | 0.653 % (0.686 %) | 4.993e-05 | +8913 | 2218 (+4.1 %) | 1757 (-7.1 %) | 1.325 (+25.5 %) | 1.754 (+19.2 %) | 0.958 (+8.9 %) | 0.509 (-35.4 %) | 2.396 / 1.272 |
| `cls_ft1z` | 0.599 % (0.685 %) | 5.144e-05 | -3.064e+04 | 1873 (-12.1 %) | 1470 (-22.3 %) | 1.238 (+17.2 %) | 1.672 (+13.6 %) | 0.871 (-0.9 %) | 0.461 (-41.5 %) | 2.179 / 1.153 |
| `cls_ct1z6` | 0.155 % (0.161 %) | 1.142e-05 | +1376 | 2504 (+17.5 %) | 2126 (+12.4 %) | 1.328 (+25.7 %) | 1.744 (+18.4 %) | 1.182 (+34.4 %) | 0.621 (-21.2 %) | 2.956 / 1.552 |
| `tacbm_12` | 0.063 % (0.057 %) | 1.105e-05 | -1.186e+04 | 2051 (-3.8 %) | 1701 (-10.1 %) | 1.152 (+9.1 %) | 1.579 (+7.3 %) | 0.901 (+2.4 %) | 0.463 (-41.2 %) | 2.251 / 1.158 |
| `s_h9c1` | 0.687 % | 1.625e-03 | +2969 | 2940 (+37.9 %) | 1688 (-10.8 %) | 1.841 (+74.3 %) | 2.246 (+52.5 %) | 1.718 (+95.2 %) | 1.455 (+84.7 %) | 4.295 / 3.638 |
| `s_h9c1e` | 0.674 % | 1.627e-03 | +2881 | 3778 (+77.2 %) | 1779 (-6.0 %) | 1.980 (+87.4 %) | 2.373 (+61.2 %) | 2.379 (+170.4 %) | 1.891 (+140.0 %) | 5.948 / 4.726 |
| `s_cdmf880` | 3.095 % | 3.781e-03 | -4282 | 3425 (+60.7 %) | 2514 (+32.9 %) | 1.449 (+37.1 %) | 1.858 (+26.2 %) | 1.331 (+51.3 %) | 0.610 (-22.6 %) | 3.327 / 1.524 |
| `s_cdmfbb3` | 3.814 % | 4.149e-03 | +2648 | 3329 (+56.2 %) | 2364 (+24.9 %) | 1.429 (+35.3 %) | 1.855 (+26.0 %) | 1.469 (+67.0 %) | 0.647 (-17.9 %) | 3.674 / 1.617 |
| `s_dralm5` | 3.804 % | 9.221e-03 | +3417 | 765 (-64.1 %) | 647 (-65.8 %) | 1.066 (+0.9 %) | 1.478 (+0.4 %) | 0.265 (-69.9 %) | 0.260 (-67.0 %) | 0.662 / 0.651 |
| `s_dralm6` | 3.031 % | 7.307e-03 | +4942 | 857 (-59.8 %) | 708 (-62.6 %) | 1.108 (+4.9 %) | 1.528 (+3.8 %) | 0.313 (-64.4 %) | 0.290 (-63.2 %) | 0.782 / 0.724 |

Area in um^2, delay / period in ns, power in mW. Formality SUCCEEDED and GLS == model for every
row.

## Reading
- The hand-written signed Booth structure costs +38 % area, +26 % delay and +87 % uniform
  power vs DesignWare (`park_0`); a Booth approximation has to recover that before it saves
  anything. Every Booth row is slower than `s_exact` (+3.5 to +26 % a -> p), all still meet
  400 MHz (min period <= 1.76 ns).
- **`park_14z` is the best Booth design**: -14.0 % area, -13.5 % uniform power / energy,
  -50.9 % GAN-like power, +6.1 % delay at MRED 0.18 %, b = 0 exact. `park_14` is the same
  without the zero fix.
- `r256_10z` saves more area (-22.7 %) but at 4x the error (MRED 0.76 %) and only -3 % uniform
  power; `r256_8(z)` (the paper's AR256) is dominated by `park_14z` at equal MRED.
- The CLS designs recover the overhead only in the ABMFT1 form (`cls_ft1(z)`: -12 to -13 %
  area, -1 to -11 % uniform, -42 to -44 % GAN-like power) at 4-6x the error of `park_14z`
  (MRED 0.68-1.0 %) and +17-20 % delay; ABMCT1 / 2 only save GAN-like power. The paper's
  8-bit error figures are 10x too low (`wang_2026_cls.md` s.3).
- `tacbm_12` is the most accurate approximate row (MRED 0.057 %) with -3.8 % area and -41 %
  GAN-like power, but uniform power +2.4 %.
- The non-Booth signed rows: DR-ALM is by far the cheapest (-60 to -64 % area, -64 to -70 %
  power) at MRED 3-3.8 %; HAM and sign-magnitude CDM16 cost more than DesignWare at 400 MHz.

**Recommendation for the 16-bit chip:** carry `park_14z` (Park 2023, wG = wA = 14, zero-safe
encoder) as the Booth variant; `tacbm_12` if accuracy matters more than area, `s_dralm5` /
`s_dralm6` only if a few-% MRED is acceptable. Not `r256_*` or `cls_*` (dominated).
