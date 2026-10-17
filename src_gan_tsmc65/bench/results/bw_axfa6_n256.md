# gan65_chip benchmark: variant `bw_axfa6`, 256 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 0/256 |
| pixels equal to golden | 84715/200704 |
| PSNR vs golden (all pixels) | 21.56 dB |
| PSNR vs golden, worst / median image | 16.09 / 21.96 dB |
| MAE / max abs error | 12.270 / 183 grey levels |
| label agreement RTL vs golden | 236/256 (92.2 %) |
| mean classifier confidence RTL / golden | 0.799 / 0.814 |
| RTL vs Python emulation of the variant | 256/256 images bit-exact |

Golden label histogram: T-shirt/top 14, Trouser 27, Pullover 13, Dress 36, Coat 25, Sandal 18, Shirt 50, Sneaker 27, Bag 21, Ankle boot 25

chip simulation: 2346721 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 62 s wall on 44 jobs
