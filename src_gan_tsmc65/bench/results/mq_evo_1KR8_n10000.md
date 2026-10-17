# gan65_chip benchmark: variant `mq:evo_1KR8`, 10000 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 0/10000 |
| pixels equal to golden | 3037382/7840000 |
| PSNR vs golden (all pixels) | 21.41 dB |
| PSNR vs golden, worst / median image | 12.40 / 22.05 dB |
| MAE / max abs error | 12.331 / 242 grey levels |
| label agreement RTL vs golden | 8761/10000 (87.6 %) |
| mean classifier confidence RTL / golden | 0.811 / 0.828 |
| RTL vs Python emulation of the variant | 10000/10000 images bit-exact |

Golden label histogram: T-shirt/top 623, Trouser 1062, Pullover 310, Dress 1072, Coat 1022, Sandal 862, Shirt 2113, Sneaker 1003, Bag 969, Ankle boot 964

chip simulation: 2346721 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 2296 s wall on 44 jobs
