# Architecture

```mermaid
graph LR
 A[Admin via Tailscale] --> B[OpenSSH TCP 2222]
 C[Local test client] --> D[Loopback TCP 22]
 D --> E[Cowrie TCP 2222]
 E --> F[Persistent JSON logs]
 E --> G[nftables egress filtering]
 F -. planned .-> H[Metrics collector]
 H -. planned .-> I[Prometheus]
 I -. planned .-> J[Grafana]
```

The administrative SSH service is managed separately. The firewall rules filter new IP connections arriving from br-honeypot; they do not prove DNS or container escape containment. Keep the sensor loopback-only. Future metrics should avoid raw IP, username, password and command labels to prevent sensitive data exposure and high cardinality.
