#!/usr/bin/env bash
monitor_menu() {
  while menu 'Live Monitor' 'TCP connections' 'UDP sockets' 'Interface traffic counters' 'Listening ports' 'Back'; do
    case "$MENU_CHOICE" in
      0) run_view 'TCP connections' ss -tanp;;
      1) run_view 'UDP sockets' ss -uanp;;
      2) run_view 'Interface counters' cat /proc/net/dev;;
      3) run_view 'Listening ports' ss -tuln;;
      *) break;;
    esac
  done
}
