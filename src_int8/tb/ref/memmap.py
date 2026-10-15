"""Internal memory map of mq_chip (spec.md section 6) and the host byte view."""
CFG = dict(vocab=128, d_model=64, n_layer=2, d_inner=96, d_state=4, dt_rank=4, conv=2)

HMEM_ENTRIES = 768                   # 3 triples x 256 rows, INT24
BMEM_BASE, BMEM_BYTES = 0x400, 512

# name -> (internal base address, size in entries (HMEM) or bytes (BMEM))
MAP = {
    'H0': (0x000, 384), 'H1': (0x180, 384),
    'XN': (0x400, 64), 'X': (0x440, 128), 'U': (0x4C0, 96), 'DBC': (0x520, 12),
    'TMP': (0x52C, 20), 'CONV0': (0x540, 96), 'CONV1': (0x5A0, 96), 'LOGITS': (0x440, 256),
}
STATE_END = 0x300                    # H* occupy [0, 0x300)
CONV_BASE, CONV_END = 0x540, 0x600   # CONV* occupy [0x540, 0x600)
HOST_LOGITS = 0x1040                 # host byte address of the logits (256 B, INT16 LE)
HOST_BMEM = 0x1000


def is_state(addr):
    return addr < STATE_END or CONV_BASE <= addr < CONV_END


def host_addr(internal, byte=0):
    """Internal address (+ byte of an HMEM entry) -> host byte address."""
    if internal < 0x400:
        return internal * 4 + byte
    return HOST_BMEM | (internal - BMEM_BASE)
