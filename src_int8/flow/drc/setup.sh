#!/usr/bin/env bash
# Create/verify the KLayout DRC python env used by src_int8/flow/drc/kdrc.sh.
#   src_int8/flow/drc/setup.sh            idempotent; prints the env's python path on the last line
#   FRESH=1 src_int8/flow/drc/setup.sh    delete and rebuild the venv
# Needs the LibreLane nix shell (source src_int8/flow/env.sh): klayout + python3 with klayout.db on PATH,
# PDK_ROOT = open_pdks 7b70722e gf180mcu. The venv lives in src_int8/flow/drc/.venv (git-ignored).
# Pins: KLayout 0.30.7 (binary and python module), docopt 0.6.2 (hashed), deck files (deck.sha256).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VENV=$HERE/.venv
KLAYOUT_VER=0.30.7
PDK_SOURCES="open_pdks 7b70722e33c03fcb5dabcf4d479fb0822d9251c9"
die() { echo "drc/setup.sh: $*" >&2; exit 1; }

command -v klayout >/dev/null || die "klayout not on PATH (source src_int8/flow/env.sh)"
kv=$(klayout -b -v | head -1 | awk '{print $NF}')
[ "$kv" = "$KLAYOUT_VER" ] || die "klayout binary $kv, need $KLAYOUT_VER"

: "${PDK_ROOT:?PDK_ROOT unset (source src_int8/flow/env.sh)}"
src=$(head -1 "$PDK_ROOT/gf180mcuD/SOURCES" 2>/dev/null || true)
[ "$src" = "$PDK_SOURCES" ] || die "PDK is '$src', need '$PDK_SOURCES'"
DECK=$PDK_ROOT/gf180mcuD/libs.tech/klayout/tech/drc
(cd "$DECK" && grep -v '^#' "$HERE/deck.sha256" | sha256sum -c --quiet) || die "DRC deck differs from deck.sha256"

[ -n "${FRESH:-}" ] && rm -rf "$VENV"
if [ ! -x "$VENV/bin/python" ]; then
  BASE=$(command -v python3)
  "$BASE" -c 'import klayout.db' 2>/dev/null || die "$BASE cannot import klayout.db"
  "$BASE" -m venv --system-site-packages "$VENV"
  "$VENV/bin/python" -m pip install -q --disable-pip-version-check --require-hashes -r "$HERE/build-requirements.txt"
  "$VENV/bin/python" -m pip install -q --disable-pip-version-check --require-hashes --no-build-isolation -r "$HERE/requirements.txt"
fi

PY=$VENV/bin/python
"$PY" - "$KLAYOUT_VER" <<'PYEOF' || die "venv check failed (FRESH=1 to rebuild)"
import sys, importlib.metadata as md, klayout.db, docopt
want = sys.argv[1]
assert klayout.db.__version__ == want, f"klayout.db {klayout.db.__version__} != {want}"
assert md.version("docopt") == "0.6.2", f"docopt {md.version('docopt')}"
PYEOF
echo "$PY"
