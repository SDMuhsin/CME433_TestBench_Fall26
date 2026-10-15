#!/usr/bin/env bash
# Builds the timing-check-capable simulator for the SDF GLS: Tachyon Open Source CVC (cvc64),
# pinned to cambridgehackers/open-src-cvc 1c5e043 (OSS_CVC_7.00b), into src/flow/sdf_gls/tools/.cvc
# (git-ignored).  Icarus cannot be used: it parses $setuphold/$width/$recrem but ignores them
# ("Timing checks are not supported"), so a "0 violations" result from it would mean nothing.
# cvc_sdf.patch fixes two SDF reader bugs (src/v_sdf.c) that silently corrupt timing checks:
#  1. rd_port_tchk() dropped the edge of a TIMINGCHECK port "(posedge D)", so SETUP/HOLD/WIDTH for
#     posedge and negedge annotated BOTH Verilog checks and the last value in the SDF won;
#  2. sdf_collect_num() applied a leading '-' only to integers: the negative HOLD limit -0.066 was
#     annotated as +0.066 (false hold violations).  Negative limits now reach the annotator, which
#     clamps them to 0 like other simulators without negative-timing-check support (conservative).
# Needs git, gcc, make, zlib headers (the CVC compiler also calls gcc/as at elaboration time).
# Prints the cvc64 path.  FRESH=1 rebuilds from scratch.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DIR=$HERE/.cvc
REPO=https://github.com/cambridgehackers/open-src-cvc.git
REV=1c5e043ec33ef6f1fdbf38565501c944893a83cf
BIN=$DIR/build64/cvc64
[ -n "${FRESH:-}" ] && rm -rf "$DIR"
if [ ! -x "$BIN" ]; then
    if [ ! -d "$DIR/.git" ]; then git clone -q "$REPO" "$DIR"; fi
    git -C "$DIR" checkout -q "$REV"
    git -C "$DIR" apply "$HERE/cvc_sdf.patch"
    make -C "$DIR/src" -j"$(nproc)" cvc64 >"$DIR/build.log" 2>&1 || true   # first pass races on hexasm
    make -C "$DIR/src" -j1 cvc64 >>"$DIR/build.log" 2>&1
fi
[ "$(git -C "$DIR" rev-parse HEAD)" = "$REV" ] || { echo "cvc checkout is not $REV" >&2; exit 1; }
git -C "$DIR" diff | cmp -s - "$HERE/cvc_sdf.patch" || { echo "cvc tree differs from $REV + cvc_sdf.patch (FRESH=1)" >&2; exit 1; }
case "$(cd "$DIR" && "$BIN" 2>&1 || true)" in *OSS_CVC_7.00b*) ;; *) echo "cvc64 does not run" >&2; exit 1 ;; esac
echo "$BIN"
