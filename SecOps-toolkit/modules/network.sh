#!/usr/bin/env bash
nm_profile_select() {
  need_cmd nmcli || return 1
  echo 'Available NetworkManager profiles:'
  nmcli -f NAME,UUID,TYPE,DEVICE connection show
  read -r -p 'Profile UUID (blank cancels): ' NM_UUID
  [[ "$NM_UUID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || { echo 'Invalid UUID'; return 1; }
  nmcli -g connection.id connection show uuid "$NM_UUID" >/dev/null 2>&1 || { echo 'Unknown profile'; return 1; }
}
nm_backup_profile() {
  local dir="$HOME/.local/share/secops-toolkit/profile-backups" file
  mkdir -p "$dir" || return 1
  file="$dir/${NM_UUID}-$(date +%Y%m%d-%H%M%S).txt"
  nmcli -s connection show uuid "$NM_UUID" > "$file" && echo "Profile snapshot: $file"
  echo 'Snapshot is for review, not an importable restoration file.'
}
nm_modify() {
  local description="$1"; shift
  printf '\nChange: %s\n' "$description"
  echo 'Saved profile changes may interrupt connectivity when reapplied.'
  confirm 'Save changes to this NetworkManager profile?' || return
  nm_backup_profile || return
  nmcli connection modify uuid "$NM_UUID" "$@" && echo 'Saved. Reapply/reconnect separately when safe.'
  pause
}
nm_dns_sinkhole() {
  nm_profile_select || { pause; return; }
  local typ
  typ=$(nmcli -g connection.type connection show uuid "$NM_UUID")
  [[ "$typ" == 802-11-wireless || "$typ" == 802-3-ethernet ]] || { echo 'Only Wi-Fi/Ethernet profiles supported.'; pause; return; }
  echo 'Local sinkhole must listen on 127.0.0.1:53 on this machine.'
  echo 'IPv6 and Tailscale DNS may bypass IPv4-only settings; verify after reconnect.'
  nm_modify 'Local DNS sinkhole (IPv4)' ipv4.dns 127.0.0.1 ipv4.ignore-auto-dns yes
}
nm_dns_restore() {
  nm_profile_select || { pause; return; }
  nm_modify 'Restore automatic IPv4 DNS' ipv4.dns '' ipv4.ignore-auto-dns no
}
nm_dns_custom() {
  nm_profile_select || { pause; return; }
  local dns ip
  read -r -p 'IPv4 DNS servers (space-separated): ' dns
  [[ -n "$dns" ]] || { pause; return; }
  for ip in $dns; do
    valid_ip "$ip" && [[ "$ip" != *:* && "$ip" != */* ]] || { echo "Invalid IPv4 DNS: $ip"; pause; return; }
  done
  nm_modify 'Custom IPv4 DNS' ipv4.dns "$dns" ipv4.ignore-auto-dns yes
}
nm_ipv4() {
  nm_profile_select || { pause; return; }
  local ip gw
  read -r -p 'IPv4 address/prefix (e.g. 192.168.3.50/24): ' ip
  valid_ip "$ip" && [[ "$ip" == */* && "$ip" != *:* ]] || { echo 'Invalid address/prefix'; pause; return; }
  read -r -p 'IPv4 gateway: ' gw
  valid_ip "$gw" && [[ "$gw" != *:* && "$gw" != */* ]] || { echo 'Invalid gateway'; pause; return; }
  nm_modify 'Static IPv4 configuration' ipv4.method manual ipv4.addresses "$ip" ipv4.gateway "$gw"
}
nm_dhcp() {
  nm_profile_select || { pause; return; }
  nm_modify 'Restore DHCP IPv4' ipv4.method auto ipv4.addresses '' ipv4.gateway ''
}
nm_routes() {
  nm_profile_select || { pause; return; }
  run_view 'Profile routes and routing metrics' nmcli -f ipv4.routes,ipv4.route-metric,ipv6.routes,ipv6.route-metric connection show uuid "$NM_UUID"
}
nm_wireguard() {
  run_view 'WireGuard NetworkManager profiles' nmcli -f NAME,UUID,TYPE,DEVICE connection show
  if command -v wg >/dev/null; then run_view 'WireGuard tunnel status' sudo wg show; fi
}
nm_menu() {
  while menu 'NetworkManager | Advanced Profiles' 'Device status and active profiles' 'All saved profiles' 'Profile details' 'Set DNS sinkhole (Wi-Fi/Ethernet)' 'Custom IPv4 DNS' 'Restore automatic IPv4 DNS' 'Set static IPv4' 'Restore DHCP' 'Profile routes and metrics' 'WireGuard status' 'Back'; do
    case "$MENU_CHOICE" in
      0) run_view 'Network devices' nmcli device status;;
      1) run_view 'Saved profiles' nmcli connection show;;
      2) nm_profile_select && run_view 'Profile details' nmcli connection show uuid "$NM_UUID" || pause;;
      3) nm_dns_sinkhole;;
      4) nm_dns_custom;;
      5) nm_dns_restore;;
      6) nm_ipv4;;
      7) nm_dhcp;;
      8) nm_routes;;
      9) nm_wireguard;;
      *) break;;
    esac
  done
}
network_menu() {
  while menu 'IP & Network' 'Interfaces / addresses' 'Routes' 'Advanced NetworkManager' 'Nmap Blue Team Audits' 'Back'; do
    case "$MENU_CHOICE" in
      0) run_view 'Interfaces' ip -br address;;
      1) run_view 'Routing table' ip route show table main;;
      2) nm_menu;;
      3) nmap_audit_menu;;
      *) break;;
    esac
  done
}
