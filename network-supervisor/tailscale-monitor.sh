#!/usr/bin/env bash
# Tailnet state; status JSON is supported via tailscale CLI. Requires jq.
set -euo pipefail
OUT_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
mkdir -p "$OUT_DIR"
tmp=$(mktemp "$OUT_DIR/.tailscale.XXXXXX")
trap 'rm -f "$tmp"' EXIT
{
 echo '# HELP tailscale_monitor_success Tailscale status collector succeeded.'
 echo '# TYPE tailscale_monitor_success gauge'
 echo '# HELP tailscale_connected Local Tailscale backend is Running.'
 echo '# TYPE tailscale_connected gauge'
 echo '# HELP tailscale_peer_count Known peers in tailnet status.'
 echo '# TYPE tailscale_peer_count gauge'
 echo '# HELP tailscale_peer_online_count Online peers in tailnet status.'
 echo '# TYPE tailscale_peer_online_count gauge'
 echo '# HELP tailscale_exit_node_enabled Local node is configured to use an exit node.'
 echo '# TYPE tailscale_exit_node_enabled gauge'
} > "$tmp"
if ! command -v jq >/dev/null || ! command -v tailscale >/dev/null || ! status=$(tailscale status --json 2>/dev/null); then
 echo 'tailscale_monitor_success 0' >> "$tmp"
else
 echo 'tailscale_monitor_success 1' >> "$tmp"
 jq -r '"tailscale_connected " + (if .BackendState == "Running" then "1" else "0" end), "tailscale_peer_count " + ((.Peer // {}) | length | tostring), "tailscale_peer_online_count " + ([ (.Peer // {})[] | select(.Online == true)] | length | tostring), "tailscale_exit_node_enabled " + (if ((.ExitNodeStatus // null) != null) then "1" else "0" end)' <<< "$status" >> "$tmp"
 # Peer identity intentionally not exported: avoids high-cardinality and leaking hostnames.
fi
chmod 644 "$tmp"; mv -f "$tmp" "$OUT_DIR/tailscale.prom"; trap - EXIT
