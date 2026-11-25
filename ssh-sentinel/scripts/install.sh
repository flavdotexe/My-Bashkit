#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
# Use a trusted local Cowrie source snapshot; never modify it in place.
source_dir=${1:?Usage: install.sh /path/to/cowrie-source}
[[ -f "$source_dir/pyproject.toml" && -f "$source_dir/requirements.txt" ]]
[[ ! -e upstream ]] || { echo 'upstream already exists; inspect it first' >&2; exit 1; }
mkdir upstream
# Copy source only, excluding local credentials and runtime data.
tar -C "$source_dir" --exclude=.git --exclude=.venv --exclude=cowrie-env --exclude=./var --exclude='*.key' --exclude='*.pem' --exclude=./etc/cowrie.cfg --exclude=./etc/userdb.txt -cf - . | tar -C upstream -xf -
cp Dockerfile upstream/Dockerfile.sentinel
sudo docker compose config --quiet
sudo docker compose build cowrie
