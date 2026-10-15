# Extra environment for PrimeTime / PrimePower / Formality / ICC2 (2019 releases ship an old libz).
source $MQ65/syn/common/env.csh
setenv LD_PRELOAD /usr/lib64/libz.so.1
