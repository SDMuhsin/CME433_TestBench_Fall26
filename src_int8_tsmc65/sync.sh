#!/usr/bin/env bash
# Fetch flow summaries from the server (host alias and tree from site/site.sh, git-ignored;
# template site/site.example.sh). Code reaches the server through git (push here, pull there).
#   src_int8_tsmc65/sync.sh pull   summary text files only ($MQ65/build/summary) to results/
#   src_int8_tsmc65/sync.sh site   site/ config files (git-ignored) to the server's clone
# Only scripts and summary text cross the link; libraries, netlists, SDF, SAIF and full
# reports stay on the server.
set -eu
T65=$(cd "$(dirname "$0")" && pwd)
[ -f "$T65/site/site.sh" ] || { echo "missing $T65/site/site.sh (see site/README.md)"; exit 1; }
. "$T65/site/site.sh"
RS="rsync -rltp -e ssh"
case "${1:-}" in
pull)
    mkdir -p "$T65/results"
    $RS "$MQ65_HOST:$MQ65_REMOTE/build/summary/" "$T65/results/"
    ls "$T65/results"
    ;;
site)
    $RS --exclude '*.example.*' --exclude README.md "$T65/site/" "$MQ65_HOST:$MQ65_REMOTE/site/"
    echo "site config copied"
    ;;
*)  echo "usage: $0 pull|site"; exit 1 ;;
esac
