# Supervisório de Rede — Arch Linux

Pacote com dashboard Grafana + coletores Prometheus para monitorar:
- Tentativas de brute force / possível DDoS no SSH
- Dispositivos conectados no hotspot do host
- Consumo de banda (GB download/upload) — resumo e gráficos

## 1. Pré-requisitos (pacman)

```bash
sudo pacman -S prometheus node_exporter grafana iw
# opcional, mas recomendado para banir IPs automaticamente:
sudo pacman -S fail2ban
```

## 2. Habilitar o textfile collector no node_exporter

```bash
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown node_exporter:node_exporter /var/lib/node_exporter/textfile_collector
```

Edite o serviço do node_exporter para incluir a flag do textfile collector:

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
```

Edite `hotspot-monitor.service` e troque `wlan0` pela interface real do seu
hotspot (confira com `iw dev` ou `nmcli device`).

```bash
sudo cp ssh-monitor.service ssh-monitor.timer /etc/systemd/system/
sudo cp hotspot-monitor.service hotspot-monitor.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ssh-monitor.timer hotspot-monitor.timer
```

Teste manualmente:
```bash
sudo /usr/local/bin/ssh-monitor.sh
sudo /usr/local/bin/hotspot-monitor.sh wlan0
cat /var/lib/node_exporter/textfile_collector/*.prom
```

> **Nota sobre o sshd**: os scripts leem `journalctl -u sshd`. Se seu sshd
> roda como `sshd.service` mas o log aparece em outro unit (ex.: alguns
> setups usam socket activation `sshd.socket` + `sshd@.service`), ajuste
> o `-u sshd` no script para o nome correto do seu sistema.

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

1. Acesse o Grafana → **Connections → Data sources** → adicione o
   Prometheus (`http://localhost:9090`).
2. Vá em **Dashboards → Import**.
3. Faça upload de `arch-network-supervisorio.json`.
4. Selecione seu datasource Prometheus quando solicitado.
5. No topo do dashboard, escolha a variável **interface** (ex.: `enp3s0`,
   `wlan0`) — é ela que alimenta os painéis de GB e os gráficos.

## O que cada seção mostra

| Seção | Painéis |
|---|---|
| 🔒 Segurança SSH | tentativas falhas, IPs únicos atacantes, conexões na porta 22 (indicador de DDoS/scan), IPs banidos pelo fail2ban, gráfico de tentativas ao longo do tempo, tabela top 10 IPs |
| 📶 Hotspot | contagem de dispositivos conectados agora, tabela com MAC/IP/hostname, histórico de dispositivos conectados |
| 💾 Consumo (GB) | download/upload total nas últimas 24h, gauges do período selecionado no dashboard |
| 📈 Gráficos | taxa de download/upload em Mbps em tempo real, consumo acumulado em GB no período |

## Ajustar sensibilidade de brute force/DDoS

Os thresholds (verde/laranja/vermelho) nos painéis de SSH estão em:
- Tentativas falhas: 5 min → alerta em 5, crítico em 15
- Conexões na porta SSH: alerta em 30, crítico em 100

Edite esses valores direto no JSON (`thresholds.steps`) ou pela UI do
Grafana (Edit panel → Thresholds) conforme o perfil de tráfego da sua rede.
