#!/usr/bin/env bash
# FW Manager v0.2 — edits /etc/nftables.conf directly.
set -Eeuo pipefail
CONF=${FW_CONF:-/etc/nftables.conf}
BACKUP_DIR=${FW_BACKUP_DIR:-/var/backups/fw-manager}
[[ -t 0 && -t 1 ]] || { echo 'Interactive terminal required.' >&2; exit 1; }
command -v nft >/dev/null || { echo 'nft is required.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'python3 is required.' >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo 'Run with sudo: sudo ./fw-manager.sh' >&2; exit 1; }
[[ -f $CONF && -r $CONF && -w $CONF ]] || { echo "Cannot access $CONF" >&2; exit 1; }
mkdir -p -- "$BACKUP_DIR"
TMP=''
cleanup(){ [[ -z $TMP ]] || rm -f -- "$TMP"; printf '\e[?25h'; }
trap cleanup EXIT
pause(){ printf '\nPress Enter to return...'; read -r _; }
header(){ clear; printf 'FW MANAGER v0.2 | %s\n\n' "$CONF"; }
backup(){ local dest="$BACKUP_DIR/nftables-$(date +%Y%m%d-%H%M%S)-$$.conf"; cp -a -- "$CONF" "$dest"; printf '%s\n' "$dest"; }
# Python only parses chain braces; all user interaction, validation and file lifecycle are Bash.
chain_helper(){ python3 - "$CONF" "$@" <<'PY'
import sys,re
path,cmd,*args=sys.argv[1:]
with open(path,encoding='utf-8') as f: lines=f.readlines()
# Deliberately refuse ambiguous formatting instead of modifying the wrong block.
def find_chain(name):
    starts=[]
    for i,line in enumerate(lines):
        if re.match(r'^\s*chain\s+'+re.escape(name)+r'\s*\{\s*(?:#.*)?$',line): starts.append(i)
    if len(starts)!=1: raise ValueError(f'Chain {name!r} found {len(starts)} times; require exactly one')
    start=starts[0]; depth=0
    for j in range(start,len(lines)):
        line=re.sub(r'#.*$','',lines[j]); depth+=line.count('{')-line.count('}')
        if depth==0: return start,j
    raise ValueError('Unbalanced chain braces')
try:
    if cmd=='chains':
        for i,line in enumerate(lines):
            m=re.match(r'^\s*chain\s+([A-Za-z_][\w-]*)\s*\{\s*(?:#.*)?$',line)
            if m: print(m.group(1))
    elif cmd=='list':
        name=args[0]; a,b=find_chain(name)
        for i in range(a+1,b): print(f'{i+1:4d}  {lines[i].rstrip()}')
    elif cmd=='add':
        name,rule=args; a,b=find_chain(name)
        indent=re.match(r'^(\s*)',lines[a]).group(1)+'    '
        lines.insert(b,indent+rule+'\n')
        sys.stdout.write(''.join(lines))
    elif cmd=='remove':
        name,number=args; a,b=find_chain(name); n=int(number)-1
        if not a<n<b: raise ValueError('Line is not inside selected chain')
        s=lines[n].strip()
        if not s or s.startswith('#') or s.startswith(('type ','policy ','flags ','device ')) or '{' in s or '}' in s: raise ValueError('Not a removable simple rule')
        del lines[n]; sys.stdout.write(''.join(lines))
    else: raise ValueError('Unknown operation')
except (ValueError,IndexError) as e:
    print('ERROR:',e,file=sys.stderr); sys.exit(2)
PY
}
validate_ip(){ local value=$1; [[ -z $value ]] && return 0; python3 - "$value" <<'PY'
import ipaddress,sys
try: ipaddress.ip_network(sys.argv[1],strict=False)
except ValueError: sys.exit(1)
PY
}
# Always test the exact candidate before replacing the primary file.
commit(){
  local candidate=$1 old
  printf '\nChecking candidate: nft -c -f ...\n'
  if ! nft -c -f "$candidate"; then echo 'Validation failed; original unchanged.'; return 1; fi
  old=$(backup) || return 1
  echo "Backup: $old"
  cat -- "$candidate" > "$CONF" || { cp -a -- "$old" "$CONF"; return 1; }
  echo "Updated $CONF."
  printf 'Apply this file to the LIVE firewall now? [y/N] '
  read -r answer
  if [[ $answer == [yY] ]]; then
    if nft -f "$CONF"; then echo 'Applied successfully.'
    else echo 'Apply failed. Restoring configuration file (live kernel rules may differ).'; cp -a -- "$old" "$CONF"; return 1; fi
  else echo 'File updated; live firewall not changed. Run Apply when ready.'; fi
}
make_tmp(){ TMP=$(mktemp "$(dirname "$CONF")/.fw-manager.XXXXXXXX"); chmod 600 "$TMP"; }
choose_chain(){
  local chains
  chains=$(chain_helper chains) || return 1
  echo "Available chains:"
  printf '%s\n' "$chains"
  printf 'Chain name: '; read -r CHAIN
  [[ -n $CHAIN ]] || return 1
  chain_helper list "$CHAIN" >/dev/null
}
add_rule(){
  header; choose_chain || { pause; return; }
  echo 'Add a simple INPUT/FORWARD/OUTPUT rule.'
  printf 'Action [accept/drop/reject]: '; read -r action
  [[ $action =~ ^(accept|drop|reject)$ ]] || { echo 'Invalid action'; pause; return; }
  printf 'Protocol [tcp/udp/icmp/icmpv6/any]: '; read -r proto
  [[ $proto =~ ^(tcp|udp|icmp|icmpv6|any)$ ]] || { echo 'Invalid protocol'; pause; return; }
  printf 'Source IP/CIDR (empty = any): '; read -r source
  validate_ip "$source" || { echo 'Invalid IP/CIDR'; pause; return; }
  printf 'Destination port (empty = any): '; read -r port
  if [[ -n $port ]]; then
    [[ $proto == tcp || $proto == udp ]] && [[ $port =~ ^[0-9]{1,5}$ ]] && ((10#$port >= 1 && 10#$port <= 65535)) || { echo 'Port requires TCP/UDP and range 1-65535'; pause; return; }
    port=$((10#$port))
  fi
  local rule='' family=''
  if [[ -n $source ]]; then
    [[ $source == *:* ]] && family='ip6' || family='ip'
    rule="$family saddr $source "
  fi
  case "$proto" in tcp|udp) rule+="$proto "; [[ -z $port ]] || rule+="dport $port ";; icmp) rule+='ip protocol icmp ';; icmpv6) rule+='ip6 nexthdr icmpv6 ';; esac
  rule+="$action"
  printf '\nNew rule: %s\n' "$rule"
  printf 'Write to %s? [y/N] ' "$CONF"; read -r answer
  [[ $answer == [yY] ]] || return
  make_tmp
  if chain_helper add "$CHAIN" "$rule" > "$TMP"; then commit "$TMP" || true; fi
  rm -f -- "$TMP"; TMP=''; pause
}
remove_rule(){
  header; choose_chain || { pause; return; }
  chain_helper list "$CHAIN" || { pause; return; }
  printf '\nFile line number to remove (shown on left): '; read -r number
  [[ $number =~ ^[0-9]+$ ]] || { echo 'Invalid line'; pause; return; }
  printf 'Confirm removal from %s? [y/N] ' "$CONF"; read -r answer
  [[ $answer == [yY] ]] || return
  make_tmp
  if chain_helper remove "$CHAIN" "$number" > "$TMP"; then commit "$TMP" || true; fi
  rm -f -- "$TMP"; TMP=''; pause
}
status(){ header; echo 'Active nftables ruleset:'; nft list ruleset; pause; }
list_file(){ header; echo "FILE: $CONF"; nl -ba -- "$CONF"; pause; }
apply_file(){
  header; echo "Checking $CONF"; nft -c -f "$CONF" || { pause; return; }
  echo 'WARNING: This applies the ENTIRE file. flush ruleset may remove Docker/libvirt/Tailscale rules.'
  echo 'A remote SSH connection may be disconnected.'
  printf 'Type APPLY to proceed: '; read -r answer
  if [[ $answer == APPLY ]]; then backup; nft -f "$CONF" && echo 'Applied.' || echo 'Apply failed; inspect live rules.'; fi
  pause
}
check_file(){ header; nft -c -f "$CONF" && echo 'Syntax OK' || echo 'Syntax error'; pause; }
backup_file(){ header; backup; pause; }
options=('Status (live ruleset)' 'List /etc/nftables.conf' 'Add rule to file' 'Remove rule from file' 'Apply /etc/nftables.conf' 'Backup file' 'Validate nft -c')
selected=0
while :; do
  header
  for i in "${!options[@]}"; do
    if ((i==selected)); then printf '\e[32m > %s\e[0m\n' "${options[i]}"; else printf '   %s\n' "${options[i]}"; fi
  done
  printf '\nUP/DOWN navigate | RIGHT/ENTER select | LEFT back | ESC quit\n'
  IFS= read -rsn1 key || break
  if [[ $key == $'\e' ]]; then
    IFS= read -rsn1 -t 0.08 extra || extra=''
    if [[ $extra == '[' ]]; then
      IFS= read -rsn1 -t 0.08 arrow || arrow=''
      case "$arrow" in A) selected=$(( (selected + ${#options[@]} - 1) % ${#options[@]} ));; B) selected=$(( (selected + 1) % ${#options[@]} ));; C) key=$'\n';; D) continue;; esac
    elif [[ -z $extra ]]; then break; fi
  fi
  if [[ $key == '' || $key == $'\n' ]]; then
    case "$selected" in 0) status;; 1) list_file;; 2) add_rule;; 3) remove_rule;; 4) apply_file;; 5) backup_file;; 6) check_file;; esac
  fi
done
