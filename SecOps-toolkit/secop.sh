#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/core/ui.sh"
source "$ROOT/modules/firewall.sh"
source "$ROOT/modules/network.sh"
source "$ROOT/modules/nmap_audit.sh"
source "$ROOT/modules/dns.sh"
source "$ROOT/modules/security.sh"
source "$ROOT/modules/diagnostics.sh"
source "$ROOT/modules/monitor.sh"
main() {
  while true; do
    menu 'SECOPS TOOLKIT | Linux Network & Security' 'Firewall Manager' 'IP & Network / Nmap' 'DNS Manager' 'Security Center' 'Diagnostics' 'Live Monitor' 'Quit' || break
    case "$MENU_CHOICE" in
      0) firewall_menu;; 1) network_menu;; 2) dns_menu;; 3) security_menu;; 4) diagnostics_menu;; 5) monitor_menu;; *) break;;
    esac
  done
  clear
}
main "$@"
