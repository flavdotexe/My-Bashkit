#!/usr/bin/env bash
dns_change() {
  local conn choice dns
  need_cmd nmcli || { pause; return; }
  nmcli -t -f NAME,UUID,DEVICE connection show --active
  read -r -p 'Connection UUID to modify: ' conn
  [[ "$conn" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo 'Invalid UUID'; pause; return; }
  echo '1 Cloudflare (1.1.1.1, 1.0.0.1) | 2 Quad9 (9.9.9.9, 149.112.112.112) | 3 Google (8.8.8.8, 8.8.4.4)'
  read -r -p 'Choose: ' choice
  case "$choice" in 1) dns='1.1.1.1 1.0.0.1';; 2) dns='9.9.9.9 149.112.112.112';; 3) dns='8.8.8.8 8.8.4.4';; *) echo 'Invalid choice'; pause; return;; esac
  echo "Selected DNS: $dns"
  echo 'Changes are persistent; reconnecting may interrupt network access.'
  confirm 'Save DNS settings to NetworkManager profile?' || return
  sudo nmcli connection modify uuid "$conn" ipv4.dns "$dns" ipv4.ignore-auto-dns yes && echo 'Saved. Reconnect the profile to activate.'
  pause
}
dns_flush() {
  if command -v resolvectl >/dev/null && systemctl -q is-active systemd-resolved; then
    sudo resolvectl flush-caches
  elif command -v nmcli >/dev/null; then
    echo 'No supported DNS cache flush backend detected. NetworkManager itself is not necessarily a DNS cache.'
  else echo 'No supported cache service found'; fi
  pause
}
dns_menu() {
  while menu 'DNS Manager' 'Show resolver status' 'Flush systemd-resolved cache' 'Choose DNS (NetworkManager)' 'DNS lookup (resolvectl)' 'Back'; do
    case "$MENU_CHOICE" in
      0) run_view 'DNS status' resolvectl status;;
      1) dns_flush;;
      2) dns_change;;
      3) local host; read -r -p 'Domain: ' host; [[ "$host" =~ ^[a-zA-Z0-9.-]+$ ]] && run_view 'DNS lookup' resolvectl query "$host" || { echo 'Invalid domain'; pause; };;
      *) break;;
    esac
  done
}
