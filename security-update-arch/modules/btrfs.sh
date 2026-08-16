#!/usr/bin/env bash
# =============================================================================
# arch-guardian :: modules/btrfs.sh
# Estado do BTRFS (somente leitura). O snapper continua funcionando de forma
# independente (seus próprios hooks/timers) — aqui só exibimos o `snapper
# list` como informação, nunca criamos/apagamos snapshots.
# =============================================================================

btrfs::is_root_btrfs() {
    case "$BTRFS_ENABLED" in
        false) return 1 ;;
        true)  return 0 ;;
        auto|*)
            [[ "$(stat -f --format='%T' / 2>/dev/null)" == "btrfs" ]]
            ;;
    esac
}

btrfs::status() {
    if ! btrfs::is_root_btrfs; then
        echo "Sistema de arquivos raiz não é BTRFS (ou detecção desativada)."
        return
    fi
    echo -e "${C_BOLD}Uso do sistema de arquivos:${C_RESET}"
    btrfs filesystem usage / 2>/dev/null || echo "  (necessário root para detalhes completos)"
    echo
    echo -e "${C_BOLD}Subvolumes:${C_RESET}"
    btrfs subvolume list / 2>/dev/null | sed 's/^/  /'
    echo
    echo -e "${C_BOLD}Status do último scrub:${C_RESET}"
    btrfs scrub status / 2>/dev/null | sed 's/^/  /'
}

btrfs::snapper_list() {
    if ! command -v snapper &>/dev/null; then
        echo "Snapper não está instalado (ou não está no PATH)."
        return
    fi
    echo -e "${C_BOLD}Snapshots do snapper (config: ${SNAPPER_CONFIG:-root}) - somente leitura:${C_RESET}"
    snapper -c "${SNAPPER_CONFIG:-root}" list 2>/dev/null | tail -n 10
}

btrfs::short_status() {
    if ! btrfs::is_root_btrfs; then
        echo "n/d"
        return
    fi

    local line
    local free
    local min

    line="$(
        btrfs filesystem usage / 2>/dev/null |
        grep 'Free (estimated):'
    )"

    if [[ -z "$line" ]]; then
        echo "n/d"
        return
    fi

    free="$(
        sed -nE 's/.*Free \(estimated\):[[:space:]]*([^[:space:]]+).*/\1/p' <<< "$line"
    )"

    min="$(
        sed -nE 's/.*\(min:[[:space:]]*([^)]*).*/\1/p' <<< "$line"
    )"

    [[ -z "$free" ]] && free="n/d"
    [[ -z "$min" ]] && min="n/d"

    echo "${free} free | min ${min}"
}

btrfs::menu() {
    guardian::header
    echo -e "${C_BOLD}${C_CYAN}-- BTRFS / Snapper (somente leitura) --${C_RESET}"
    echo
    btrfs::status
    echo
    btrfs::snapper_list
    echo
    guardian::pause
}

# --- Snapshot para o relatório ------------------------------------------------
btrfs::snapshot() {
    local tag="$1"
    btrfs::is_root_btrfs || return 0
    {
        echo "-- $(date) --"
        btrfs filesystem usage / 2>/dev/null
    } > "$STATE_DIR/btrfs_${tag}.txt" 2>/dev/null
}
