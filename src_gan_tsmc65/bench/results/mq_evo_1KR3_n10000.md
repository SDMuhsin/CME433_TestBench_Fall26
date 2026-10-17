# gan65_chip benchmark: variant `mq:evo_1KR3`, 10000 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 0/10000 |
| pixels equal to golden | 29773/7840000 |
| PSNR vs golden (all pixels) | 8.51 dB |
| PSNR vs golden, worst / median image | 3.92 / 8.37 dB |
| MAE / max abs error | 87.493 / 255 grey levels |
| label agreement RTL vs golden | 974/10000 (9.7 %) |
| mean classifier confidence RTL / golden | 0.893 / 0.828 |
| RTL vs Python emulation of the variant | 10000/10000 images bit-exact |

Golden label histogram: T-shirt/top 623, Trouser 1062, Pullover 310, Dress 1072, Coat 1022, Sandal 862, Shirt 2113, Sneaker 1003, Bag 969, Ankle boot 964

chip simulation: 2346721 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 814 s wall on 44 jobs
