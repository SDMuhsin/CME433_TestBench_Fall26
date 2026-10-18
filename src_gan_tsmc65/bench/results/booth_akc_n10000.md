# gan65_chip benchmark: variant `booth_akc`, 10000 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 0/10000 |
| pixels equal to golden | 2337222/7840000 |
| PSNR vs golden (all pixels) | 11.46 dB |
| PSNR vs golden, worst / median image | 5.08 / 11.91 dB |
| MAE / max abs error | 42.612 / 255 grey levels |
| label agreement RTL vs golden | 6676/10000 (66.8 %) |
| mean classifier confidence RTL / golden | 0.745 / 0.828 |
| RTL vs Python emulation of the variant | 10000/10000 images bit-exact |

Golden label histogram: T-shirt/top 623, Trouser 1062, Pullover 310, Dress 1072, Coat 1022, Sandal 862, Shirt 2113, Sneaker 1003, Bag 969, Ankle boot 964

chip simulation: 2346721 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 1630 s wall on 44 jobs
