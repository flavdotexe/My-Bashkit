#!/bin/bash
#
# ssh-monitor.sh
# Coleta metricas de tentativas de login SSH (brute force / possivel DDoS)
# e escreve no formato Prometheus textfile collector.
#
# Requer: journalctl (systemd), sshd logando via journal (padrao no Arch).
#
# Instalacao:
#   sudo install -Dm755 ssh-monitor.sh /usr/local/bin/ssh-monitor.sh
#   Use junto com o timer systemd (ssh-monitor.timer) incluido no pacote.

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/ssh_security.prom"
TMP_FILE="$(mktemp)"
WINDOW_MINUTES=5

mkdir -p "$OUTPUT_DIR"

since="$(date -d "-${WINDOW_MINUTES} minutes" '+%Y-%m-%d %H:%M:%S')"

declare -A failed_by_ip
total_failed=0

# Tentativas de senha invalida (usuario existente ou nao)
while IFS= read -r line; do
    ip=$(grep -oP '(?<=from )\d+\.\d+\.\d+\.\d+' <<< "$line" || true)
    if [[ -n "$ip" ]]; then
        failed_by_ip["$ip"]=$(( ${failed_by_ip["$ip"]:-0} + 1 ))
        total_failed=$(( total_failed + 1 ))
    fi
done < <(journalctl -u sshd --since "$since" -o cat 2>/dev/null | grep "Failed password" || true)

# Todas as conexoes recebidas na porta SSH (indicador de varredura/DDoS,
# nao apenas tentativas de login com usuario/senha)
total_connections=$(journalctl -u sshd --since "$since" -o cat 2>/dev/null | grep -c "Connection from" || echo 0)

# IPs banidos pelo fail2ban, se instalado (opcional, nao falha se ausente)
banned_count=0
if command -v fail2ban-client >/dev/null 2>&1; then
    banned_count=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | wc -l || echo 0)
fi

{
    echo "# HELP ssh_failed_login_attempts_total Tentativas de login SSH falhas por IP na janela de ${WINDOW_MINUTES} min"
    echo "# TYPE ssh_failed_login_attempts_total gauge"
    for ip in "${!failed_by_ip[@]}"; do
        echo "ssh_failed_login_attempts_total{ip=\"${ip}\"} ${failed_by_ip[$ip]}"
    done

    echo "# HELP ssh_failed_login_total Total de tentativas de login SSH falhas na janela"
    echo "# TYPE ssh_failed_login_total gauge"
    echo "ssh_failed_login_total ${total_failed}"

    echo "# HELP ssh_connection_attempts_total Total de conexoes recebidas na porta SSH na janela (indicador de scan/DDoS)"
    echo "# TYPE ssh_connection_attempts_total gauge"
    echo "ssh_connection_attempts_total ${total_connections}"

    echo "# HELP ssh_unique_attacker_ips Numero de IPs unicos com falha de login na janela"
    echo "# TYPE ssh_unique_attacker_ips gauge"
    echo "ssh_unique_attacker_ips ${#failed_by_ip[@]}"

    echo "# HELP ssh_fail2ban_banned_ips IPs atualmente banidos pelo fail2ban na jail sshd"
    echo "# TYPE ssh_fail2ban_banned_ips gauge"
    echo "ssh_fail2ban_banned_ips ${banned_count}"
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
