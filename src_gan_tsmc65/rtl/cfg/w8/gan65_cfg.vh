// gan65 datapath width: 8-bit chip (INT8 Fashion-MNIST generator, model/fmnist).
// The width is chosen by the include path: rtl/cfg/w8 or rtl/cfg/w16 (docs/width16.md); this
// directory also holds the matching CSR reset constants (g300_quant_params.vh).
`define GAN65_DATA_W 8
