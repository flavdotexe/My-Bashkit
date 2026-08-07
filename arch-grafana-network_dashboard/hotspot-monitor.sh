#!/bin/bash
#
# hotspot-monitor.sh
# Coleta a lista de dispositivos conectados no hotspot (AP) do host e
# escreve no formato Prometheus textfile collector.
#
# Uso: hotspot-monitor.sh <interface>   (padrao: wlan0)
#
# Funciona com hotspot criado via NetworkManager (nmcli) ou hostapd,
# desde que a interface esteja em modo AP e o "iw" esteja instalado.
# Cruza os MACs conectados com o arquivo de leases do dnsmasq (se existir)
# para obter IP e hostname.

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/hotspot_devices.prom"
TMP_FILE="$(mktemp)"
IFACE="${1:-wlan0}"

# Caminhos comuns de leases do dnsmasq; ajuste se o seu hotspot usar outro.
LEASES_CANDIDATES=(
    "/var/lib/misc/dnsmasq.leases"
    "/var/lib/NetworkManager/dnsmasq-${IFACE}.leases"
)

mkdir -p "$OUTPUT_DIR"

LEASES_FILE=""
for f in "${LEASES_CANDIDATES[@]}"; do
    [[ -f "$f" ]] && LEASES_FILE="$f" && break
done

macs=()
if command -v iw >/dev/null 2>&1; then
    mapfile -t macs < <(iw dev "$IFACE" station dump 2>/dev/null | awk '/^Station/ {print $2}')
fi

count=${#macs[@]}

{
    echo "# HELP hotspot_connected_devices Numero de dispositivos conectados ao hotspot"
    echo "# TYPE hotspot_connected_devices gauge"
    echo "hotspot_connected_devices ${count}"

    echo "# HELP hotspot_device_info Dispositivo conectado ao hotspot (valor sempre 1, use como label)"
    echo "# TYPE hotspot_device_info gauge"
    for mac in "${macs[@]}"; do
        ip="desconhecido"
        hostname="desconhecido"
        if [[ -n "$LEASES_FILE" ]]; then
            lease_line=$(grep -i "$mac" "$LEASES_FILE" | tail -1 || true)
            if [[ -n "$lease_line" ]]; then
                ip=$(awk '{print $3}' <<< "$lease_line")
                h=$(awk '{print $4}' <<< "$lease_line")
                [[ -n "$h" && "$h" != "*" ]] && hostname="$h"
            fi
        fi
        echo "hotspot_device_info{mac=\"${mac}\",ip=\"${ip}\",hostname=\"${hostname}\",iface=\"${IFACE}\"} 1"
    done
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
