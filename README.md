# My-Bashkit

> **Laboratório pessoal de infraestrutura Linux, automação, observabilidade, virtualização e redes.**

O **My-Bashkit** é um laboratório de infraestrutura desenvolvido em Linux para estudar, implementar e documentar conceitos de administração de sistemas, redes, virtualização, containers, monitoramento e segurança.

O projeto nasceu como uma coleção de scripts Bash para administração do Arch Linux e evoluiu para um ambiente de experimentação de infraestrutura, integrando **Prometheus, Grafana, Node Exporter, Docker, libvirt/KVM/QEMU, virt-manager, systemd e Git**.

A ideia é transformar o próprio computador em um ambiente de laboratório onde seja possível **monitorar, diagnosticar, automatizar e visualizar a infraestrutura em funcionamento**.

---

## Objetivos

* Aprender administração de sistemas Linux na prática
* Automatizar tarefas administrativas utilizando Bash
* Monitorar recursos de hardware e sistema
* Criar dashboards de observabilidade com Grafana
* Coletar métricas com Prometheus e Node Exporter
* Criar métricas customizadas através do Textfile Collector
* Monitorar redes físicas e virtuais
* Explorar virtualização com libvirt, KVM/QEMU e virt-manager
* Monitorar redes e containers Docker
* Investigar problemas de conectividade e infraestrutura
* Documentar configurações e soluções encontradas durante o laboratório
* Versionar configurações, scripts e dashboards utilizando Git

---

## Arquitetura

O laboratório utiliza diferentes camadas de infraestrutura:

```text
                         ┌──────────────────────┐
                         │       Grafana        │
                         │      Dashboards      │
                         └──────────┬───────────┘
                                    │
                                    │ PromQL
                                    │
                         ┌──────────▼───────────┐
                         │      Prometheus      │
                         │   Time Series DB     │
                         └──────────┬───────────┘
                                    │
                            scrape / metrics
                                    │
                  ┌─────────────────┴─────────────────┐
                  │                                   │
        ┌─────────▼─────────┐               ┌─────────▼─────────┐
        │   Node Exporter   │               │ Textfile Collector│
        │ Hardware / Linux  │               │ Métricas custom.  │
        └─────────┬─────────┘               └─────────┬─────────┘
                  │                                   │
                  │                         ┌─────────┼─────────┐
                  │                         │         │         │
                  │                       Bash     virsh    Docker
                  │                         │         │         │
        ┌─────────▼─────────────────────────▼─────────▼─────────▼──┐
        │                         Linux Host                       │
        │                                                           │
        │  Hardware   │   Network   │   libvirt   │   Docker       │
        │  CPU/RAM    │   Bridges   │   KVM/QEMU  │   Containers    │
        └───────────────────────────────────────────────────────────┘
```

---

# Observabilidade

A stack de monitoramento utiliza:

* **Prometheus** para coleta e armazenamento de métricas
* **Grafana** para visualização e criação de dashboards
* **Node Exporter** para métricas do sistema operacional e hardware
* **Textfile Collector** para métricas customizadas produzidas por scripts Bash

Entre as métricas monitoradas estão:

* utilização de CPU;
* utilização individual dos cores;
* memória;
* interfaces de rede;
* tráfego de rede;
* informações de hardware;
* interfaces virtuais;
* bridges;
* dispositivos conectados a redes virtuais;
* containers Docker;
* sessões SSH;
* eventos relacionados a acesso SSH.

---

# Redes virtuais

Uma das áreas do projeto é a observabilidade da infraestrutura de rede virtual criada no próprio Linux.

O laboratório consegue trabalhar com informações provenientes de:

* bridges Linux;
* redes libvirt/QEMU;
* interfaces Docker;
* hotspot;
* sessões SSH.

Para redes libvirt/QEMU, o projeto utiliza informações fornecidas pelo `virsh`, incluindo leases DHCP e dados dos dispositivos conectados.

Para containers Docker, as informações podem ser obtidas através do `docker inspect`.

Esses dados são transformados em métricas e disponibilizados ao Prometheus para posterior visualização no Grafana.

Exemplo conceitual:

```text
libvirt
   │
   ├── virbr0
   │      ├── VM
   │      │    ├── IP
   │      │    ├── MAC
   │      │    └── hostname
   │      │
   │      └── VM
   │
   └── DHCP leases
          │
          ▼
virtual-networks-monitor.sh
          │
          ▼
Prometheus Textfile Collector
          │
          ▼
Prometheus
          │
          ▼
Grafana
```

---

# Virtualização

O laboratório também é utilizado para estudar virtualização em Linux utilizando:

* **libvirt**
* **KVM/QEMU**
* **virt-manager**
* redes virtuais;
* bridges;
* DHCP leases;
* conectividade entre host e máquinas virtuais.

A virtualização é tratada como parte da infraestrutura e não como um ambiente isolado: as máquinas virtuais e suas redes podem ser integradas ao monitoramento do Prometheus e aos dashboards do Grafana.

---

# Containers

O projeto utiliza **Docker** para executar serviços de infraestrutura e observabilidade.

Exemplos:

* Prometheus
* Grafana
* Node Exporter
* containers utilizados durante os laboratórios

A integração entre Docker, redes virtuais e Prometheus permite observar não apenas o host, mas também parte da infraestrutura criada sobre ele.

---

# Automação com Bash

O Bash é utilizado para automatizar tarefas administrativas e transformar informações do sistema em dados consumíveis por outras ferramentas.

Exemplos:

* coleta de informações de rede;
* monitoramento de dispositivos;
* análise de sessões SSH;
* geração de métricas Prometheus;
* diagnóstico do sistema;
* gerenciamento de recursos;
* automação através de systemd services e timers.

Os scripts são desenvolvidos com foco em ambientes Linux.

---

# Segurança e administração

O laboratório também contém experimentos relacionados à segurança e administração de sistemas, incluindo:

* firewall com `nftables`;
* WireGuard;
* Tailscale;
* monitoramento de SSH;
* análise de logs;
* identificação de tentativas de acesso;
* troubleshooting de rede;
* administração de serviços através do systemd.

---

# Estrutura do projeto

```text
My-Bashkit/
│
├── grafana-network_dashboard/
│   ├── dashboards
│   ├── collectors
│   ├── systemd services
│   └── systemd timers
│
├── disk-space-control/
│   └── scripts para gerenciamento de espaço
│
├── thinkpad-battery-control/
│   └── scripts relacionados ao gerenciamento de bateria
│
├── security-and-automatic-update-arch/
│   └── automação e administração do Arch Linux
│
└── README.md
```

A estrutura pode mudar conforme novos laboratórios e ferramentas forem incorporados ao projeto.

## Licença

Este projeto é disponibilizado para fins de estudo, experimentação e aprendizado.
