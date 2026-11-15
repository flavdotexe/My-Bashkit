# Network Supervisor — Security Observability

A security-focused Grafana dashboard using Bash collectors, systemd timers, Prometheus, and node_exporter textfile collector.

## Modules

1. **SSH Security** — existing SSH/Fail2ban collector, preserved (only invalid Markdown fences removed from script files).
2. **Device Governance** — existing hotspot, virtual-network and SSH-session collectors.
3. **DNS Security** — systemd-resolved resolver inventory and persisted configuration change counter. **This is not a confirmed DNS leak test**; DoH/DoT, application-specific DNS and egress route need separate active verification.
4. **Port Exposure** — local TCP/UDP listening endpoints and binding scope. **This does not establish Internet accessibility.** UDP listeners are not proof of remotely reachable UDP services.
5. **VPN / WireGuard** — Tailscale backend state, peer counts and exit-node state. WireGuard transport telemetry, peer latency and tunnel byte counters are not yet implemented.

## Fresh install on Arch Linux

Dependencies: `bash`, `jq`, `iproute2` (`ss`), `coreutils`, `systemd`, `libnotify` not required. Install `node_exporter`, Prometheus and Grafana by your preferred package/container method. Existing collectors optionally use `iw`, `docker`, `virsh`, `fail2ban-client`.

```bash
sudo pacman -S --needed jq iproute2
sudo install -d -m 755 /var/lib/node_exporter/textfile_collector /var/lib/network-supervisor
sudo install -m 755 -- *.sh /usr/local/bin/
sudo install -m 644 -- *.service *.timer /etc/systemd/system/
# IMPORTANT: Edit hotspot-monitor.service and set the real hotspot interface (e.g. wlp1s0).
sudo systemctl daemon-reload
sudo systemctl enable --now ssh-monitor.timer hotspot-monitor.timer virtual-networks-monitor.timer dns-security-monitor.timer port-exposure-monitor.timer tailscale-monitor.timer
```

**IMPORTANT:** If the node_exporter runs in Docker, the textfile directory must be bind-mounted read-only into its container, and `--collector.textfile.directory` must point to the container path. The directory must be readable by the node_exporter process. Ensure Prometheus scrapes the exporter and Grafana is connected to Prometheus.

Run collectors manually and verify:

```bash
sudo /usr/local/bin/dns-security-monitor.sh
sudo /usr/local/bin/port-exposure-monitor.sh
sudo /usr/local/bin/tailscale-monitor.sh
sudo systemctl list-timers --all | grep monitor
ls -l /var/lib/node_exporter/textfile_collector/*.prom
curl -s http://localhost:9100/metrics | grep -E '^(dns_|port_|tailscale_)' | head
```

Import `Network_Supervisor_Security.json` in Grafana (**Dashboards → New → Import**) and select your Prometheus datasource. SSH/Fail2ban existing metrics remain unchanged. Existing SSH collector needs access to the system journal and Fail2ban; the system services run as root by default.

### Accuracy and security notes

- DNS configuration changes are counted since the state directory was initialized. First run establishes the baseline. Tailscale DNS preference may be unavailable depending on CLI version; missing data is intentional.
- A DNS leak requires an expected VPN/DNS routing policy and an independent active test. This release reports configuration posture only; it never labels a DNS leak confirmed.
- `ss` shows local listeners, including Docker-related bound ports, but not firewall/NAT or remote reachability. Test external exposure from an independently controlled host.
- `tailscale status --json` reports tailnet status; Tailscale uses WireGuard but does not necessarily expose a standard `wg` interface.
- For a true fresh reset, stop and disable old timers and remove old `.prom` files only after identifying which collectors own them. Never delete arbitrary files from the shared textfile directory.
- Do not publish DNS/port inventory dashboards publicly. Bind Grafana to Tailscale or another authenticated private endpoint.
