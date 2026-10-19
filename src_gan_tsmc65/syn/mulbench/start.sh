#!/usr/bin/env bash
# Start run_all.sh detached on the server, log to build/mulbench/<log>:
#   syn/mulbench/start.sh <log> <width> <jobs> <design> ...
set -u
M=$(cd "$(dirname "$0")" && pwd)
L=$M/../../build/mulbench/$1; shift
mkdir -p "$(dirname "$L")"
nohup "$M/run_all.sh" "$@" > "$L" 2>&1 < /dev/null &
echo "started $! log $L"
