#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
sudo docker compose ps -a
sudo docker inspect cowrie --format 'Status={{.State.Status}} Restarts={{.RestartCount}} User={{.Config.User}} ReadOnly={{.HostConfig.ReadonlyRootfs}} Privileged={{.HostConfig.Privileged}}'
sudo nft list table inet honeypot
