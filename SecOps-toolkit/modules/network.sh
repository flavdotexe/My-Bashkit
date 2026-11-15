#!/usr/bin/env bash
network_scan() {
  local target
  read -r -p 'Authorized target IPv4/CIDR (e.g. 192.168.1.0/24): ' target
  valid_ip "$target" || { echo 'Invalid target'; pause; return; }
  [[ "$target" != *:* ]] || { echo 'IPv4 targets only in v1'; pause; return; }
  echo 'Only scan networks you own or have permission to test.'
  confirm "Run nmap -sn $target?" && nmap -sn -- "$target" || true
  pause
}
network_ports() {
  local target
  read -r -p 'Authorized target IPv4 address: ' target
  valid_ip "$target" || { echo 'Invalid target'; pause; return; }
  [[ "$target" != */* && "$target" != *:* ]] || { echo 'Enter a single IPv4 host'; pause; return; }
  confirm "Scan common TCP ports on $target?" && nmap -sT --top-ports 100 -- "$target" || true
  pause
}
network_menu() {
  while menu 'IP & Network / Nmap' 'Interfaces / addresses' 'Routes' 'NetworkManager connections' 'Discover hosts (nmap -sn)' 'Scan common TCP ports (nmap)' 'Back'; do
    case "$MENU_CHOICE" in
      0) run_view 'Interfaces' ip -br address;;
      1) run_view 'Routing table' ip route show table main;;
      2) run_view 'NetworkManager' nmcli connection show;;
      3) need_cmd nmap && network_scan || pause;;
      4) need_cmd nmap && network_ports || pause;;
      *) break;;
    esac
  done
}
