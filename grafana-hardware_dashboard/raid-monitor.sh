#!/bin/bash
#
# raid-monitor.sh
# Le /proc/mdstat e expoe o status de arrays RAID (mdadm) no formato
# Prometheus textfile collector.
#
# IMPORTANTE: se nao houver nenhum array RAID configurado, o script
# ainda assim emite uma linha com state="nao_configurado" em vez de
# simplesmente nao gerar nenhuma metrica — isso evita que o painel do
# Grafana mostre "No data" e, ao inves disso, mostra explicitamente que
# o RAID nao esta configurado. Quando voce configurar um array de fato,
# a linha passa a refletir o array real automaticamente.

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/raid_status.prom"
TMP_FILE="$(mktemp)"
mkdir -p "$OUTPUT_DIR"

lines=()
configured=0
array_count=0

if [[ -f /proc/mdstat ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^(md[0-9A-Za-z_]+)[[:space:]]*:[[:space:]]*(active|inactive)[[:space:]]*(\(auto-read-only\))?[[:space:]]*(raid[0-9]+|linear) ]]; then
            array="${BASH_REMATCH[1]}"
            state="${BASH_REMATCH[2]}"
            level="${BASH_REMATCH[4]}"
            configured=1
            array_count=$(( array_count + 1 ))
            devices=$(grep -oE '[a-zA-Z0-9_]+\[[0-9]+\]' <<< "$line" | wc -l)
            degraded=0
            [[ "$state" == "inactive" ]] && degraded=1
            lines+=("raid_array_info{array=\"${array}\",level=\"${level}\",state=\"${state}\"} 1")
            lines+=("raid_array_devices{array=\"${array}\"} ${devices}")
            lines+=("raid_array_degraded{array=\"${array}\"} ${degraded}")
        fi
    done < /proc/mdstat
fi

if [[ "$configured" -eq 0 ]]; then
    lines+=("raid_array_info{array=\"nenhum\",level=\"none\",state=\"nao_configurado\"} 1")
fi

{
    echo "# HELP raid_array_info Informacao de arrays RAID (mdadm). Sem RAID configurado, emite state=\"nao_configurado\" em vez de nao gerar dado nenhum."
    echo "# TYPE raid_array_info gauge"
    for l in "${lines[@]:-}"; do
        [[ -n "$l" ]] && echo "$l"
    done

    echo "# HELP raid_configured Indica se ha pelo menos um array RAID configurado (1) ou nao (0)"
    echo "# TYPE raid_configured gauge"
    echo "raid_configured ${configured}"

    echo "# HELP raid_arrays_total Numero de arrays RAID configurados"
    echo "# TYPE raid_arrays_total gauge"
    echo "raid_arrays_total ${array_count}"
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
