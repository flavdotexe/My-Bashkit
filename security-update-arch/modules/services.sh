#!/usr/bin/env bash
# =============================================================================
# arch-guardian :: modules/services.sh
# Serviços systemd ativos, e o cruzamento entre eles e pacotes pendentes de
# atualização (para saber o que pode precisar de restart após o update).
# =============================================================================

svc::active() {
    systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null
}

svc::active_count() {
    svc::active | grep -c .
}

svc::failed() {
    systemctl --failed --no-legend --no-pager 2>/dev/null
}

svc::failed_count() {
    svc::failed | grep -c .
}

# Cruza pacotes pendentes de atualização com serviços systemd ativos.
# Estratégia: para cada pacote pendente, lista os arquivos que ele instala em
# /usr/lib/systemd/system (unit files); se algum desses units está ativo,
# reporta o pacote + o serviço.
svc::affected_by_pending() {
    local pkgs
    pkgs="$(pkg::pending_names 2>/dev/null)"
    [[ -z "$pkgs" ]] && return 0

    local active_units
    active_units="$(systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | awk '{print $1}')"

    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        local units
        units="$(pacman -Ql "$pkg" 2>/dev/null | awk '{print $2}' | grep -E '/systemd/system/.*\.service$' | xargs -r -n1 basename)"
        [[ -z "$units" ]] && continue
        while IFS= read -r unit; do
            [[ -z "$unit" ]] && continue
            if grep -qx "$unit" <<<"$active_units"; then
                echo "$pkg -> $unit"
            fi
        done <<<"$units"
    done <<<"$pkgs"
}

svc::affected_count() {
    svc::affected_by_pending | grep -c .
}

# --- Snapshot de estado --------------------------------------------------------
svc::snapshot() {
    local tag="$1"
    svc::active > "$STATE_DIR/services_${tag}.txt" 2>/dev/null
    svc::failed > "$STATE_DIR/services_failed_${tag}.txt" 2>/dev/null
}

svc::diff_report() {
    local before="$STATE_DIR/services_before.txt"
    local after="$STATE_DIR/services_after.txt"
    local fbefore="$STATE_DIR/services_failed_before.txt"
    local fafter="$STATE_DIR/services_failed_after.txt"

    if [[ -f "$before" && -f "$after" ]]; then
        echo "# Serviços que pararam de rodar após a atualização:"
        comm -23 <(awk '{print $1}' "$before" | sort) <(awk '{print $1}' "$after" | sort) | sed 's/^/  - /'
        echo
        echo "# Serviços novos em execução após a atualização:"
        comm -13 <(awk '{print $1}' "$before" | sort) <(awk '{print $1}' "$after" | sort) | sed 's/^/  + /'
    else
        echo "(sem dados de comparação)"
    fi

    echo
    if [[ -f "$fafter" ]]; then
        local failed
        failed="$(cat "$fafter")"
        if [[ -n "$failed" ]]; then
            echo "# Serviços em estado FAILED após a atualização:"
            echo "$failed" | sed 's/^/  ! /'
        else
            echo "# Nenhum serviço em estado FAILED após a atualização."
        fi
    fi
}
