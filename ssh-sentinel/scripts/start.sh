#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
# Refuse to start without the expected containment rules.
if ! sudo nft list table inet honeypot >/dev/null 2>&1; then
    sudo nft -c -f firewall/honeypot.nft
    sudo nft -f firewall/honeypot.nft
fi
# Existing rules must be reviewed; do not overwrite a live firewall.
sudo nft list table inet honeypot
read -r -p 'Confirm both bridge drop rules are present [y/N]: ' answer
[[ "$answer" == y || "$answer" == Y ]] || exit 1
sudo docker compose up -d --no-build
