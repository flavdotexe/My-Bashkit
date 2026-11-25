#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
sudo docker compose stop cowrie
# Keep firewall and persistent volumes intact.
