#!/usr/bin/env bash
NFT_CONF=${NFT_CONF:-/etc/nftables.conf}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/secops-toolkit}
firewall_backup() {
  sudo mkdir -p "$BACKUP_DIR" || return
  local dst="$BACKUP_DIR/nftables-$(date +%Y%m%d-%H%M%S)-$$.conf"
  sudo cp -a -- "$NFT_CONF" "$dst" && echo "Backup: $dst"
}
firewall_add() {
  local table chain proto port source action rule temp
  echo "This edits $NFT_CONF, not a parallel configuration."
  read -r -p 'Table family/name (e.g. inet filter): ' table
  [[ "$table" =~ ^(inet|ip|ip6)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || { echo 'Invalid table'; pause; return; }
  read -r -p 'Chain (e.g. input): ' chain
  [[ "$chain" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || { echo 'Invalid chain'; pause; return; }
  read -r -p 'Protocol (tcp/udp): ' proto
  [[ "$proto" == tcp || "$proto" == udp ]] || { echo 'Invalid protocol'; pause; return; }
  read -r -p 'Destination port (1-65535): ' port
  valid_port "$port" || { echo 'Invalid port'; pause; return; }
  read -r -p 'Source IPv4/CIDR (blank for any): ' source
  if [[ -n "$source" ]]; then
    valid_ip "$source" || { echo 'Invalid IP'; pause; return; }
    [[ "$source" != *:* ]] || { echo 'IPv6 editing is not supported by this add form yet'; pause; return; }
  fi
  read -r -p 'Action (accept/drop/reject): ' action
  [[ "$action" == accept || "$action" == drop || "$action" == reject ]] || { echo 'Invalid action'; pause; return; }
  rule="${source:+ip saddr $source }$proto dport $port $action"
  printf '\nNew rule: %s\n' "$rule"
  confirm 'Edit the system configuration?' || return
  temp=$(mktemp) || return
  # Only supports simple one-line table/chain opening braces; rejects ambiguous matches.
  if ! awk -v target_table="$table" -v target_chain="$chain" -v rule="$rule" '
    BEGIN {split(target_table,t," "); count=0; in_table=0; in_chain=0; depth=0}
    {
      line=$0
      if (line ~ "^[[:space:]]*table[[:space:]]+" t[1] "[[:space:]]+" t[2] "[[:space:]]*\\{") in_table=1
      if (in_table && line ~ "^[[:space:]]*chain[[:space:]]+" target_chain "[[:space:]]*\\{") {in_chain=1; depth=0}
      if (in_chain) {
        opens=gsub(/\{/,"{",line); closes=gsub(/\}/,"}",line)
        if (depth+opens-closes==0) {print "        " rule; count++; in_chain=0}
        else depth+=opens-closes
      }
      print $0
      if (in_table && $0 ~ /^[[:space:]]*\}/ && !in_chain) in_table=0
    }
    END {if (count!=1) exit 3}
  ' "$NFT_CONF" > "$temp"; then
    echo 'Could not uniquely locate the chain; file unchanged.'; rm -f "$temp"; pause; return
  fi
  if ! sudo nft -c -f "$temp"; then echo 'nft -c failed; file unchanged.'; rm -f "$temp"; pause; return; fi
  firewall_backup || { rm -f "$temp"; pause; return; }
  sudo cp -- "$temp" "$NFT_CONF" && echo "Saved to $NFT_CONF. Use Apply to activate."
  rm -f "$temp"; pause
}
firewall_apply() {
  echo "WARNING: applying $NFT_CONF may disconnect SSH/Tailscale and alter Docker/libvirt rules."
  sudo nft -c -f "$NFT_CONF" || { echo 'Syntax check failed'; pause; return; }
  confirm 'Apply now? No automatic rollback is provided.' || return
  firewall_backup || { pause; return; }
  sudo nft -f "$NFT_CONF" && echo 'Applied to kernel' || echo 'Apply failed'
  pause
}
firewall_menu() {
  while menu 'Firewall Manager' 'View /etc/nftables.conf' 'View active ruleset' 'Add rule to file' 'Edit file with $EDITOR' 'Validate nft -c' 'Backup config' 'Apply config' 'Back'; do
    case "$MENU_CHOICE" in
      0) run_view 'Configuration file' sudo cat "$NFT_CONF";;
      1) run_view 'Kernel ruleset' sudo nft list ruleset;;
      2) firewall_add;;
      3) firewall_backup && sudo "${EDITOR:-nano}" "$NFT_CONF" || true;;
      4) run_view 'nft syntax check' sudo nft -c -f "$NFT_CONF";;
      5) firewall_backup; pause;;
      6) firewall_apply;;
      *) break;;
    esac
  done
}
