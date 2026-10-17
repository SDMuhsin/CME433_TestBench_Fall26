#!/usr/bin/env bash
# Exchange the non-code files with the server (host alias and tree from site/site.sh,
# git-ignored; template site/site.example.sh). Code reaches the server through git.
#   src_gan_tsmc65/sync.sh pull   summary text files ($GAN65/build/summary) to results/
#   src_gan_tsmc65/sync.sh site   site/ files (git-ignored) to the server clone
# Libraries, netlists, SPEF, SAIF and full reports stay on the server.
set -eu
G=$(cd "$(dirname "$0")" && pwd)
[ -f "$G/site/site.sh" ] || { echo "missing $G/site/site.sh (see site/README.md)"; exit 1; }
. "$G/site/site.sh"
RS="rsync -rltp -e ssh"
case "${1:-}" in
pull)
    mkdir -p "$G/results"
    $RS "$GAN65_HOST:$GAN65_REMOTE/build/summary/" "$G/results/"
    ls "$G/results"
    ;;
site)
    $RS --exclude '*.example.*' --exclude README.md --exclude .gitignore "$G/site/" "$GAN65_HOST:$GAN65_REMOTE/site/"
    echo "site files copied"
    ;;
*)  echo "usage: $0 pull|site"; exit 1 ;;
esac
