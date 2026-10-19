#!/usr/bin/env bash
# Start any flow command detached from the ssh session (server), log to build/logs/<log>:
#   src_gan_tsmc65/syn/start.sh <log> <command> [args ...]
#   e.g. syn/start.sh w16.log syn/run_syn.sh exact --width 16 --period 2.4 --signoff --sta-period 2.5
# Prints the PID (kill by PID only) and the log path. Relative commands are taken from src_gan_tsmc65/.
set -u
[ $# -ge 2 ] || { sed -n '2,5p' "$0"; exit 2; }
G=$(cd "$(dirname "$0")/.." && pwd)
L=$G/build/logs/$1; shift
mkdir -p "$(dirname "$L")"
cd "$G"
setsid nohup "$@" > "$L" 2>&1 < /dev/null &
echo "started $! log $L"
