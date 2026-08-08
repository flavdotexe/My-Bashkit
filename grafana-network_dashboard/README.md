# Supervisório de Rede — Arch Linux

Pacote com dashboard Grafana + coletores Prometheus para:
- Tentativas de brute force / possível DDoS no SSH (+ sessões SSH ativas)
- Governança de dispositivos: **hotspot**, **redes virtuais** (bridge/libvirt/docker) e **SSH**, todos com IP
- Consumo de banda (GB download/upload) — resumo e gráficos

## O que mudou nesta versão

1. **Correção do `ssh-monitor.sh`**: o array associativo `failed_by_ip` era
   incrementado com `${arr["$ip"]:-0}`, que só resolve um valor padrão na
   *leitura* — a chave nunca era criada antes disso. Sob `set -u` isso é
   frágil. Agora cada chave é inicializada explicitamente com
   `: "${arr[$k]:=0}"` (atribuição, não só leitura) antes de qualquer
   incremento. O mesmo padrão foi aplicado em `virtual-networks-monitor.sh`
   e no controle de sessões SSH.
2. **IP garantido em todos os dispositivos do hotspot**: `hotspot-monitor.sh`
   agora tenta primeiro o lease do dnsmasq e, se não encontrar, cai para a
   tabela ARP/vizinhos da interface (`ip neigh`) — então praticamente todo
   dispositivo conectado aparece com IP.
3. **Novo script `virtual-networks-monitor.sh`**: lista dispositivos em
   bridges genéricas (`virbr0`, `docker0`, `br-*`, etc. via `ip neigh`),
   em redes libvirt/QEMU (via `virsh net-dhcp-leases`, com hostname) e em
   redes Docker (via `docker inspect`). Cada fonte é opcional — o script
   não falha se `virsh`/`docker` não estiverem instalados.
4. **Novo bloco no `ssh-monitor.sh`**: sessões SSH autenticadas e ativas
   agora aparecem com usuário, IP de origem e TTY (via `who`).
5. **Dashboard**: nova seção "🌐 Governança de Dispositivos" reunindo as
   três fontes (hotspot / redes virtuais / SSH) em stats + tabelas lado a
   lado, além de um gráfico histórico combinando as três.

## 1. Pré-requisitos (pacman)

```bash
sudo pacman -S prometheus node_exporter grafana iw
# opcional, recomendado:
sudo pacman -S fail2ban
# opcional, só se você usa essas tecnologias:
sudo pacman -S libvirt        # para virsh
# docker via AUR/repos oficiais, se usar containers
```

## 2. Habilitar o textfile collector no node_exporter

```bash
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown node_exporter:node_exporter /var/lib/node_exporter/textfile_collector
```

```bash
sudo systemctl edit node_exporter
```

Adicione:
```ini
[Service]
ExecStart=
ExecStart=/usr/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart node_exporter
```

## 3. Instalar os scripts coletores

```bash
sudo install -Dm755 ssh-monitor.sh /usr/local/bin/ssh-monitor.sh
sudo install -Dm755 hotspot-monitor.sh /usr/local/bin/hotspot-monitor.sh
sudo install -Dm755 virtual-networks-monitor.sh /usr/local/bin/virtual-networks-monitor.sh
```

Edite `hotspot-monitor.service` e troque `wlan0` pela interface real do seu
hotspot (confira com `iw dev` ou `nmcli device`).

```bash
sudo cp ssh-monitor.service ssh-monitor.timer /etc/systemd/system/
sudo cp hotspot-monitor.service hotspot-monitor.timer /etc/systemd/system/
sudo cp virtual-networks-monitor.service virtual-networks-monitor.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ssh-monitor.timer hotspot-monitor.timer virtual-networks-monitor.timer
```

Teste manualmente:
```bash
sudo /usr/local/bin/ssh-monitor.sh
sudo /usr/local/bin/hotspot-monitor.sh wlan0
sudo /usr/local/bin/virtual-networks-monitor.sh
cat /var/lib/node_exporter/textfile_collector/*.prom
```

> **Nota sobre o sshd**: os scripts leem `journalctl -u sshd`. Se seu sshd
> aparece em outro unit no seu sistema (ex.: `sshd@.service` com socket
> activation), ajuste o `-u sshd` no script.
>
> **Nota sobre permissões**: os timers rodam como root por padrão, o que é
> necessário para `iw dev` (station dump), `virsh` e `docker inspect`.

## 4. Configurar o Prometheus

Em `/etc/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'node_exporter'
    scrape_interval: 15s
    static_configs:
      - targets: ['localhost:9100']
```

```bash
sudo systemctl enable --now prometheus
sudo systemctl restart prometheus
```

## 5. Importar o dashboard no Grafana

1. **Connections → Data sources** → adicione o Prometheus (`http://localhost:9090`).
2. **Dashboards → Import** → upload de `arch-network-supervisorio.json`.
3. Selecione seu datasource Prometheus quando solicitado.
4. No topo do dashboard: escolha a variável **interface** (para os painéis
   de GB) e, opcionalmente, filtre **Rede virtual** (`vnet`) para focar em
   uma bridge/rede específica nas tabelas de governança.

## O que cada seção mostra

| Seção | Painéis |
|---|---|
| 🔒 Segurança SSH | tentativas falhas, IPs únicos atacantes, conexões na porta 22 (DDoS/scan), IPs banidos (fail2ban), gráfico ao longo do tempo, tabela top 10 IPs |
| 🌐 Governança de Dispositivos | contagem hotspot / redes virtuais / sessões SSH ativas, tabela hotspot (MAC/IP/hostname), tabela redes virtuais (rede/IP/MAC/hostname/origem), tabela sessões SSH (usuário/IP/TTY), histórico combinado |
| 💾 Consumo (GB) | download/upload total nas últimas 24h, gauges do período selecionado no dashboard |
| 📈 Gráficos | taxa de download/upload em Mbps em tempo real, consumo acumulado em GB no período |

## Fontes de IP por categoria de dispositivo

| Categoria | Fonte primária | Fallback |
|---|---|---|
| Hotspot | lease do dnsmasq | tabela ARP/vizinhos da interface (`ip neigh`) |
| Bridges genéricas | tabela ARP/NDP (`ip neigh`) | — |
| Libvirt/QEMU | `virsh net-dhcp-leases` (inclui hostname) | — |
| Docker | `docker inspect` por container | — |
| SSH | `who` (sessões autenticadas com host remoto) | — |

## Ajustar sensibilidade de brute force/DDoS

Thresholds nos painéis de SSH:
- Tentativas falhas: 5 min → alerta em 5, crítico em 15
- Conexões na porta SSH: alerta em 30, crítico em 100

Edite `thresholds.steps` no JSON ou pela UI (Edit panel → Thresholds)
conforme o perfil de tráfego da sua rede.
