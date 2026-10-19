# gan65_chip benchmark: variant `mb:park_14z`, 16-bit datapath, 16 Fashion-MNIST latents

| metric | value |
|---|---|
| bit-exact images vs golden | 0/16 |
| pixels equal to golden | 7661/12544 |
| PSNR vs golden (all pixels) | 45.91 dB |
| PSNR vs golden, worst / median image | 41.62 / 46.20 dB |
| MAE / max abs error | 0.726 / 6 grey levels |
| label agreement RTL vs golden | 16/16 (100.0 %) |
| mean classifier confidence RTL / golden | 0.855 / 0.855 |
| PSNR / MAE vs float generator | 45.13 dB / 0.766 |
| label agreement RTL vs float generator | 16/16 (100.0 %) |
| RTL vs Python emulation of the variant | 16/16 images bit-exact |

Golden label histogram: T-shirt/top 1, Trouser 1, Dress 3, Coat 1, Sandal 1, Shirt 4, Sneaker 4, Bag 1

chip simulation: 4606025 clk per image (START, stream at SCLK = clk/4, readback at clk/8); 164 s wall on 4 jobs
