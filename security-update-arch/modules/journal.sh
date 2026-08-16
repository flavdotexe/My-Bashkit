#!/usr/bin/env bash
# =============================================================================
# arch-guardian :: modules/journal.sh
# Marca o instante de início/fim de uma atualização e usa journalctl para
# extrair erros ocorridos nesse intervalo (correlação com a atualização).
# =============================================================================

jr::mark_start() {
    date '+%Y-%m-%d %H:%M:%S' > "$STATE_DIR/last_update_start"
}

jr::mark_end() {
    date '+%Y-%m-%d %H:%M:%S' > "$STATE_DIR/last_update_end"
}

jr::errors_since_start() {
    local since
    since="$(cat "$STATE_DIR/last_update_start" 2>/dev/null)"
    [[ -z "$since" ]] && { echo "(sem marca de início registrada)"; return; }
    journalctl -p "${JOURNAL_ERROR_PRIORITY:-3}" --since "$since" --no-pager 2>/dev/null
}

jr::errors_count() {
    jr::errors_since_start | grep -c .
}

# Erros gerais desde o último boot (visão rápida de saúde do sistema)
jr::boot_errors() {
    journalctl -p "${JOURNAL_ERROR_PRIORITY:-3}" -b --no-pager 2>/dev/null
}

jr::boot_errors_count() {
    jr::boot_errors | grep -c .
}

jr::report_section() {
    echo "# Erros no journal desde o início da atualização:"
    local errs
    errs="$(jr::errors_since_start)"
    if [[ -z "$errs" ]]; then
        echo "  Nenhum erro registrado."
    else
        echo "$errs" | sed 's/^/  /'
    fi
}
