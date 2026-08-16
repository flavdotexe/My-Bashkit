#!/bin/bash
#
# nvme-monitor.sh
# Coleta saude SMART e temperatura de todos os controladores NVMe
# detectados (/dev/nvme0, /dev/nvme1, ...), no formato Prometheus
# textfile collector.
#
# Requer smartmontools (smartctl). Usa jq se disponivel (saida mais
# confiavel via JSON); senao cai para parsing de texto.

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/nvme_health.prom"
TMP_FILE="$(mktemp)"
mkdir -p "$OUTPUT_DIR"

lines=()

if command -v smartctl >/dev/null 2>&1; then
    for dev in /dev/nvme[0-9]; do
        [[ -e "$dev" ]] || continue
        name=$(basename "$dev")

        if command -v jq >/dev/null 2>&1; then
            json=$(smartctl -a -j "$dev" 2>/dev/null || echo '{}')
            temp=$(jq -r '.temperature.current // empty' <<< "$json")
            used=$(jq -r '.nvme_smart_health_information_log.percentage_used // empty' <<< "$json")
            spare=$(jq -r '.nvme_smart_health_information_log.available_spare // empty' <<< "$json")
            spare_thresh=$(jq -r '.nvme_smart_health_information_log.available_spare_threshold // empty' <<< "$json")
            media_errors=$(jq -r '.nvme_smart_health_information_log.media_errors // empty' <<< "$json")
            crit_warn_raw=$(jq -r '.nvme_smart_health_information_log.critical_warning // 0' <<< "$json")
            power_on_hours=$(jq -r '.power_on_time.hours // empty' <<< "$json")
            model=$(jq -r '.model_name // "desconhecido"' <<< "$json")
            crit_warn=0
            [[ "$crit_warn_raw" != "0" && -n "$crit_warn_raw" ]] && crit_warn=1
        else
            text=$(smartctl -a "$dev" 2>/dev/null)
            temp=$(grep -oP 'Temperature:\s*\K[0-9]+' <<< "$text" | head -1)
            used=$(grep -oP 'Percentage Used:\s*\K[0-9]+' <<< "$text" | head -1)
            spare=$(grep -oP 'Available Spare:\s*\K[0-9]+' <<< "$text" | head -1)
            spare_thresh=$(grep -oP 'Available Spare Threshold:\s*\K[0-9]+' <<< "$text" | head -1)
            media_errors=$(grep -oP 'Media and Data Integrity Errors:\s*\K[0-9]+' <<< "$text" | head -1)
            crit_warn_raw=$(grep -oP 'Critical Warning:\s*\K0x[0-9a-fA-F]+' <<< "$text" | head -1)
            power_on_hours=$(grep -oP 'Power On Hours:\s*\K[0-9,]+' <<< "$text" | head -1 | tr -d ',')
            model=$(grep -oP 'Model Number:\s*\K.*' <<< "$text" | head -1)
            crit_warn=0
            [[ -n "$crit_warn_raw" && "$crit_warn_raw" != "0x00" ]] && crit_warn=1
        fi

        temp="${temp:-0}"; used="${used:-0}"; spare="${spare:-0}"; spare_thresh="${spare_thresh:-0}"
        media_errors="${media_errors:-0}"; power_on_hours="${power_on_hours:-0}"
        model="${model:-desconhecido}"; crit_warn="${crit_warn:-0}"

        lines+=("nvme_temperature_celsius{device=\"${name}\",model=\"${model}\"} ${temp}")
        lines+=("nvme_percentage_used{device=\"${name}\"} ${used}")
        lines+=("nvme_available_spare_percent{device=\"${name}\"} ${spare}")
        lines+=("nvme_available_spare_threshold_percent{device=\"${name}\"} ${spare_thresh}")
        lines+=("nvme_media_errors_total{device=\"${name}\"} ${media_errors}")
        lines+=("nvme_critical_warning{device=\"${name}\"} ${crit_warn}")
        lines+=("nvme_power_on_hours{device=\"${name}\"} ${power_on_hours}")
    done
fi

{
    echo "# HELP nvme_temperature_celsius Temperatura do NVMe em graus Celsius"
    echo "# TYPE nvme_temperature_celsius gauge"
    echo "# HELP nvme_percentage_used Percentual de vida util consumida do NVMe (desgaste; pode passar de 100)"
    echo "# TYPE nvme_percentage_used gauge"
    echo "# HELP nvme_available_spare_percent Percentual de blocos reserva ainda disponiveis"
    echo "# TYPE nvme_available_spare_percent gauge"
    echo "# HELP nvme_available_spare_threshold_percent Limite critico de blocos reserva definido pelo fabricante"
    echo "# TYPE nvme_available_spare_threshold_percent gauge"
    echo "# HELP nvme_media_errors_total Total de erros de midia/integridade de dados reportados"
    echo "# TYPE nvme_media_errors_total gauge"
    echo "# HELP nvme_critical_warning Indicador SMART de warning critico (0=ok, 1=alerta)"
    echo "# TYPE nvme_critical_warning gauge"
    echo "# HELP nvme_power_on_hours Horas ligadas do dispositivo"
    echo "# TYPE nvme_power_on_hours gauge"
    for l in "${lines[@]:-}"; do
        [[ -n "$l" ]] && echo "$l"
    done
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
