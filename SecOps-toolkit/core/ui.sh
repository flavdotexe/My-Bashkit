#!/usr/bin/env bash
# Arrow-key UI: ↑↓ select, →/Enter open, ←/Esc back.
MENU_CHOICE=0
menu() {
  local title="$1"; shift
  local -a items=("$@")
  local selected=0 key rest
  while true; do
    clear
    printf '\033[1;32m%s\033[0m\n\n' "$title"
    for ((i=0;i<${#items[@]};i++)); do
      if ((i==selected)); then printf '\033[32m ❯ %s\033[0m\n' "${items[i]}"; else printf '   %s\n' "${items[i]}"; fi
    done
    printf '\n\033[2m↑↓ Navigate  →/Enter Select  ←/Esc Back\033[0m\n'
    IFS= read -rsn1 key || return 1
    if [[ "$key" == $'\e' ]]; then
      rest=''
      IFS= read -rsn2 -t 0.15 rest || true
      case "$rest" in
        '[A') selected=$(((selected+${#items[@]}-1)%${#items[@]}));;
        '[B') selected=$(((selected+1)%${#items[@]}));;
        '[C') MENU_CHOICE=$selected; return 0;;
        '[D'|'') return 1;;
      esac
    elif [[ "$key" == '' || "$key" == $'\r' ]]; then MENU_CHOICE=$selected; return 0
    elif [[ "$key" == 'q' ]]; then return 1
    fi
  done
}
pause() { printf '\nPress Enter to return...'; read -r _ || true; }
run_view() { clear; printf '\033[1;32m%s\033[0m\n\n' "$1"; shift; "$@" || printf '\nCommand failed (exit %s)\n' "$?"; pause; }
confirm() { local a; read -r -p "$1 [type YES]: " a; [[ "$a" == YES ]]; }
need_cmd() { command -v "$1" >/dev/null || { echo "Missing dependency: $1"; return 1; }; }
valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && ((10#$1>=1 && 10#$1<=65535)); }
valid_ip() { python3 - "$1" <<'PY'
import ipaddress,sys
try: ipaddress.ip_network(sys.argv[1],strict=False)
except ValueError: sys.exit(1)
PY
}
