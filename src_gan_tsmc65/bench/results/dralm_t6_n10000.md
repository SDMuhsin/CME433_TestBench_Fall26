# gan65_chip benchmark: variant `dralm_t6`, 10000 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 0/10000 |
| pixels equal to golden | 3596936/7840000 |
| PSNR vs golden (all pixels) | 26.02 dB |
| PSNR vs golden, worst / median image | 13.98 / 27.10 dB |
| MAE / max abs error | 6.398 / 230 grey levels |
| label agreement RTL vs golden | 9269/10000 (92.7 %) |
| mean classifier confidence RTL / golden | 0.830 / 0.828 |
| RTL vs Python emulation of the variant | 10000/10000 images bit-exact |

Golden label histogram: T-shirt/top 623, Trouser 1062, Pullover 310, Dress 1072, Coat 1022, Sandal 862, Shirt 2113, Sneaker 1003, Bag 969, Ankle boot 964

chip simulation: 2346721 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 618 s wall on 44 jobs
