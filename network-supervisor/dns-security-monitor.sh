#!/usr/bin/env bash
# DNS security posture: configuration and observed classic DNS destinations.
# Does NOT claim to prove DNS leaks; DoH/DoT and encrypted tunnels need separate tests.
set -euo pipefail
OUT_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
STATE_DIR="${SECURITY_STATE_DIR:-/var/lib/network-supervisor}"
mkdir -p "$OUT_DIR" "$STATE_DIR"
tmp=$(mktemp "$OUT_DIR/.dns.XXXXXX")
trap 'rm -f "$tmp"' EXIT
escape() { local x="$1"; x=${x//\\/\\\\}; x=${x//\"/\\\"}; x=${x//$'\n'/ }; printf '%s' "$x"; }
{
 echo '# HELP dns_monitor_success DNS collector succeeded.'
 echo '# TYPE dns_monitor_success gauge'
 echo 'dns_monitor_success 1'
 echo '# HELP dns_resolver_info DNS servers configured by systemd-resolved.'
 echo '# TYPE dns_resolver_info gauge'
} > "$tmp"
if command -v resolvectl >/dev/null 2>&1 && resolvectl dns >/dev/null 2>&1; then
 current=$(resolvectl dns)
else
 current=$(awk '/^nameserver[[:space:]]/ {print "Link fallback: " $2}' /etc/resolv.conf 2>/dev/null || true)
fi
# Normalize and hash for change detection, ignoring ordering changes only if identical output.
if [[ -n "$current" ]]; then
 while IFS= read -r line; do
   iface=$(sed -nE 's/^Link [0-9]+ \(([^)]+)\):.*/\1/p' <<< "$line")
   [[ -n "$iface" ]] || iface="global"
   servers=${line#*:}
   for server in $servers; do
     [[ "$server" =~ ^([0-9a-fA-F:.]+)(%[[:alnum:]_.-]+)?$ ]] || continue
     printf 'dns_resolver_info{interface="%s",server="%s"} 1\n' "$(escape "$iface")" "$(escape "$server")" >> "$tmp"
   done
 done <<< "$current"
fi
hash=$(printf '%s' "$current" | sha256sum | awk '{print $1}')
old=$(cat "$STATE_DIR/dns.sha256" 2>/dev/null || true)
changes=$(cat "$STATE_DIR/dns_changes.count" 2>/dev/null || echo 0)
[[ "$changes" =~ ^[0-9]+$ ]] || changes=0
if [[ -n "$old" && "$hash" != "$old" ]]; then changes=$((changes+1)); fi
printf '%s\n' "$hash" > "$STATE_DIR/dns.sha256"
printf '%s\n' "$changes" > "$STATE_DIR/dns_changes.count"
{
 echo '# HELP dns_configuration_changes_total DNS configuration changes since monitor initialization.'
 echo '# TYPE dns_configuration_changes_total counter'
 echo "dns_configuration_changes_total $changes"
 echo '# HELP dns_resolver_count Number of configured resolver entries.'
 echo '# TYPE dns_resolver_count gauge'
 printf 'dns_resolver_count %s\n' "$(grep -c '^dns_resolver_info{' "$tmp" || true)"
 echo '# HELP dns_tailscale_dns_enabled Tailscale DNS preference when available (1 enabled, 0 disabled).'
 echo '# TYPE dns_tailscale_dns_enabled gauge'
} >> "$tmp"
if command -v tailscale >/dev/null 2>&1; then
 tsdns=$(tailscale debug prefs 2>/dev/null | grep -oE 'CorpDNS: (true|false)' | head -1 || true)
 case "$tsdns" in *true*) echo 'dns_tailscale_dns_enabled 1' >> "$tmp";; *false*) echo 'dns_tailscale_dns_enabled 0' >> "$tmp";; esac
fi
chmod 644 "$tmp"; mv -f "$tmp" "$OUT_DIR/dns_security.prom"; trap - EXIT
