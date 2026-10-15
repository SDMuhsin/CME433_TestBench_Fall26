#!/usr/bin/env bash
# Sync the 65 nm flow with the server (host alias and tree from site/site.sh, git-ignored;
# template site/site.example.sh).
#   src_int8_tsmc65/sync.sh push   RTL (src_int8/rtl unchanged + rtl_mem), flow scripts, chip TB
#                                  and golden vectors (from sim/build/chip/vec) to ~/mq65
#   src_int8_tsmc65/sync.sh pull   summary text files only (~/mq65/out/summary) to results/
# Only scripts and summary text cross the link; libraries, netlists, SDF, SAIF and full
# reports stay on the server.
set -eu
T65=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$T65")
[ -f "$T65/site/site.sh" ] || { echo "missing $T65/site/site.sh (see site/README.md)"; exit 1; }
. "$T65/site/site.sh"
H=$MQ65_HOST
R=${MQ65_REMOTE:-mq65}
RS="rsync -rltp -e ssh"
case "${1:-}" in
push)
    ssh -o BatchMode=yes $H "mkdir -p $R/rtl $R/tb $R/vec $R/site"
    $RS --delete --exclude '*.memh.bak' "$ROOT/src_int8/rtl/" $H:$R/rtl/core/
    $RS --delete "$T65/rtl_mem/" $H:$R/rtl/mem/
    for d in syn sta power sim lec site; do $RS --exclude build "$T65/$d/" $H:$R/$d/; done
    $RS "$T65/syn/common/env.csh" $H:$R/env.csh
    $RS "$ROOT/src_int8/tb/chip/tb_mq_chip.sv" "$ROOT/src_int8/tb/common/" $H:$R/tb/
    [ -d "$T65/sim/build/chip/vec/chip" ] && $RS "$T65/sim/build/chip/vec/chip/" $H:$R/vec/chip/
    echo "pushed"
    ;;
pull)
    mkdir -p "$T65/results"
    $RS "$H:$R/out/summary/" "$T65/results/"
    ls "$T65/results"
    ;;
*)  echo "usage: $0 push|pull"; exit 1 ;;
esac
