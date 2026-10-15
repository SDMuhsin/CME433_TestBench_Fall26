#!/usr/bin/env bash
# Fill chain of a finished run: fill.sh (fill + checks + KLayout DRC of the filled GDS) ->
# fill_sta.sh (RCX + 9-corner STA with grounded fill -> runs/<TAG>_fillrc) ->
# fill_signoff.sh (Magic DRC + GDS-extracted LVS on the filled GDS -> runs/<TAG>_fillsignoff).
#   src_int8/flow/fill/fill_all.sh <TAG>      (needs the nix shell: source src_int8/flow/env.sh)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TAG=${1:?usage: fill_all.sh <TAG>}
"$HERE/fill.sh" "$TAG"
"$HERE/fill_sta.sh" "$TAG"
"$HERE/fill_signoff.sh" "$TAG"
