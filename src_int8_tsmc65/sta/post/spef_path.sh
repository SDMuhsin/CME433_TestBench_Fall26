#!/usr/bin/env bash
# Path of the SPEF for a routed block:  sta/post/spef_path.sh <pnr_tag> <rc>
#   rc: star (StarRC, typical corner) | icc2_<corner> (ICC2 extraction, TLU+ of ss / tt / ff)
B=$(cd "$(dirname "$0")/../../build" && pwd)
case "$2" in
star)   echo "$B/ext/$1/mq_chip.star_typ.spef" ;;
icc2_*) ls "$B/pnr/$1/out/"mq_chip*"${2#icc2_}"*.spef 2>/dev/null | head -1 ;;
*)      echo "unknown rc $2" >&2; exit 1 ;;
esac
