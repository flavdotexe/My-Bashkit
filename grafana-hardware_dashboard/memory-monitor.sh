#!/bin/bash
#
# memory-monitor.sh
# Coleta status de dual channel (heuristica via dmidecode) e estatisticas
# de zram, no formato Prometheus textfile collector.
#
# Requer dmidecode (para dual channel) — se ausente, essa parte e pulada
# sem falhar o script. zram e lido direto de /sys/block/zram*, sem
# dependencias externas.

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/memory_extra.prom"
TMP_FILE="$(mktemp)"
mkdir -p "$OUTPUT_DIR"

dimm_lines=()
populated_slots=0
total_slots=0
declare -A channel_labels=()

if command -v dmidecode >/dev/null 2>&1; then
    while IFS='|' read -r locator size speed manufacturer part; do
        [[ -z "$locator" ]] && continue
        total_slots=$(( total_slots + 1 ))
        if [[ -n "$size" && "$size" != "No Module Installed" ]]; then
            populated_slots=$(( populated_slots + 1 ))
            manufacturer="${manufacturer:-desconhecido}"
            part="${part:-desconhecido}"
            speed="${speed:-desconhecido}"
            dimm_lines+=("memory_dimm_info{locator=\"${locator}\",size=\"${size}\",speed=\"${speed}\",manufacturer=\"${manufacturer}\",part_number=\"${part}\"} 1")

            # Tenta extrair o rotulo do canal a partir do nome do slot
            # (ex.: "ChannelA-DIMM0", "DIMM_A1" etc.)
            chan=$(grep -oP '(?i)channel[_-]?[A-Za-z0-9]|DIMM_?[A-Za-z]' <<< "$locator" | head -1)
            [[ -n "$chan" ]] && channel_labels["$chan"]=1
        fi
    done < <(
        dmidecode -t memory 2>/dev/null | awk '
            BEGIN { in_dev=0; locator=""; size=""; speed=""; manu=""; part="" }
            /^Memory Device$/ { in_dev=1; locator=""; size=""; speed=""; manu=""; part=""; next }
            in_dev && /^$/ {
                if (locator != "") printf "%s|%s|%s|%s|%s\n", locator, size, speed, manu, part
                in_dev=0; next
            }
            in_dev && /Locator:/ && $0 !~ /Bank Locator/ { sub(/^[ \t]*Locator:[ \t]*/,""); locator=$0 }
            in_dev && /^[ \t]*Size:/ { sub(/^[ \t]*Size:[ \t]*/,""); size=$0 }
            in_dev && /Speed:/ && $0 !~ /Configured/ { sub(/^[ \t]*Speed:[ \t]*/,""); speed=$0 }
            in_dev && /Manufacturer:/ { sub(/^[ \t]*Manufacturer:[ \t]*/,""); manu=$0 }
            in_dev && /Part Number:/ { sub(/^[ \t]*Part Number:[ \t]*/,""); part=$0 }
        '
    )
fi

# Heuristica de dual channel:
# - se conseguimos identificar rotulos de canal distintos (ex.: A e B) em
#   pelo menos 2 slots populados -> method="channel_label" (mais confiavel)
# - senao, caimos para "populated_slots >= 2" como aproximacao
dual_channel=0
method="heuristic_slot_count"
if [[ ${#channel_labels[@]} -ge 2 ]]; then
    dual_channel=1
    method="channel_label"
elif [[ "$populated_slots" -ge 2 ]]; then
    dual_channel=1
fi

# --- zram ---
zram_lines=()
for zdev in /sys/block/zram*; do
    [[ -d "$zdev" ]] || continue
    name=$(basename "$zdev")
    disksize=$(cat "$zdev/disksize" 2>/dev/null || echo 0)
    orig=0; compr=0; mem_used=0
    if [[ -f "$zdev/mm_stat" ]]; then
        read -r orig compr mem_used _ < "$zdev/mm_stat"
    fi
    ratio="0"
    [[ "$compr" -gt 0 ]] 2>/dev/null && ratio=$(awk -v o="$orig" -v c="$compr" 'BEGIN{ if (c>0) printf "%.2f", o/c; else print "0" }')
    used_pct="0"
    [[ "$disksize" -gt 0 ]] 2>/dev/null && used_pct=$(awk -v u="$mem_used" -v d="$disksize" 'BEGIN{ if (d>0) printf "%.2f", (u/d)*100; else print "0" }')

    zram_lines+=("zram_device_original_bytes{device=\"${name}\"} ${orig}")
    zram_lines+=("zram_device_compressed_bytes{device=\"${name}\"} ${compr}")
    zram_lines+=("zram_device_mem_used_bytes{device=\"${name}\"} ${mem_used}")
    zram_lines+=("zram_device_disksize_bytes{device=\"${name}\"} ${disksize}")
    zram_lines+=("zram_device_compression_ratio{device=\"${name}\"} ${ratio}")
    zram_lines+=("zram_device_used_percent{device=\"${name}\"} ${used_pct}")
done

{
    echo "# HELP memory_dimm_info Modulo de memoria instalado (locator, size, speed, manufacturer, part_number)"
    echo "# TYPE memory_dimm_info gauge"
    for l in "${dimm_lines[@]:-}"; do
        [[ -n "$l" ]] && echo "$l"
    done

    echo "# HELP memory_populated_slots Numero de slots de memoria com modulo instalado"
    echo "# TYPE memory_populated_slots gauge"
    echo "memory_populated_slots ${populated_slots}"

    echo "# HELP memory_total_slots Numero total de slots de memoria (ocupados ou nao)"
    echo "# TYPE memory_total_slots gauge"
    echo "memory_total_slots ${total_slots}"

    echo "# HELP memory_dual_channel_active Indica dual channel ativo (1) ou single channel (0). Heuristica best-effort — confirme com 'dmidecode -t memory' se tiver duvida."
    echo "# TYPE memory_dual_channel_active gauge"
    echo "memory_dual_channel_active{method=\"${method}\"} ${dual_channel}"

    echo "# HELP zram_device_original_bytes Tamanho original (nao comprimido) dos dados no zram"
    echo "# TYPE zram_device_original_bytes gauge"
    echo "# HELP zram_device_compressed_bytes Tamanho comprimido dos dados no zram"
    echo "# TYPE zram_device_compressed_bytes gauge"
    echo "# HELP zram_device_mem_used_bytes Memoria RAM real usada pelo zram (dados + overhead)"
    echo "# TYPE zram_device_mem_used_bytes gauge"
    echo "# HELP zram_device_disksize_bytes Tamanho configurado do dispositivo zram"
    echo "# TYPE zram_device_disksize_bytes gauge"
    echo "# HELP zram_device_compression_ratio Taxa de compressao (original/comprimido)"
    echo "# TYPE zram_device_compression_ratio gauge"
    echo "# HELP zram_device_used_percent Percentual do zram configurado atualmente em uso"
    echo "# TYPE zram_device_used_percent gauge"
    for l in "${zram_lines[@]:-}"; do
        [[ -n "$l" ]] && echo "$l"
    done
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
