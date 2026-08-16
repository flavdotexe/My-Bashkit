```bash
#!/bin/bash

#
# ssh-monitor.sh
# Coleta métricas de segurança SSH:
# - Tentativas de login SSH falhas
# - Conexões SSH recebidas
# - IPs banidos pelo Fail2Ban
# - Sessões SSH atualmente ativas, com usuário, IP e TTY
#
# Saída no formato Prometheus Textfile Collector.
#
# Instalação:
# sudo install -Dm755 ssh-monitor.sh /usr/local/bin/ssh-monitor.sh
#
# Uso:
# ssh-monitor.service + ssh-monitor.timer
#

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/ssh_security.prom"
TMP_FILE="$(mktemp)"
WINDOW_MINUTES=5

mkdir -p "$OUTPUT_DIR"

# Remove o arquivo temporário caso o script seja interrompido.
trap 'rm -f "$TMP_FILE"' EXIT

since="$(date -d "-${WINDOW_MINUTES} minutes" '+%Y-%m-%d %H:%M:%S')"

# ---------------------------------------------------------------------
# TENTATIVAS DE LOGIN SSH FALHAS
# ---------------------------------------------------------------------

declare -A failed_by_ip=()
total_failed=0

while IFS= read -r line; do

    # Extrai IPv4 depois de "from".
    # Exemplo:
    # Failed password for invalid user root from 192.168.1.50 ...
    ip=$(grep -oP '(?<=from )\d+\.\d+\.\d+\.\d+' <<< "$line" || true)

    if [[ -n "$ip" ]]; then
        : "${failed_by_ip[$ip]:=0}"
        failed_by_ip[$ip]=$(( failed_by_ip[$ip] + 1 ))
        total_failed=$(( total_failed + 1 ))
    fi

done < <(
    journalctl \
        -u sshd \
        --since "$since" \
        -o cat 2>/dev/null |
        grep "Failed password" || true
)

# ---------------------------------------------------------------------
# CONEXÕES SSH RECEBIDAS
# ---------------------------------------------------------------------

total_connections="$(
    journalctl \
        -u sshd \
        --since "$since" \
        -o cat 2>/dev/null |
        grep -c "Connection from" || true
)"

# ---------------------------------------------------------------------
# FAIL2BAN
# ---------------------------------------------------------------------

banned_count=0

if command -v fail2ban-client >/dev/null 2>&1; then

    banned_count="$(
        fail2ban-client status sshd 2>/dev/null |
        grep "Banned IP list" |
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' |
        wc -l || true
    )"

fi

# ---------------------------------------------------------------------
# SESSÕES SSH ATIVAS
# ---------------------------------------------------------------------

declare -A session_seen=()
session_lines=()
session_count=0

while IFS= read -r wline; do

    [[ -z "$wline" ]] && continue

    # who normalmente retorna algo como:
    #
    # fl4v1c0r3 pts/0 2026-08-11 17:55 (192.168.122.99)
    #
    # Extrai o conteúdo entre parênteses.
    ip="$(
    grep -oP '(?<=\()\d+\.\d+\.\d+\.\d+(?=\))' <<< "$wline" || true
)"

[[ -z "$ip" ]] && continue

    user="$(awk '{print $1}' <<< "$wline")"
    tty="$(awk '{print $2}' <<< "$wline")"

    key="${user}:${tty}"

    : "${session_seen[$key]:=0}"

    if [[ "${session_seen[$key]}" -eq 0 ]]; then

        session_seen[$key]=1

        session_lines+=(
            "ssh_active_session_info{user=\"${user}\",ip=\"${ip}\",tty=\"${tty}\"} 1"
        )

        session_count=$(( session_count + 1 ))

    fi

done < <(who 2>/dev/null || true)

# ---------------------------------------------------------------------
# GERA MÉTRICAS PROMETHEUS
# ---------------------------------------------------------------------

{
    echo "# HELP ssh_failed_login_attempts_total Tentativas de login SSH falhas por IP na janela de ${WINDOW_MINUTES} min"
    echo "# TYPE ssh_failed_login_attempts_total gauge"

    for ip in "${!failed_by_ip[@]}"; do
        echo "ssh_failed_login_attempts_total{ip=\"${ip}\"} ${failed_by_ip[$ip]}"
    done


    echo "# HELP ssh_failed_login_total Total de tentativas de login SSH falhas na janela"
    echo "# TYPE ssh_failed_login_total gauge"

    echo "ssh_failed_login_total ${total_failed}"


    echo "# HELP ssh_connection_attempts_total Total de conexões recebidas na porta SSH na janela (indicador de scan/DDoS)"
    echo "# TYPE ssh_connection_attempts_total gauge"

    echo "ssh_connection_attempts_total ${total_connections}"


    echo "# HELP ssh_unique_attacker_ips Número de IPs únicos com falha de login na janela"
    echo "# TYPE ssh_unique_attacker_ips gauge"

    echo "ssh_unique_attacker_ips ${#failed_by_ip[@]}"


    echo "# HELP ssh_fail2ban_banned_ips IPs atualmente banidos pelo Fail2Ban na jail sshd"
    echo "# TYPE ssh_fail2ban_banned_ips gauge"

    echo "ssh_fail2ban_banned_ips ${banned_count}"


    echo "# HELP ssh_active_session_info Sessão SSH autenticada e ativa agora (user, ip, tty)"
    echo "# TYPE ssh_active_session_info gauge"

    for line in "${session_lines[@]:-}"; do
        [[ -n "$line" ]] && echo "$line"
    done


    echo "# HELP ssh_active_sessions_total Número de sessões SSH autenticadas ativas agora"
    echo "# TYPE ssh_active_sessions_total gauge"

    echo "ssh_active_sessions_total ${session_count}"

} > "$TMP_FILE"

# ---------------------------------------------------------------------
# PUBLICA O ARQUIVO ATOMICAMENTE
# ---------------------------------------------------------------------

mv "$TMP_FILE" "$OUTPUT_FILE"

chmod 644 "$OUTPUT_FILE"

trap - EXIT
```
