"""Spec section 6: on-chip memory map (internal 12-bit addresses) and the host read-back view.

HMEM: 768 x 24-bit entries at 0x000-0x2FF (entry = 4 d + n); BMEM: 512 bytes at 0x400-0x5FF.
Host byte address: bit 12 clear -> HMEM entry addr[11:2], byte addr[1:0] (byte 3 reads 0);
bit 12 set -> BMEM byte addr[8:0].  So the logits (128 x INT16 LE) are at host 0x1040.
"""
HMEM_BASE, HMEM_ENTRIES = 0x000, 768
BMEM_BASE, BMEM_BYTES = 0x400, 512
HOST_BMEM = 0x1000

REGIONS = {  # name: (internal base, size, unit)
    'H0': (0x000, 384, 'entry'), 'H1': (0x180, 384, 'entry'),
    'XN': (0x400, 64, 'byte'), 'X': (0x440, 128, 'byte'), 'U': (0x4C0, 96, 'byte'),
    'DBC': (0x520, 12, 'byte'), 'TMP': (0x52C, 20, 'byte'),
    'CONV0': (0x540, 96, 'byte'), 'CONV1': (0x5A0, 96, 'byte'),
    'LOGITS': (0x440, 256, 'byte'),             # alias of X + U + DBC + TMP
}


def h_entry(layer, d, n, n_state=4):
    """Internal HMEM address of state element (layer, d, n)."""
    return REGIONS[f'H{layer}'][0] + n_state * d + n


def host_address(name, offset=0):
    """Host byte address of byte `offset` of a BMEM region, or of entry `offset` of an H region."""
    base, size, unit = REGIONS[name]
    if unit == 'entry':
        return (base + offset) * 4
    return HOST_BMEM + (base - BMEM_BASE) + offset


HOST_LOGITS = host_address('LOGITS')
assert HOST_LOGITS == 0x1040


def host_to_internal(addr):
    """Host byte address -> ('H', entry, byte) or ('B', byte address)."""
    if addr & 0x1000:
        return ('B', BMEM_BASE + (addr & 0x1FF))
    return ('H', (addr >> 2) & 0x3FF, addr & 3)


def host_image(h_states, bmem):
    """Build the host-visible byte view: h_states [n_layer, 384] INT24 ints, bmem 512 bytes."""
    out = bytearray(HOST_BMEM + BMEM_BYTES)
    entries = [int(v) for layer in h_states for v in layer]
    for e, v in enumerate(entries):
        v &= 0xFFFFFF
        out[4 * e:4 * e + 3] = bytes([v & 0xFF, (v >> 8) & 0xFF, v >> 16])
    out[HOST_BMEM:] = bytes(bmem)
    return bytes(out)


def summary():
    state = sum(s * (3 if u == 'entry' else 1) for n, (b, s, u) in REGIONS.items()
                if n.startswith(('H', 'CONV')))
    return dict(state_bytes=state, hmem_macros=9, bmem_macros=2, macros=11)
