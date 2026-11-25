# SSH Sentinel

A local SSH deception lab using Cowrie, Docker, nftables and a separate administrative OpenSSH service. Built for defensive network monitoring and SOC practice.

## Features
- Loopback-only SSH honeypot (TCP 22 → 2222).
- Dedicated Docker bridge and host/forward egress filtering.
- Non-root, read-only container with dropped capabilities and resource limits.
- Persistent JSON events and runtime audit scripts.
- Planned Prometheus/Grafana integration.

## Setup
Requires Linux, Docker Compose, nftables, Bash and a trusted Cowrie source snapshot matching the supplied Dockerfile. Obtain source from https://github.com/cowrie/cowrie and record its revision locally. The Dockerfile is adapted from upstream; the local version override supports ZIP snapshots and is not an official release version.

If migrating an existing lab, stop its Cowrie container first. Do not delete its volumes. This Compose project uses its own volume names; existing logs are not migrated automatically. Check that TCP 22 is free and that administrative access remains available before starting.

```bash
./scripts/install.sh /path/to/cowrie-main
./scripts/start.sh
./scripts/status.sh
./scripts/logs.sh
```

Test from another host terminal (use only fictional credentials):

```bash
ssh -p 22 -o PubkeyAuthentication=no -o UserKnownHostsFile=/dev/null root@127.0.0.1
```

Audit with authorized local targets, e.g. `./scripts/security-audit.sh 172.22.0.1:2222`. Adapt the address to your actual bridge. Compare firewall counters before and after. A timeout alone does not prove filtering.

## Safety and limitations
This is a local lab, not a production deployment. DNS forwarding, full runtime isolation and firewall persistence are not yet validated. Do not publish the port or forward it on a router. Docker restart is deliberately disabled until firewall ordering is implemented. Start through the script after reboot. Never automatically apply the reference OpenSSH configuration; test key-based access and restrict TCP 2222 to your administrative VPN first. Do not flush existing nftables rules. Never commit captured credentials, session recordings or private keys.

## Roadmap
- DNS isolation and persistence tests
- JSON event collector with bounded metric labels
- Prometheus counters and Grafana dashboard

## Attribution
Cowrie is an upstream BSD-3-Clause project by Michel Oosterhof and contributors. See https://github.com/cowrie/cowrie for its license and source. The included Dockerfile retains upstream attribution; the Compose file is adapted from upstream. Preserve upstream license notices when redistributing.
