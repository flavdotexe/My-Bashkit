#!/usr/bin/env bash
# =============================================================================
# arch-guardian :: modules/packages.sh
# Tudo relacionado a pacman/AUR: listar atualizações, aplicar, tipos de
# pacotes, órfãos, kernel, snapshot de estado para o relatório.
# =============================================================================

# --- Descoberta de helper AUR ------------------------------------------------
pkg::aur_helper() {
    case "$AUR_HELPER" in
        yay|paru)
            command -v "$AUR_HELPER" &>/dev/null && echo "$AUR_HELPER" && return 0
            ;;
        auto|*)
            for h in yay paru; do
                command -v "$h" &>/dev/null && echo "$h" && return 0
            done
            ;;
    esac
    return 1
}

# --- Listagem de atualizações pendentes -------------------------------------
# Formato de saída: "pacote versao_atual -> versao_nova"
pkg::pending_updates() {
    pacman -Qu 2>/dev/null
}

pkg::pending_count() {
    pkg::pending_updates | grep -c .
}

pkg::pending_names() {
    pkg::pending_updates | awk '{print $1}'
}

# --- Pacotes críticos pendentes ----------------------------------------------
pkg::critical_pending() {
    local pending
    pending="$(pkg::pending_names)"
    [[ -z "$pending" ]] && return 0
    for crit in "${CRITICAL_PACKAGES[@]}"; do
        grep -qx "$crit" <<<"$pending" && echo "$crit"
    done
}

# --- Tipos de pacotes ---------------------------------------------------------
pkg::explicit()     { pacman -Qe 2>/dev/null; }
pkg::dependencies()  { pacman -Qd 2>/dev/null; }
pkg::orphans()       { pacman -Qtdq 2>/dev/null; }
pkg::orphans_count() { pkg::orphans | grep -c .; }
pkg::groups()        { pacman -Qg 2>/dev/null; }
pkg::foreign()       { pacman -Qm 2>/dev/null; }  # instalados fora dos repos oficiais (AUR/local)

pkg::types_menu() {
    local -a labels=(
        "Explícitos (instalados manualmente)"
        "Dependências (instaladas automaticamente)"
        "Órfãos (dependências sem nada que dependa delas)"
        "Grupos de pacotes"
        "Estrangeiros (AUR / instalação local, fora dos repos oficiais)"
    )

    while true; do
        guardian::menu "Tipos de pacotes instalados" "${labels[@]}"
        local rc=$?
        [[ $rc -ne 0 ]] && return

        case "$GUARDIAN_MENU_CHOICE" in
            0) pkg::explicit | less -F ;;
            1) pkg::dependencies | less -F ;;
            2)
                local orphans
                orphans="$(pkg::orphans)"
                guardian::header
                if [[ -z "$orphans" ]]; then
                    echo "Nenhum pacote órfão encontrado."
                else
                    echo "$orphans"
                    echo
                    read -rp "Remover todos os órfãos listados acima? [s/N] " rm
                    if [[ "$rm" =~ ^[sS]$ ]]; then
                        sudo pacman -Rns $(echo "$orphans")
                    fi
                fi
                guardian::pause
                ;;
            3) pkg::groups | less -F ;;
            4) pkg::foreign | less -F ;;
        esac
    done
}

# --- Kernel -------------------------------------------------------------------
pkg::kernel_info() {
    guardian::header
    echo -e "${C_BOLD}${C_CYAN}-- Informações do kernel --${C_RESET}"
    echo
    echo -e "${C_BOLD}Kernel em execução:${C_RESET} $(uname -r)"
    echo
    echo -e "${C_BOLD}Pacotes de kernel instalados:${C_RESET}"
    pacman -Q | grep -E '^linux(-lts|-zen|-hardened)?( |$)' || echo "  (nenhum encontrado com esse padrão)"
    echo
    echo -e "${C_BOLD}Imagens em /boot:${C_RESET}"
    find /boot -maxdepth 1 -type f \( -name 'vmlinuz-*' -o -name 'initramfs-*' \) -printf '  %f\t%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort
    echo
    local running_pkg
    running_pkg="$(pacman -Qo "/boot/vmlinuz-linux" 2>/dev/null | awk '{print $5}')"
    if pacman -Qu 2>/dev/null | grep -qE '^linux(-lts|-zen|-hardened)? '; then
        echo -e "${C_YELLOW}⚠ Há atualização de kernel pendente. É recomendado reiniciar após atualizar.${C_RESET}"
    else
        echo -e "${C_GREEN}✔ Nenhuma atualização de kernel pendente.${C_RESET}"
    fi
    guardian::pause
}

# --- Ações de atualização -----------------------------------------------------
pkg::action_full_update() {
    sudo pacman -Syu
}

pkg::action_sync_official() {
    # Só repositórios oficiais (mesmo comando, mas explicitamente sem AUR)
    sudo pacman -Syu
}

pkg::action_aur_update() {
    local helper
    if ! helper="$(pkg::aur_helper)"; then
        echo -e "${C_RED}Nenhum helper de AUR (yay/paru) encontrado no PATH.${C_RESET}"
        return 1
    fi
    "$helper" -Sua
}

# --- Snapshot de estado para o relatório --------------------------------------
pkg::snapshot() {
    local tag="$1"
    pacman -Q > "$STATE_DIR/pkglist_${tag}.txt" 2>/dev/null
}

# Gera a seção "Pacotes atualizados" do relatório comparando pkglist_before/after
pkg::diff_report() {
    local before="$STATE_DIR/pkglist_before.txt"
    local after="$STATE_DIR/pkglist_after.txt"
    [[ -f "$before" && -f "$after" ]] || { echo "(sem dados de comparação)"; return; }

    echo "# Atualizados/alterados:"
    join -j1 <(sort "$before") <(sort "$after") 2>/dev/null | \
        awk '{ if (NF>=3 && $2!=$3) print "  " $1 ": " $2 " -> " $3 }'

    echo
    echo "# Instalados novos:"
    comm -13 <(awk '{print $1}' "$before" | sort) <(awk '{print $1}' "$after" | sort) | sed 's/^/  + /'

    echo
    echo "# Removidos:"
    comm -23 <(awk '{print $1}' "$before" | sort) <(awk '{print $1}' "$after" | sort) | sed 's/^/  - /'
}
