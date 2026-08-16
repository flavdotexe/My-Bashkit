#!/usr/bin/env bash
# =============================================================================
# arch-guardian :: modules/network.sh
# Estado de rede via `ss -tulpn`, usado para comparar portas/serviços
# escutando antes e depois de uma atualização.
# =============================================================================

net::listeners() {
    # -n usa sudo se disponível sem senha (para resolver o PID/processo);
    # se não houver sudo sem senha, cai para o `ss` normal do usuário.
    if sudo -n true 2>/dev/null; then
        sudo ss -tulpn 2>/dev/null
    else
        ss -tulpn 2>/dev/null
    fi
}

net::listener_count() {
    net::listeners | tail -n +2 | grep -c .
}

net::snapshot() {
    local tag="$1"
    net::listeners > "$STATE_DIR/net_${tag}.txt" 2>/dev/null
}

net::diff_report() {
    local before="$STATE_DIR/net_before.txt"
    local after="$STATE_DIR/net_after.txt"
    [[ -f "$before" && -f "$after" ]] || { echo "(sem dados de comparação)"; return; }

    echo "# Portas/serviços que pararam de escutar após a atualização:"
    comm -23 <(tail -n +2 "$before" | awk '{print $1, $5}' | sort -u) \
             <(tail -n +2 "$after"  | awk '{print $1, $5}' | sort -u) | sed 's/^/  - /'
    echo
    echo "# Portas/serviços novos escutando após a atualização:"
    comm -13 <(tail -n +2 "$before" | awk '{print $1, $5}' | sort -u) \
             <(tail -n +2 "$after"  | awk '{print $1, $5}' | sort -u) | sed 's/^/  + /'
}
