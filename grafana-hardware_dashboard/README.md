# Supervisório de Hardware — Arch Linux

Dashboard Grafana + coletores Prometheus para:
- CPU: uso por núcleo, uso total (gauge único), temperatura, velocidade dos fans
- Memória: uso, status de dual channel, zram
- NVMe: saúde SMART, temperatura, % de armazenamento usado
- Histórico de montagens de dispositivos e status de RAID (sem "No data" quando não há RAID)

## 1. Pré-requisitos (pacman)

```bash
sudo pacman -S prometheus node_exporter grafana lm_sensors smartmontools jq dmidecode
```

Configure o `lm_sensors` (necessário para os painéis de temperatura da
CPU e velocidade dos fans aparecerem):

```bash
sudo sensors-detect --auto
sensors   # deve listar coretemp (Intel) ou k10temp/zenpower (AMD), e
          # os sensores de fan da placa-mãe (nct6775, it87, etc.)
```

Se o `node_exporter` já estava instalado antes deste comando, reinicie-o
depois de rodar `sensors-detect` (ele detecta os módulos hwmon
automaticamente no boot/restart):

```bash
sudo systemctl restart node_exporter
```

> Se `sensors` não mostrar nada mesmo depois do `sensors-detect`, o
> hardware da sua placa-mãe pode não ser suportado pelos drivers hwmon do
> kernel — nesse caso os painéis de temperatura/fan ficam vazios (isso é
> uma limitação do driver, não do dashboard).

## 2. Habilitar o textfile collector no node_exporter

Se você já configurou isso para o supervisório de rede, pule esta etapa —
é o mesmo diretório.

```bash
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown node_exporter:node_exporter /var/lib/node_exporter/textfile_collector
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
sudo install -Dm755 memory-monitor.sh /usr/local/bin/memory-monitor.sh
sudo install -Dm755 nvme-monitor.sh /usr/local/bin/nvme-monitor.sh
sudo install -Dm755 mount-history-monitor.sh /usr/local/bin/mount-history-monitor.sh
sudo install -Dm755 raid-monitor.sh /usr/local/bin/raid-monitor.sh

sudo cp memory-monitor.service memory-monitor.timer /etc/systemd/system/
sudo cp nvme-monitor.service nvme-monitor.timer /etc/systemd/system/
sudo cp mount-history-monitor.service mount-history-monitor.timer /etc/systemd/system/
sudo cp raid-monitor.service raid-monitor.timer /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now memory-monitor.timer nvme-monitor.timer mount-history-monitor.timer raid-monitor.timer
```

Teste manualmente:
```bash
sudo /usr/local/bin/memory-monitor.sh
sudo /usr/local/bin/nvme-monitor.sh
sudo /usr/local/bin/mount-history-monitor.sh
sudo /usr/local/bin/raid-monitor.sh
cat /var/lib/node_exporter/textfile_collector/*.prom
```

## 4. Prometheus

Se você já tem o `node_exporter` como target no `prometheus.yml` (do
supervisório de rede), não precisa adicionar nada — as métricas novas
saem pelo mesmo textfile collector. Se este é seu primeiro dashboard:

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

## 5. Importar no Grafana

**Dashboards → Import** → upload de `arch-hardware-supervisorio.json` →
selecione o datasource Prometheus → escolha o **Ponto de montagem** (var
`mountpoint`, padrão `/`) para o painel de % de armazenamento do NVMe.

## O que cada seção mostra

| Seção | Painéis |
|---|---|
| 🖥️ CPU | gauge de uso total, gráfico de uso por núcleo, temperatura (hwmon), velocidade dos fans (hwmon) |
| 🧠 Memória | % usada, uso em GB (total/usada/disponível), status dual/single channel, tabela de DIMMs, taxa de compressão zram, % de zram usado, gráfico original vs comprimido |
| 💽 NVMe | temperatura, % de vida útil usada (desgaste), spare disponível, erros de mídia, gauge de % de armazenamento (capacidade), gráfico de temperatura no tempo |
| 🗄️ Montagens & RAID | histórico de montagens/desmontagens, dispositivos montados agora, status do RAID (texto, nunca "No data"), tabela de arrays RAID |

## Sobre o RAID

Você não tem RAID configurado agora — o painel **Status RAID** vai
mostrar "Não configurado" (cinza) e a tabela de arrays vai mostrar uma
linha `array=nenhum, state=nao_configurado`, em vez de aparecer vazio.
No dia em que você criar um array com `mdadm`, o script (`raid-monitor.sh`,
rodando a cada 60s) detecta automaticamente via `/proc/mdstat` e os
painéis passam a mostrar o array real — nada precisa ser reconfigurado
no dashboard.

## Sobre a heurística de Dual Channel

`memory-monitor.sh` tenta identificar o canal pelo nome do slot (ex.:
`ChannelA-DIMM0`) via `dmidecode -t memory`. Quando isso funciona, o
método é `channel_label` (confiável). Quando o BIOS não nomeia os slots
de forma clara, o script cai para uma heurística mais fraca: "2+ slots
populados = provável dual channel". Se quiser conferir manualmente:

```bash
sudo dmidecode -t memory | grep -E "Locator|Size:"
```

## Limitações conhecidas

- **NVMe**: o script assume controladores em `/dev/nvme0`, `/dev/nvme1`
  etc. (padrão do Linux). Se você tiver mais de um NVMe, todos aparecem
  automaticamente, diferenciados pelo label `device`.
- **RAID**: o parsing de `/proc/mdstat` cobre os casos comuns (raid0,
  raid1, raid5, raid6, raid10, linear). Arrays em estados incomuns podem
  não ser classificados com 100% de precisão — o essencial (existe ou não
  existe RAID) sempre funciona.
- **Histórico de montagens**: comparação de snapshots a cada 15s, então
  montagens/desmontagens muito rápidas (menos de 15s de duração) podem não
  ser capturadas.
