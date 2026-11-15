#!/usr/bin/env bash
security_menu() {
  while menu 'Security Center (read-only audit)' 'SSH effective configuration' 'Fail2ban status' 'Security sysctl values' 'Listening ports' 'Back'; do
    case "$MENU_CHOICE" in
      0) run_view 'SSH configuration' sudo sshd -T;;
      1) run_view 'Fail2ban' sudo fail2ban-client status;;
      2) run_view 'Kernel network security' sh -c 'for k in net.ipv4.ip_forward net.ipv4.conf.all.accept_redirects net.ipv4.conf.all.send_redirects net.ipv4.conf.all.rp_filter net.ipv4.tcp_syncookies; do sysctl "$k"; done';;
      3) run_view 'Listening TCP/UDP' ss -tulpen;;
      *) break;;
    esac
  done
}
