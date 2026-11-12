# FW-MANAGER v0.1

Interactive Bash CLI for managing a dedicated nftables input table.

## Requirements
- Linux, Bash 4+, nftables, Python 3 (IP address validation), sudo
- Terminal with ANSI escape support

## Start
```bash
chmod +x fw-manager.sh
./fw-manager.sh
```

Controls: up/down navigate, right/Enter select, left returns (at root it does nothing), Esc quits at the menu. While entering text, Enter submits the prompt.

## Safety
- Candidate rules are stored in `rules/firewall.nft`; changes are not active until Apply.
- `nft -c -f` checks syntax, not whether remote access will remain available.
- The default policy is ACCEPT. Other firewall tables and Docker/Tailscale rules remain untouched, but newly added DROP/REJECT rules can still disrupt connectivity.
- The manager replaces only its own `inet fw_manager` table on Apply; it does not flush the global ruleset.
- Before applying, an existing manager table is saved to `backups/preapply-*.nft` if it exists. Backups are not automatically restored.
- The backup menu copies the candidate ruleset, not the full live firewall.
- No automatic rollback or persistent boot-time restore is implemented.
- Input rules only; output and forwarding are out of scope.
- For local lab testing, start with a VM or a console session rather than SSH.
