#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
sudo docker inspect cowrie --format 'User={{.Config.User}} Privileged={{.HostConfig.Privileged}} ReadOnly={{.HostConfig.ReadonlyRootfs}} CapDrop={{.HostConfig.CapDrop}} SecurityOpt={{.HostConfig.SecurityOpt}}'
sudo nft list table inet honeypot
# Test only addresses you own or are authorized to test.
if (($#)); then
sudo docker exec -i cowrie /cowrie/cowrie-env/bin/python - "$@" <<'PY'
import socket, sys
failed = False
for target in sys.argv[1:]:
    host, port = target.rsplit(':', 1)
    try:
        with socket.create_connection((host, int(port)), timeout=3):
            print(f'FAIL: {target} reachable')
            failed = True
    except OSError as exc:
        print(f'UNREACHABLE: {target}: {exc}')
sys.exit(int(failed))
PY
fi
sudo nft list table inet honeypot
