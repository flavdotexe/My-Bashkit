#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for f in secops.sh core/*.sh modules/*.sh; do bash -n "$f"; done
source core/ui.sh
valid_port 22
! valid_port 0
! valid_port 65536
valid_ip 192.168.1.0/24
! valid_ip 999.999.1.1
echo 'Syntax and validation smoke tests passed'
