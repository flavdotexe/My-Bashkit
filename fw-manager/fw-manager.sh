#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RULES="$BASE/rules/firewall.nft"
BACKUPS="$BASE/backups"
TABLE="fw_manager"
mkdir -p "$BASE/rules" "$BACKUPS"
command -v nft >/dev/null || { echo 'nft is required'; exit 1; }
command -v python3 >/dev/null || { echo 'python3 is required for IP validation'; exit 1; }
[[ -f "$RULES" ]] || cat > "$RULES" <<'NFT'
table inet fw_manager {
    chain input {
        type filter hook input priority 10; policy accept;
    }
}
NFT
[[ -t 0 && -t 1 ]] || { echo 'Interactive terminal required'; exit 1; }
OLD_STTY=$(stty -g)
cleanup() { stty "$OLD_STTY" 2>/dev/null || :; printf '\033[?25h\033[0m'; }
trap cleanup EXIT
trap 'exit 130' INT TERM
stty -echo -icanon min 1 time 0
printf '\033[?25l'
read_key() {
  local a b c
  IFS= read -rsn1 a || return 1
  if [[ "$a" == $'\e' ]]; then
    b=''; c=''
    IFS= read -rsn1 -t 0.08 b || :
    if [[ "$b" == '[' ]]; then
      IFS= read -rsn1 -t 0.08 c || :
      case "$c" in A) KEY=up;; B) KEY=down;; C) KEY=enter;; D) KEY=back;; *) KEY=none;; esac
    elif [[ -z "$b" ]]; then KEY=quit
    else KEY=none
    fi
  elif [[ "$a" == '' || "$a" == $'\n' || "$a" == $'\r' ]]; then KEY=enter
  else KEY=none
  fi
}
message() { printf '\n%s\n' "$*"; printf '\nPress any key to return...'; IFS= read -rsn1 _ || :; }
prompt() {
  stty echo icanon
  printf '\033[?25h'
  read -r -p "$1" REPLY_VALUE || REPLY_VALUE=''
  stty -echo -icanon min 1 time 0
  printf '\033[?25l'
}
valid_ip() {
  python3 - "$1" <<'PY'
import ipaddress,sys
try: ipaddress.ip_network(sys.argv[1],strict=False)
except ValueError: sys.exit(1)
PY
}
valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
check_rules() { sudo nft -c -f "$RULES"; }
status() {
  clear
  echo '=== STATUS ==='
  if sudo nft list table inet "$TABLE" 2>/dev/null; then :; else echo 'Manager table not currently loaded.'; fi
  message 'Status displayed.'
}
list_rules() { clear; echo '=== CANDIDATE RULESET ==='; cat -n "$RULES"; message 'End of ruleset.'; }
add_rule() {
  clear; echo '=== ADD INPUT RULE ==='
  prompt 'Action (accept/drop/reject): '; local action=${REPLY_VALUE,,}
  [[ "$action" =~ ^(accept|drop|reject)$ ]] || { message 'Invalid action.'; return; }
  prompt 'Protocol (tcp/udp): '; local proto=${REPLY_VALUE,,}
  [[ "$proto" =~ ^(tcp|udp)$ ]] || { message 'Invalid protocol.'; return; }
  prompt 'Destination port (1-65535): '; local port=$REPLY_VALUE
  valid_port "$port" || { message 'Invalid port.'; return; }
  port=$((10#$port))
  prompt 'Source IPv4/IPv6 or CIDR (blank = any): '; local ip=$REPLY_VALUE
  local family='' src=''
  if [[ -n "$ip" ]]; then
    valid_ip "$ip" || { message 'Invalid IP/CIDR.'; return; }
    if [[ "$ip" == *:* ]]; then family='ip6'; else family='ip'; fi
    src="$family saddr $ip "
  fi
  local rule="        ${src}${proto} dport ${port} ${action}"
  local temp; temp=$(mktemp "$BASE/rules/.candidate.XXXXXX")
  # Insert before the input chain's closing brace (the first indented closing brace).
  awk -v rule="$rule" '/^    }$/ && !done {print rule; done=1} {print}' "$RULES" > "$temp"
  if ! sudo nft -c -f "$temp"; then rm -f "$temp"; message 'Validation failed; no changes saved.'; return; fi
  mv -- "$temp" "$RULES"
  message 'Rule saved to candidate. Use Apply to activate.'
}
remove_rule() {
  clear; echo '=== REMOVE INPUT RULE ==='
  local -a lines=()
  mapfile -t lines < <(grep -nE '^        (ip(6)? saddr .+ )?(tcp|udp) dport [0-9]+ (accept|drop|reject)$' "$RULES" || :)
  if ((${#lines[@]}==0)); then message 'No managed rules to remove.'; return; fi
  printf '%s\n' "${lines[@]}"
  prompt 'Line number to remove (blank = cancel): '; local line=$REPLY_VALUE
  [[ "$line" =~ ^[0-9]+$ ]] || return
  local match='' entry number
  for entry in "${lines[@]}"; do number=${entry%%:*}; [[ "$line" == "$number" ]] && match=1; done
  [[ -n "$match" ]] || { message 'Invalid managed rule number.'; return; }
  local temp; temp=$(mktemp "$BASE/rules/.candidate.XXXXXX")
  awk -v n="$line" 'NR!=n' "$RULES" > "$temp"
  if ! sudo nft -c -f "$temp"; then rm -f "$temp"; message 'Validation failed.'; return; fi
  mv -- "$temp" "$RULES"
  message 'Rule removed from candidate. Apply to activate.'
}
backup() {
  local stamp file
  stamp=$(date +%Y%m%d-%H%M%S)
  file="$BACKUPS/firewall-$stamp-$$.nft"
  cp -- "$RULES" "$file"
  message "Candidate backup saved: $file"
}
apply() {
  clear; echo '=== APPLY ==='
  if ! check_rules; then message 'Syntax check failed. Nothing applied.'; return; fi
  echo 'WARNING: Applying may disrupt active network connections.'
  echo 'This replaces only the inet fw_manager table.'
  prompt 'Type APPLY to continue: '
  [[ "$REPLY_VALUE" == APPLY ]] || return
  local snapshot="$BACKUPS/preapply-$(date +%Y%m%d-%H%M%S)-$$.nft"
  # Backup active manager table when present.
  sudo nft list table inet "$TABLE" > "$snapshot" 2>/dev/null || rm -f "$snapshot"
  local temp; temp=$(mktemp "$BASE/rules/.apply.XXXXXX")
  # nft -f is not idempotent for an existing table: delete only our table first.
  if sudo nft list table inet "$TABLE" >/dev/null 2>&1; then
    { echo "delete table inet $TABLE"; cat "$RULES"; } > "$temp"
  else cp -- "$RULES" "$temp"; fi
  if ! sudo nft -c -f "$temp"; then rm -f "$temp"; message 'Preflight failed. Nothing applied.'; return; fi
  if sudo nft -f "$temp"; then rm -f "$temp"; message 'Applied successfully.'
  else rm -f "$temp"; message 'Apply failed; inspect active rules immediately.'; fi
}
validate() { clear; echo '=== NFT CHECK ==='; if check_rules; then message 'Candidate syntax OK.'; else message 'Candidate syntax INVALID.'; fi; }
OPTIONS=('Status' 'List rules' 'Add rule' 'Remove rule' 'Apply rules' 'Backup rules' 'Validate (nft -c)')
selected=0
while :; do
  clear
  printf 'FW-MANAGER v0.1 | nftables\n\n'
  for i in "${!OPTIONS[@]}"; do
    if ((i==selected)); then printf '\033[1;32m  > %s\033[0m\n' "${OPTIONS[i]}"; else printf '    %s\n' "${OPTIONS[i]}"; fi
  done
  printf '\nUP/DOWN navigate | RIGHT/ENTER select | LEFT back | ESC quit\n'
  read_key || break
  case "$KEY" in
    up) selected=$(((selected+${#OPTIONS[@]}-1)%${#OPTIONS[@]}));;
    down) selected=$(((selected+1)%${#OPTIONS[@]}));;
    quit) break;;
    back) :;;
    enter)
      case "$selected" in
        0) status;; 1) list_rules;; 2) add_rule;; 3) remove_rule;;
        4) apply;; 5) backup;; 6) validate;;
      esac;;
  esac
done
clear
