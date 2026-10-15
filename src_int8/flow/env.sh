# Source me (bash), from anywhere:  source src_int8/flow/env.sh
# Puts the LibreLane 3.0.14 nix devshell on PATH (librelane, openroad, yosys, magic, netgen,
# klayout 0.30.7 + python3 with klayout.db, sta, iverilog, verilator) and points PDK_ROOT at the
# gf180mcu open_pdks 7b70722e PDK with the AS 3V3 library merged in.
# Machine prerequisites (not in the repo): nix, the devshell gc-root /opt/librelane/devshell-3.0.14
# (re-dump with `nix print-dev-env /opt/librelane/devshell-3.0.14 > /opt/librelane/devshell-3.0.14.sh`)
# and the PDK at /root/.ciel-chipathon (override with LIBRELANE_DEVSHELL / PDK_ROOT before sourcing).
_MQ_FLOW=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# 1) nix daemon (no systemd in the container: start determinate-nixd by hand if needed)
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
if ! nix store ping >/dev/null 2>&1; then
  nohup /usr/local/bin/determinate-nixd daemon >/var/log/determinate-nixd.log 2>&1 &
  for _i in $(seq 30); do nix store ping >/dev/null 2>&1 && break; sleep 1; done
fi
# 2) LibreLane 3.0.14 devshell
source "${LIBRELANE_DEVSHELL:-/opt/librelane/devshell-3.0.14.sh}" >/dev/null 2>&1
# 3) PDK
export PDK_ROOT=${PDK_ROOT:-/root/.ciel-chipathon}
export PDK=gf180mcuD
# 4) shims: librelane adds --pdk-root/--manual-pdk; openroad-librelane -> openroad
export PATH=$_MQ_FLOW/shims:$PATH
unset _MQ_FLOW _i
