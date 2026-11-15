# SecOps Toolkit v1.0 (initial prototype)

A keyboard-driven Bash TUI for Linux networking and security administration.

## Installation (Arch Linux)

```bash
sudo pacman -S --needed nftables iproute2 networkmanager nmap python sudo nano
chmod +x secops.sh
./secops.sh
```

Optional tools: `openssh`, `fail2ban`, `systemd-resolvconf` / `systemd-resolved`, `tracepath` (from `iputils` on Arch, depending on release).

Use ↑↓ to navigate, → or Enter to select, ← or Esc to go back. `q` also returns.

## Modules

- **Firewall:** directly reads and edits `/etc/nftables.conf` (`NFT_CONF` can override). It validates candidate edits with `nft -c`, creates a backup before editing, and applies only on explicit confirmation. Editing the file and loading kernel rules remain distinct actions. The add-rule form supports basic TCP/UDP IPv4 rules and **simple single-line table/chain declarations only**. For complex rulesets use the editor option. No general-purpose automatic rule removal yet.
- **Network/Nmap:** view interfaces, routes, NetworkManager connections; authorized IPv4 host discovery and common-port scan. No IP configuration write flow yet.
- **DNS:** view resolver status, flush systemd-resolved cache, set persistent DNS for a NetworkManager connection (reconnection required), query domains.
- **Security:** read-only SSH/Fail2ban/sysctl/port audits.
- **Diagnostics:** ping, tracepath, routing, DNS.
- **Monitor:** snapshot of TCP/UDP connections and traffic counters (not continuous refresh).

## Safety

Never apply an unreviewed `/etc/nftables.conf` over SSH. A config containing `flush ruleset` may wipe dynamic Docker/libvirt/Tailscale rules. `nft -c` checks syntax, not reachability or logical correctness. Backup is not an automatic rollback. For production, use a local console or a separately tested timed rollback.

Only scan networks you own or are authorized to assess.

## Next engineering steps

Tests using network namespaces, full nftables parser or constrained rule blocks, reliable removal by managed rule identifiers, IP write flows with rollback, continuous monitor, distro-specific adapters, privilege separation.
