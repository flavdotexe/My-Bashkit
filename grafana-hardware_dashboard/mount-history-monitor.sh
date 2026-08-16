#!/bin/bash
#
# mount-history-monitor.sh
# Detecta montagens e desmontagens de dispositivos reais (comparando
# snapshots sucessivos de /proc/mounts) e mantem um historico persistente,
# expondo os eventos mais recentes no formato Prometheus textfile
# collector.

set -euo pipefail

STATE_DIR="/var/lib/node_exporter/mount_history"
SNAPSHOT_FILE="${STATE_DIR}/current_mounts.tsv"
HISTORY_FILE="${STATE_DIR}/history.log"
OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/mount_history.prom"
TMP_FILE="$(mktemp)"
MAX_HISTORY=500
MAX_EXPOSED=25

mkdir -p "$STATE_DIR" "$OUTPUT_DIR"
touch "$SNAPSHOT_FILE" "$HISTORY_FILE"

# Apenas dispositivos reais (/dev/...), ignora pseudo-fs (proc, sysfs,
# tmpfs, cgroup, etc.)
current=$(awk '$1 ~ /^\/dev\// {print $1"\t"$2"\t"$3}' /proc/mounts | sort)
prev=$(cat "$SNAPSHOT_FILE")
now_ts=$(date +%s)

while IFS=$'\t' read -r dev mp fstype; do
    [[ -z "$dev" ]] && continue
    line="${dev}"$'\t'"${mp}"$'\t'"${fstype}"
    if ! grep -qxF "$line" <<< "$prev"; then
        printf '%s\tmount\t%s\t%s\t%s\n' "$now_ts" "$dev" "$mp" "$fstype" >> "$HISTORY_FILE"
    fi
done <<< "$current"

while IFS=$'\t' read -r dev mp fstype; do
    [[ -z "$dev" ]] && continue
    line="${dev}"$'\t'"${mp}"$'\t'"${fstype}"
    if ! grep -qxF "$line" <<< "$current"; then
        printf '%s\tumount\t%s\t%s\t%s\n' "$now_ts" "$dev" "$mp" "$fstype" >> "$HISTORY_FILE"
    fi
done <<< "$prev"

echo "$current" > "$SNAPSHOT_FILE"

# Mantem o historico limitado em disco
tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"

current_count=$(grep -c . <<< "$current" 2>/dev/null || echo 0)
[[ -z "$current" ]] && current_count=0
total_events=$(wc -l < "$HISTORY_FILE" | tr -d ' ')

{
    echo "# HELP mount_event_info Evento de montagem/desmontagem detectado (valor = timestamp unix * 1000, em ms)"
    echo "# TYPE mount_event_info gauge"
    tail -n "$MAX_EXPOSED" "$HISTORY_FILE" | while IFS=$'\t' read -r ts action dev mp fstype; do
        [[ -z "$ts" ]] && continue
        ts_ms=$(( ts * 1000 ))
        echo "mount_event_info{action=\"${action}\",device=\"${dev}\",mountpoint=\"${mp}\",fstype=\"${fstype}\"} ${ts_ms}"
    done

    echo "# HELP mount_events_total Numero total de eventos de montagem/desmontagem registrados no historico"
    echo "# TYPE mount_events_total gauge"
    echo "mount_events_total ${total_events:-0}"

    echo "# HELP mount_currently_mounted_devices Numero de dispositivos reais atualmente montados"
    echo "# TYPE mount_currently_mounted_devices gauge"
    echo "mount_currently_mounted_devices ${current_count}"
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
