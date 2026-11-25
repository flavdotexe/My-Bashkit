#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
# Logs can contain sensitive credentials; never commit them.
sudo docker compose logs --tail 100 -f cowrie
