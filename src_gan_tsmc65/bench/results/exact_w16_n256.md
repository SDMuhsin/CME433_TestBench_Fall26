# gan65_chip benchmark: variant `exact`, 16-bit datapath, 256 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 256/256 |
| pixels equal to golden | 200704/200704 |
| PSNR vs golden (all pixels) | inf dB |
| PSNR vs golden, worst / median image | inf / inf dB |
| MAE / max abs error | 0.000 / 0 grey levels |
| label agreement RTL vs golden | 256/256 (100.0 %) |
| mean classifier confidence RTL / golden | 0.809 / 0.809 |
| PSNR / MAE vs float generator | 46.79 dB / 0.081 |
| label agreement RTL vs float generator | 256/256 (100.0 %) |

Golden label histogram: T-shirt/top 14, Trouser 26, Pullover 12, Dress 36, Coat 26, Sandal 17, Shirt 50, Sneaker 28, Bag 22, Ankle boot 25

chip simulation: 4606025 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 57 s wall on 44 jobs
