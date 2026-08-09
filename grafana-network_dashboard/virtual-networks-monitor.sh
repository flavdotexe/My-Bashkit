```bash
#!/bin/bash

#
# virtual-networks-monitor.sh
#
# Lista os dispositivos conectados às redes virtuais do host
# (bridges genéricas, redes libvirt/QEMU e redes Docker),
# com IP garantido para cada um, no formato Prometheus
# textfile collector.
#
# Não falha se libvirt/docker não estiverem instalados —
# cada fonte é opcional e ignorada silenciosamente se a
# ferramenta não existir.
#

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/virtual_networks.prom"
TMP_FILE="$(mktemp)"

mkdir -p "$OUTPUT_DIR"

# ============================================================
# Estruturas de dados
# ============================================================

# Contagem de dispositivos por rede.
declare -A network_count=()

# IPs pertencentes a containers Docker.
# Usados para evitar duplicação com bridges genéricas.
declare -A docker_ips=()

# IPs pertencentes a máquinas virtuais libvirt.
# Usados para evitar duplicação com virbr0 e outras bridges.
declare -A libvirt_ips=()

# Linhas finais das métricas.
device_lines=()


# ============================================================
# Funções auxiliares
# ============================================================

incr_network() {
    local net="$1"

    : "${network_count[$net]:=0}"
    network_count[$net]=$(( network_count[$net] + 1 ))
}


# ============================================================
# 1) Docker
# ============================================================
#
# Primeiro descobrimos os containers Docker.
#
# Isso permite registrar seus IPs antes da descoberta das
# bridges, evitando que o mesmo container seja contabilizado
# novamente como "source=bridge".
#

if command -v docker >/dev/null 2>&1; then

    while IFS= read -r cid; do

        [[ -z "$cid" ]] && continue

        # Nome do container.
        cname="$(
            docker inspect \
                --format '{{.Name}}' \
                "$cid" 2>/dev/null |
            sed 's#^/##'
        )"

        while IFS= read -r netline; do

            [[ -z "$netline" ]] && continue

            netname="$(awk '{print $1}' <<< "$netline")"
            ip_addr="$(awk '{print $2}' <<< "$netline")"
            mac_addr="$(awk '{print $3}' <<< "$netline")"

            [[ -z "$netname" ]] && continue
            [[ -z "$ip_addr" ]] && continue

            # Registra o IP para impedir que a descoberta por
            # bridge contabilize esse container novamente.
            docker_ips["$ip_addr"]="$cname"

            # Se por algum motivo o MAC não estiver disponível,
            # mantém "desconhecido".
            [[ -z "$mac_addr" ]] && mac_addr="desconhecido"

            device_lines+=(
                "virtual_network_device_info{network=\"${netname}\",ip=\"${ip_addr}\",mac=\"${mac_addr}\",hostname=\"${cname}\",source=\"docker\"} 1"
            )

            incr_network "$netname"

        done < <(
            docker inspect \
                --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}} {{$v.MacAddress}}{{"\n"}}{{end}}' \
                "$cid" 2>/dev/null
        )

    done < <(
        docker ps -q 2>/dev/null
    )

fi


# ============================================================
# 2) Redes libvirt/QEMU
# ============================================================
#
# Usa os leases DHCP do libvirt.
#
# Além de obter IP/MAC/hostname, registramos cada IP em
# libvirt_ips para que ele não seja posteriormente descoberto
# novamente pela seção de bridges.
#

if command -v virsh >/dev/null 2>&1; then

    while IFS= read -r net; do

        [[ -z "$net" ]] && continue

        while IFS= read -r lease; do

            [[ -z "$lease" ]] && continue
            [[ "$lease" == *"Expiry"* ]] && continue
            [[ "$lease" == "----"* ]] && continue

            mac="$(awk '{print $3}' <<< "$lease")"

            ip_cidr="$(awk '{print $5}' <<< "$lease")"
            ip_addr="${ip_cidr%%/*}"

            hostname="$(awk '{print $6}' <<< "$lease")"

            [[ -z "$hostname" || "$hostname" == "-" ]] &&
                hostname="desconhecido"

            [[ -z "$ip_addr" ]] && continue
            [[ -z "$mac" ]] && mac="desconhecido"

            # Registra o IP como pertencente ao libvirt.
            # A seção de bridges usará isso para evitar
            # duplicação.
            libvirt_ips["$ip_addr"]="$hostname"

            device_lines+=(
                "virtual_network_device_info{network=\"${net}\",ip=\"${ip_addr}\",mac=\"${mac}\",hostname=\"${hostname}\",source=\"libvirt\"} 1"
            )

            incr_network "$net"

        done < <(
            virsh net-dhcp-leases "$net" 2>/dev/null |
            tail -n +3
        )

    done < <(
        virsh net-list --name 2>/dev/null
    )

fi


# ============================================================
# 3) Bridges genéricas
# ============================================================
#
# Cobre:
#
#   - virbr0
#   - docker0
#   - br-*
#   - bridges criadas manualmente
#   - bridges criadas pelo NetworkManager
#
# Porém, IPs já identificados pelo Docker ou pelo libvirt
# são ignorados aqui.
#
# Isso evita situações como:
#
#   virbr0 → 192.168.122.14 → desconhecido
#   default → 192.168.122.14 → DESKTOP-HCSNFEC
#
# O IP aparecerá somente pela fonte mais precisa.
#

if command -v ip >/dev/null 2>&1; then

    while IFS= read -r bridge; do

        [[ -z "$bridge" ]] && continue

        while IFS= read -r line; do

            [[ -z "$line" ]] && continue

            ip_addr="$(awk '{print $1}' <<< "$line")"

            mac_addr="$(
                grep -oP '(?<=lladdr )\S+' <<< "$line" ||
                true
            )"

            state="$(awk '{print $NF}' <<< "$line")"

            [[ -z "$ip_addr" ]] && continue
            [[ -z "$mac_addr" ]] && continue
            [[ "$state" == "FAILED" ]] && continue

            # ------------------------------------------------
            # Ignora IP já identificado pelo Docker.
            # ------------------------------------------------

            if [[ -n "${docker_ips[$ip_addr]:-}" ]]; then
                continue
            fi

            # ------------------------------------------------
            # Ignora IP já identificado pelo libvirt.
            # ------------------------------------------------

            if [[ -n "${libvirt_ips[$ip_addr]:-}" ]]; then
                continue
            fi

            # ------------------------------------------------
            # Dispositivo realmente descoberto apenas pela
            # bridge.
            # ------------------------------------------------

            device_lines+=(
                "virtual_network_device_info{network=\"${bridge}\",ip=\"${ip_addr}\",mac=\"${mac_addr}\",hostname=\"desconhecido\",source=\"bridge\"} 1"
            )

            incr_network "$bridge"

        done < <(
            ip neigh show dev "$bridge" 2>/dev/null || true
        )

    done < <(
        ip -o link show type bridge 2>/dev/null |
        awk -F': ' '{print $2}'
    )

fi


# ============================================================
# 4) Geração do arquivo Prometheus
# ============================================================

{
    echo "# HELP virtual_network_device_info Dispositivo conectado a uma rede virtual (bridge, libvirt ou docker)"
    echo "# TYPE virtual_network_device_info gauge"

    for line in "${device_lines[@]:-}"; do
        [[ -n "$line" ]] && echo "$line"
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


# ============================================================
# 5) Permissões
# ============================================================
#
# O Node Exporter roda como usuário nobody.
# O arquivo precisa ser legível por ele.
#

chmod 644 "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
```
