# gan65_chip benchmark: variant `ham_ae`, 256 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 0/256 |
| pixels equal to golden | 110271/200704 |
| PSNR vs golden (all pixels) | 38.24 dB |
| PSNR vs golden, worst / median image | 27.51 / 39.74 dB |
| MAE / max abs error | 1.432 / 64 grey levels |
| label agreement RTL vs golden | 249/256 (97.3 %) |
| mean classifier confidence RTL / golden | 0.813 / 0.814 |
| RTL vs Python emulation of the variant | 256/256 images bit-exact |

Golden label histogram: T-shirt/top 14, Trouser 27, Pullover 13, Dress 36, Coat 25, Sandal 18, Shirt 50, Sneaker 27, Bag 21, Ankle boot 25

chip simulation: 2346721 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 19 s wall on 44 jobs
