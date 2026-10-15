# Site configuration (process kit and server)

The 65 nm flow scripts contain no kit names, paths or cell names. Everything specific to the
process kit, the tool installation and the server is read from git-ignored files in this
directory. Only the templates are tracked.

| Template (tracked) | Copy to (ignored) | Read by | Holds |
|---|---|---|---|
| `site.example.tcl` | `site.tcl` | `syn/common/libs.tcl` | library dir and per-corner .db names, operating conditions, techfile, RC tech files, reference cells (NAND2, ICG, drivers, load) |
| `site.example.csh` | `site.csh` | `syn/common/env.csh` | tool setup scripts, `MQ65_KIT` (kit root) |
| `site.example.sh` | `site.sh` | `sync.sh` | ssh host alias and remote tree |
| `mq65_icg_site.example.v` | `mq65_icg_site.v` | synthesis / LEC (via `::MQ65_ICG_RTL`) | `mq65_icg` mapped to the library clock-gating cell |

To set up a new site:

    cd src_int8_tsmc65/site
    for f in site.tcl site.csh site.sh; do cp site.example.${f#site.} $f; done
    cp mq65_icg_site.example.v mq65_icg_site.v

then replace every `<PLACEHOLDER>` with the values from your kit. `sync.sh push` copies this
directory to the server together with the flow scripts.

The open-source simulations (`sim/unit`, `sim/chip`) never read these files: they use the
behavioural clock gate in `rtl_mem/mq65_icg.v`.
