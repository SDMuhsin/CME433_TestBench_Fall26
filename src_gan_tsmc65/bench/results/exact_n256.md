# gan65_chip benchmark: variant `exact`, 256 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 256/256 |
| pixels equal to golden | 200704/200704 |
| PSNR vs golden (all pixels) | inf dB |
| PSNR vs golden, worst / median image | inf / inf dB |
| MAE / max abs error | 0.000 / 0 grey levels |
| label agreement RTL vs golden | 256/256 (100.0 %) |
| mean classifier confidence RTL / golden | 0.814 / 0.814 |
| PSNR / MAE vs float generator | 35.32 dB / 1.934 |
| label agreement RTL vs float generator | 250/256 (97.7 %) |

Golden label histogram: T-shirt/top 14, Trouser 27, Pullover 13, Dress 36, Coat 25, Sandal 18, Shirt 50, Sneaker 27, Bag 21, Ankle boot 25

chip simulation: 2346721 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 27 s wall on 44 jobs
