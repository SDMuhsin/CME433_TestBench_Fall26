"""On-chip FP16 word memory map (spec section 6). SRAM = pairs of 256x8 macros (hi/lo byte)."""
WORDS_PER_PAIR = 256
TEMP_WORDS = 8     # scalar temporaries: ms, r, dt, dtu, z, silu(z), y, spare


def memory_map(cfg):
    """Ordered (name, base word, words) regions; LOGITS aliases X + U (dead at logits time)."""
    E, N, D = cfg['d_inner'], cfg['d_state'], cfg['d_model']
    regions, base = [], 0
    for name, size in ([(f'H{l}', E * N) for l in range(cfg['n_layer'])]
                       + [(f'CONV{l}', E) for l in range(cfg['n_layer'])]
                       + [('XN', D), ('X', D), ('U', E), ('DBC', cfg['dt_rank'] + 2 * N),
                          ('TMP', TEMP_WORDS)]):
        regions.append((name, base, size))
        base += size
    x_base = dict((n, b) for n, b, _ in regions)['X']
    assert D + E >= cfg['vocab'], 'X + U must hold the logits'
    regions.append(('LOGITS', x_base, cfg['vocab']))
    return regions


def sram_summary(cfg):
    """-> dict(state_bytes, act_bytes, total_bytes, macro_pairs, macros)."""
    regions = memory_map(cfg)
    state = sum(s for n, _, s in regions if n.startswith(('H', 'CONV')))
    total = max(b + s for _, b, s in regions)
    pairs = -(-total // WORDS_PER_PAIR)
    return dict(state_bytes=2 * state, act_bytes=2 * (total - state), total_bytes=2 * total,
                macro_pairs=pairs, macros=2 * pairs)
