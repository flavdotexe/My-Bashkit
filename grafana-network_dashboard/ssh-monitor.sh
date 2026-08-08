#!/bin/bash
#
# ssh-monitor.sh
# Coleta metricas de tentativas de login SSH (brute force / possivel DDoS)
# e sessoes SSH atualmente ativas (autenticadas), com IP de origem,
# no formato Prometheus textfile collector.
#
# Instalacao:
#   sudo install -Dm755 ssh-monitor.sh /usr/local/bin/ssh-monitor.sh
#   Use junto com ssh-monitor.service + ssh-monitor.timer (systemd).

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${OUTPUT_DIR}/ssh_security.prom"
TMP_FILE="$(mktemp)"
WINDOW_MINUTES=5

mkdir -p "$OUTPUT_DIR"

since="$(date -d "-${WINDOW_MINUTES} minutes" '+%Y-%m-%d %H:%M:%S')"

# ---------------------------------------------------------------------
# CORREÇÃO: inicialização do array associativo.
# Antes: "${failed_by_ip["$ip"]:-0}" só resolvia o default no momento da
# leitura, sem nunca *criar* a chave — sob `set -u` isso é frágil e pode
# estourar "unbound variable" dependendo da versão do bash.
# Agora: array é declarado vazio explicitamente e cada chave é
# inicializada com "${arr[$k]:=0}" (operador de atribuição, não só
# leitura) ANTES de qualquer incremento. Isso garante que a chave sempre
# exista antes de ser referenciada.
# ---------------------------------------------------------------------
declare -A failed_by_ip=()
total_failed=0

while IFS= read -r line; do
    ip=$(grep -oP '(?<=from )\d+\.\d+\.\d+\.\d+' <<< "$line" || true)
    if [[ -n "$ip" ]]; then
        : "${failed_by_ip[$ip]:=0}"
        failed_by_ip[$ip]=$(( failed_by_ip[$ip] + 1 ))
        total_failed=$(( total_failed + 1 ))
    fi
done < <(journalctl -u sshd --since "$since" -o cat 2>/dev/null | grep "Failed password" || true)

total_connections=$(journalctl -u sshd --since "$since" -o cat 2>/dev/null | grep -c "Connection from" || echo 0)

banned_count=0
if command -v fail2ban-client >/dev/null 2>&1; then
    banned_count=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | wc -l || echo 0)
fi

# --- Sessões SSH ativas (autenticadas), com IP de origem ---
# Mesmo cuidado de inicialização aplicado aqui.
declare -A session_seen=()
session_lines=()
session_count=0

while IFS= read -r wline; do
    [[ -z "$wline" ]] && continue
    ip=$(grep -oP '(?<=\()[^)]+' <<< "$wline" || true)
    [[ -z "$ip" ]] && continue   # sessao local (sem host remoto) nao e SSH
    user=$(awk '{print $1}' <<< "$wline")
    tty=$(awk '{print $2}' <<< "$wline")
    key="${user}:${tty}"
    : "${session_seen[$key]:=0}"
    if [[ "${session_seen[$key]}" -eq 0 ]]; then
        session_seen[$key]=1
        session_lines+=("ssh_active_session_info{user=\"${user}\",ip=\"${ip}\",tty=\"${tty}\"} 1")
        session_count=$(( session_count + 1 ))
    fi
done < <(who 2>/dev/null || true)

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

    echo "# HELP ssh_active_session_info Sessao SSH autenticada e ativa agora (user, ip, tty)"
    echo "# TYPE ssh_active_session_info gauge"
    for l in "${session_lines[@]:-}"; do
        [[ -n "$l" ]] && echo "$l"
    done

    echo "# HELP ssh_active_sessions_total Numero de sessoes SSH autenticadas ativas agora"
    echo "# TYPE ssh_active_sessions_total gauge"
    echo "ssh_active_sessions_total ${session_count}"
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"
