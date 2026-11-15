#!/usr/bin/env bash
diagnostics_menu() {
  while menu 'Diagnostics' 'Ping 1.1.1.1' 'Tracepath 1.1.1.1' 'IP route to 1.1.1.1' 'DNS lookup example.com' 'Back'; do
    case "$MENU_CHOICE" in
      0) run_view 'Ping' ping -c 4 -W 2 1.1.1.1;;
      1) run_view 'Tracepath' tracepath 1.1.1.1;;
      2) run_view 'Route lookup' ip route get 1.1.1.1;;
      3) run_view 'DNS lookup' getent ahosts example.com;;
      *) break;;
    esac
  done
}
