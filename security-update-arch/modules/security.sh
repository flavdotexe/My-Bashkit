#!/usr/bin/env bash
# =============================================================================
# arch-guardian :: modules/security.sh
# Agrega informações dos outros módulos numa tabela de avisos exibida
# abaixo do menu principal, e calcula uma "saúde do sistema" simples com
# base no resultado da última atualização registrada.
# =============================================================================

sec::_row() {
    # $1 rótulo, $2 valor, $3 cor (opcional)
    local label="$1" value="$2" color="${3:-$C_RESET}"
    printf "  %-34s ${color}%-30s${C_RESET}\n" "$label" "$value"
}

sec::render_warnings_table() {
    echo -e "${C_BOLD}${C_MAGENTA} STATUS DO SISTEMA:${C_RESET}"

    # Pacotes críticos pendentes
    local crit
    crit="$(pkg::critical_pending 2>/dev/null | tr '\n' ' ')"
    if [[ -n "${crit// }" ]]; then
        sec::_row "Pacotes críticos pendentes:" "$crit" "$C_RED"
    else
        sec::_row "Pacotes críticos pendentes:" "Nenhum" "$C_GREEN"
    fi

    # Total de atualizações pendentes
    local total
    total="$(pkg::pending_count 2>/dev/null)"
    if [[ "$total" -gt 0 ]]; then
        sec::_row "Atualizações pendentes:" "$total pacote(s)" "$C_YELLOW"
    else
        sec::_row "Atualizações pendentes:" "Sistema em dia" "$C_GREEN"
    fi

    # Órfãos
    local orph
    orph="$(pkg::orphans_count 2>/dev/null)"
    if [[ "$orph" -gt 0 ]]; then
        sec::_row "Pacotes órfãos:" "$orph encontrado(s)" "$C_YELLOW"
    else
        sec::_row "Pacotes órfãos:" "Nenhum" "$C_GREEN"
    fi

    # Serviços ativos afetados por pendências
    local aff
    aff="$(svc::affected_count 2>/dev/null)"
    if [[ "$aff" -gt 0 ]]; then
        sec::_row "Serviços ativos em atualizações pendentes:" "$aff serviço(s)" "$C_YELLOW"
    else
        sec::_row "Serviços ativos em atualizações pendentes:" "Nenhum" "$C_GREEN"
    fi

    # Serviços com falha agora
    local failed
    failed="$(svc::failed_count 2>/dev/null)"
    if [[ "$failed" -gt 0 ]]; then
        sec::_row "Serviços em estado FAILED:" "$failed" "$C_RED"
    else
        sec::_row "Serviços em estado FAILED:" "Nenhum" "$C_GREEN"
    fi

    # Configs modificados em pacotes pendentes
    local cfg
    cfg="$(integ::modified_configs_count 2>/dev/null)"
    if [[ "$cfg" -gt 0 ]]; then
        sec::_row "Configs modificadas em atualizações pendentes:" "$cfg arquivo(s)" "$C_YELLOW"
    else
        sec::_row "Configs modificadas em atualizações pendentes:" "Nenhuma" "$C_GREEN"
    fi

    # .pacnew/.pacsave existentes
local pacnew
pacnew="$(integ::pacnew_count 2>/dev/null)"

if [[ "$pacnew" -gt 0 ]]; then
    local pacnew_size
    pacnew_size="$(integ::pacnew_size 2>/dev/null)"
    sec::_row ".pacnew/.pacsave em /etc:" "$pacnew arquivo(s) | $pacnew_size" "$C_YELLOW"
else
    sec::_row ".pacnew/.pacsave em /etc:" "Nenhum" "$C_GREEN"
fi

    # BTRFS
    sec::_row "BTRFS (/root):" "$(btrfs::short_status 2>/dev/null)" "$C_RESET"

    # Saúde geral com base no último relatório
    sec::_row "Saúde da última atualização:" "$(sec::last_update_health)" "$(sec::last_update_health_color)"

    echo -e "${C_BOLD}${C_MAGENTA}─────────────────────────────────────────────────────────────────────────${C_RESET}"
}

# Lê o status salvo da última execução de guardian::write_report
sec::last_update_health() {
    local f="$STATE_DIR/last_update_status"
    [[ -f "$f" ]] && cat "$f" || echo "Sem registro ainda"
}

sec::last_update_health_color() {
    local status
    status="$(sec::last_update_health)"
    case "$status" in
        OK) echo "$C_GREEN" ;;
        FALHOU) echo "$C_RED" ;;
        *) echo "$C_RESET" ;;
    esac
}
