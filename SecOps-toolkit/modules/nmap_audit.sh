#!/usr/bin/env bash
NMAP_REPORT_DIR="${NMAP_REPORT_DIR:-$HOME/.local/share/secops-toolkit/reports}"
nmap_target() {
  local prompt="${1:-Authorized IPv4 host/CIDR}" target
  read -r -p "$prompt: " target
  valid_ip "$target" && [[ "$target" != *:* ]] || { echo 'Invalid IPv4 target'; pause; return 1; }
  NMAP_TARGET="$target"
}
nmap_host() {
  nmap_target 'Authorized single IPv4 host' || return 1
  [[ "$NMAP_TARGET" != */* ]] || { echo 'Single host required'; pause; return 1; }
}
nmap_execute() {
  local label="$1"; shift
  local stamp base
  mkdir -p -- "$NMAP_REPORT_DIR" || { pause; return; }
  stamp=$(date +%Y%m%d-%H%M%S)
  base="$NMAP_REPORT_DIR/${label}-${stamp}-$$"
  printf 'Target: %s\nReport: %s.{nmap,xml,gnmap}\n' "$NMAP_TARGET" "$base"
  confirm 'Run authorized scan and save reports?' || return
  nmap -oA "$base" "$@" -- "$NMAP_TARGET" || true
  pause
}
nmap_baseline() {
  nmap_host || return
  local base="$NMAP_REPORT_DIR/baseline-${NMAP_TARGET}"
  mkdir -p "$NMAP_REPORT_DIR" || return
  confirm "Save/replace baseline $base.xml?" || return
  nmap -sT -sV --top-ports 100 -oA "$base" -- "$NMAP_TARGET" || true
  pause
}
nmap_changes() {
  local target current baseline
  nmap_host || return
  target="$NMAP_TARGET"
  baseline="$NMAP_REPORT_DIR/baseline-${target}.xml"
  [[ -f "$baseline" ]] || { echo "Missing baseline: $baseline"; pause; return; }
  need_cmd ndiff || { pause; return; }
  mkdir -p "$NMAP_REPORT_DIR"
  current="$NMAP_REPORT_DIR/current-${target}-$(date +%Y%m%d-%H%M%S).xml"
  confirm "Scan $target and compare with baseline?" || return
  nmap -sT -sV --top-ports 100 -oX "$current" -- "$target" || { pause; return; }
  ndiff "$baseline" "$current" | tee "${current%.xml}.diff" || true
  pause
}
nmap_custom() {
  nmap_host || return
  local ports
  read -r -p 'TCP ports (e.g. 22,80,443 or 8000-8010): ' ports
  [[ "$ports" =~ ^[0-9,-]+$ ]] || { echo 'Invalid port syntax'; pause; return; }
  local segment a b
  local IFS=,
  for segment in $ports; do
    if [[ "$segment" == *-* ]]; then
      a=${segment%-*}; b=${segment#*-}
      valid_port "$a" && valid_port "$b" && ((10#$a <= 10#$b)) || { echo 'Invalid port range'; pause; return; }
    else
      valid_port "$segment" || { echo 'Invalid port'; pause; return; }
    fi
  done
  nmap_execute custom -sT -p "$ports"
}
nmap_audit_menu() {
  need_cmd nmap || { pause; return; }
  while menu 'Nmap | Blue Team Audits' 'Asset discovery' 'TCP ports' 'Service detection' 'Common UDP ports (sudo)' 'SSH algorithms / host keys' 'TLS protocols / ciphers' 'Save security baseline' 'Detect changes (ndiff)' 'Custom TCP ports' 'List reports' 'Back'; do
    case "$MENU_CHOICE" in
      0) nmap_target && nmap_execute discovery -sn;;
      1) nmap_host && nmap_execute tcp -sT --top-ports 100;;
      2) nmap_host && nmap_execute services -sT -sV --top-ports 100;;
      3) nmap_host && { echo 'UDP scanning may require elevated privileges.'; nmap_execute udp -sU -p 53,67,68,123,161,500,4500; };;
      4) nmap_host && nmap_execute ssh -sT -p 22 --script ssh2-enum-algos,ssh-hostkey;;
      5) nmap_host && nmap_execute tls -sT -p 443,8443 --script ssl-enum-ciphers;;
      6) nmap_baseline;;
      7) nmap_changes;;
      8) nmap_custom;;
      9) run_view 'Reports' ls -lah "$NMAP_REPORT_DIR";;
      *) break;;
    esac
  done
}
