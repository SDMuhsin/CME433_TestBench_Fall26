# gan65_chip benchmark: variant `exact`, 16 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 16/16 |
| pixels equal to golden | 12544/12544 |
| PSNR vs golden (all pixels) | inf dB |
| PSNR vs golden, worst / median image | inf / inf dB |
| MAE / max abs error | 0.000 / 0 grey levels |
| label agreement RTL vs golden | 16/16 (100.0 %) |
| mean classifier confidence RTL / golden | 0.846 / 0.846 |

Golden label histogram: T-shirt/top 1, Trouser 1, Dress 3, Coat 1, Sandal 1, Shirt 4, Sneaker 4, Bag 1

chip simulation: 2346721 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 170 s wall on 16 jobs
