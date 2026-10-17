# Site configuration (process kit and server)

The gan65 synthesis / LEC / STA / GLS scripts contain no kit names, paths or cell names.
They share the kit configuration of the INT8 65 nm flow: `src_int8_tsmc65/site/`
(`site.tcl` libraries, RC files and reference cells, `site.csh` tool setup; see
`src_int8_tsmc65/site/README.md`). Set that up first.

This directory only adds what is specific to `gan65_chip`. Only the templates are tracked.

| Template (tracked) | Copy to (ignored) | Read by | Holds |
|---|---|---|---|
| `gan65_icg_site.example.v` | `gan65_icg_site.v` | synthesis / LEC (`syn/common/rtl.tcl`) | `gan65_icg` mapped to the library clock-gating cell |
| `site.example.sh` | `site.sh` | `sync.sh` | ssh host alias and remote tree |

    cd src_gan_tsmc65/site
    cp gan65_icg_site.example.v gan65_icg_site.v
    cp site.example.sh site.sh

then replace every `<PLACEHOLDER>`, and copy the files to the server with `sync.sh site`.
Without `gan65_icg_site.v` the behavioural clock gate `rtl/mem/gan65_icg.v` is synthesised
(DC then builds each word gate from a latch and an AND gate).

The RTL simulations (`bench/`) never read these files.
