#!/usr/bin/env bash
# Local listening sockets, not proof of Internet exposure.
set -euo pipefail
OUT_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
mkdir -p "$OUT_DIR"
tmp=$(mktemp "$OUT_DIR/.ports.XXXXXX")
trap 'rm -f "$tmp"' EXIT
escape() { local x="$1"; x=${x//\\/\\\\}; x=${x//\"/\\\"}; printf '%s' "$x"; }
command -v ss >/dev/null || { echo 'port_monitor_success 0' > "$tmp"; mv "$tmp" "$OUT_DIR/port_exposure.prom"; exit 1; }
{
 echo '# HELP port_monitor_success Listening port collector succeeded.'
 echo '# TYPE port_monitor_success gauge'
 echo 'port_monitor_success 1'
 echo '# HELP port_listening_info Listening socket by transport, address and port; not external reachability.'
 echo '# TYPE port_listening_info gauge'
 echo '# HELP port_listening_count Unique listening local endpoints by protocol.'
 echo '# TYPE port_listening_count gauge'
} > "$tmp"
# -H removes header, -n numeric, -l listening, -t/-u TCP/UDP. Process names deliberately omitted (unstable labels).
ss -H -n -l -t -u | awk '{print $1 " " $5}' | sort -u | while read -r proto endpoint; do
 [[ "$proto" == tcp || "$proto" == udp ]] || continue
 port=${endpoint##*:}; addr=${endpoint%:*}
 [[ "$port" =~ ^[0-9]+$ ]] || continue
 scope=interface
 case "$addr" in '0.0.0.0'|'*'|'[::]'|'::') scope=wildcard;; '127.'*|'[::1]'|'::1') scope=loopback;; esac
 printf 'port_listening_info{protocol="%s",address="%s",port="%s",scope="%s"} 1\n' "$proto" "$(escape "$addr")" "$port" "$scope" >> "$tmp"
done
for proto in tcp udp; do
 n=$(grep -c "^port_listening_info{protocol=\"$proto\"" "$tmp" || true)
 printf 'port_listening_count{protocol="%s"} %s\n' "$proto" "$n" >> "$tmp"
done
chmod 644 "$tmp"; mv -f "$tmp" "$OUT_DIR/port_exposure.prom"; trap - EXIT
