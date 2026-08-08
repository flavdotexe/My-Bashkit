#!/bin/bash
#
# virtual-networks-monitor.sh
# Lista os dispositivos conectados as redes virtuais do host (bridges
# genericas, redes libvirt/QEMU e redes docker), com IP garantido para
# cada um, no formato Prometheus textfile collector.
#
# Nao falha se libvirt/docker nao estiverem instalados — cada fonte e
# opcional e ignorada silenciosamente se a ferramenta nao existir.

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/virtual_networks.prom"
TMP_FILE="$(mktemp)"
mkdir -p "$OUTPUT_DIR"

# Mesma correcao de inicializacao aplicada no ssh-monitor.sh:
# array vazio + "${arr[$k]:=0}" antes de incrementar.
declare -A network_count=()
device_lines=()

incr_network() {
    local net="$1"
    : "${network_count[$net]:=0}"
    network_count[$net]=$(( network_count[$net] + 1 ))
}

# 1) Bridges genericas via tabela de vizinhos (ARP/NDP) — cobre virbr0,
#    docker0, br-*, e qualquer bridge criada manualmente ou pelo
#    NetworkManager.
if command -v ip >/dev/null 2>&1; then
    while IFS= read -r bridge; do
        [[ -z "$bridge" ]] && continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            ip_addr=$(awk '{print $1}' <<< "$line")
            mac=$(grep -oP '(?<=lladdr )\S+' <<< "$line" || true)
            state=$(awk '{print $NF}' <<< "$line")
            [[ -z "$mac" || "$state" == "FAILED" ]] && continue
            device_lines+=("virtual_network_device_info{network=\"${bridge}\",ip=\"${ip_addr}\",mac=\"${mac}\",hostname=\"desconhecido\",source=\"bridge\"} 1")
            incr_network "$bridge"
        done < <(ip neigh show dev "$bridge" 2>/dev/null || true)
    done < <(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}')
fi

# 2) Redes libvirt/QEMU — leases DHCP (tem hostname, mais preciso que ARP)
if command -v virsh >/dev/null 2>&1; then
    while IFS= read -r net; do
        [[ -z "$net" ]] && continue
        while IFS= read -r lease; do
            [[ -z "$lease" ]] && continue
            [[ "$lease" == *"Expiry"* || "$lease" == "----"* ]] && continue
            mac=$(awk '{print $3}' <<< "$lease")
            ip_cidr=$(awk '{print $5}' <<< "$lease")
            ip_addr="${ip_cidr%%/*}"
            hostname=$(awk '{print $6}' <<< "$lease")
            [[ -z "$hostname" || "$hostname" == "-" ]] && hostname="desconhecido"
            [[ -z "$ip_addr" ]] && continue
            device_lines+=("virtual_network_device_info{network=\"${net}\",ip=\"${ip_addr}\",mac=\"${mac}\",hostname=\"${hostname}\",source=\"libvirt\"} 1")
            incr_network "$net"
        done < <(virsh net-dhcp-leases "$net" 2>/dev/null | tail -n +3)
    done < <(virsh net-list --name 2>/dev/null)
fi

# 3) Docker — containers e seus IPs por rede
if command -v docker >/dev/null 2>&1; then
    while IFS= read -r cid; do
        [[ -z "$cid" ]] && continue
        cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')
        while IFS= read -r netline; do
            [[ -z "$netline" ]] && continue
            netname=$(awk '{print $1}' <<< "$netline")
            ip_addr=$(awk '{print $2}' <<< "$netline")
            [[ -z "$ip_addr" ]] && continue
            device_lines+=("virtual_network_device_info{network=\"${netname}\",ip=\"${ip_addr}\",mac=\"desconhecido\",hostname=\"${cname}\",source=\"docker\"} 1")
            incr_network "$netname"
        done < <(docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{"\n"}}{{end}}' "$cid" 2>/dev/null)
    done < <(docker ps -q 2>/dev/null)
fi

{
    echo "# HELP virtual_network_device_info Dispositivo conectado a uma rede virtual (bridge, libvirt ou docker)"
    echo "# TYPE virtual_network_device_info gauge"
    for l in "${device_lines[@]:-}"; do
        [[ -n "$l" ]] && echo "$l"
    done

    echo "# HELP virtual_network_connected_devices Numero de dispositivos conectados por rede virtual"
    echo "# TYPE virtual_network_connected_devices gauge"
    for net in "${!network_count[@]}"; do
        echo "virtual_network_connected_devices{network=\"${net}\"} ${network_count[$net]}"
    done

    total=0
    for net in "${!network_count[@]}"; do
        total=$(( total + network_count[$net] ))
    done
    echo "# HELP virtual_network_connected_devices_total Numero total de dispositivos em todas as redes virtuais"
    echo "# TYPE virtual_network_connected_devices_total gauge"
    echo "virtual_network_connected_devices_total ${total}"
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
