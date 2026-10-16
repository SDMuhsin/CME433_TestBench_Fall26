# Benchmark: mq_mul8 = `example_trunc4`

RTL BPB 1.8333 +- 0.0174 (95 % CI 1.8003..1.8675), PPL 3.5635 per byte, 90,112 bytes in 88 crops

cycles START->done [450412], TB errors 0

wall 15.6 min on 44 workers

Python golden (exact multiplier) on the same bytes: BPB 1.3926; RTL - golden +0.44075 +- 0.00466; tokens with any logit mismatch 90,112 (NOT bit-exact)

Python emulator (golden + this mq_mul8's table) on the same bytes: BPB 1.8333; tokens with any logit mismatch vs RTL 0 (bit-exact)

vs baseline build/bench/runs/exact_c88x1024: dBPB +0.44075 +- 0.00466 (paired, 95 % CI +0.43152..+0.44997)
