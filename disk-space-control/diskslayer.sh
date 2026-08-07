#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
#  DISKSLAYER — Arch Linux Disk Space Destroyer
#  Navegação de pastas │ fzf integrado │ Scan automático │ Bash
# ╚══════════════════════════════════════════════════════════════════╝

# ━━━ CORES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
R='\033[0;31m'
RB='\033[1;31m'
RD='\033[2;31m'
W='\033[1;37m'
GR='\033[0;37m'
GN='\033[0;32m'
NC='\033[0m'
BG_R='\033[41m'
BLINK='\033[5m'
BOLD='\033[1m'
DIM='\033[2m'

# ━━━ ESTADO GLOBAL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ITEMS=()
SIZES=()
TYPES=()
CURSOR=0
PAGE_SIZE=16
SCROLL_OFFSET=0
SCAN_PATH="${1:-/}"
CUR_DIR="$SCAN_PATH"
MODE="top"           # top | browse | pacman
NAV_STACK=()         # histórico para [B]oltar

TOTAL_DISK="" USED_DISK="" FREE_DISK="" USE_PCT=0
PACMAN_CACHE_SIZE=""
HAS_FZF=0
command -v fzf &>/dev/null && HAS_FZF=1

# ━━━ TERMINAL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
hide_cursor()  { printf '\033[?25l'; }
show_cursor()  { printf '\033[?25h'; }
cls()          { printf '\033[2J\033[H'; }

trap 'show_cursor; tput rmcup 2>/dev/null; stty echo 2>/dev/null; printf "\n"; exit 0' EXIT INT TERM

# ━━━ BARRA DE PROGRESSO ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
draw_bar() {
    local pct="${1:-0}" width="${2:-40}"
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local color="$GN"
    (( pct > 60 )) && color='\033[0;33m'
    (( pct > 80 )) && color="$RB"
    printf "${color}["
    for (( i=0; i<filled; i++ )); do
        (( i == filled-1 )) && printf "▓" || printf "█"
    done
    for (( i=0; i<empty; i++ )); do printf "${RD}░"; done
    printf "${color}]${NC}"
}

# ━━━ SPINNER ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_SP=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
_SI=0
spin() {
    printf "\r${RB}  ${_SP[$_SI]} ${R}%-60s${NC}" "$1"
    _SI=$(( (_SI+1) % 10 ))
}

# ━━━ BANNER ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
print_banner() {
    printf "${RB}"
    printf '  ██████╗ ██╗███████╗██╗  ██╗███████╗██╗      █████╗ ██╗   ██╗███████╗██████╗ \n'
    printf '  ██╔══██╗██║██╔════╝██║ ██╔╝██╔════╝██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗\n'
    printf '  ██║  ██║██║███████╗█████╔╝ ███████╗██║     ███████║ ╚████╔╝ █████╗  ██████╔╝\n'
    printf '  ██║  ██║██║╚════██║██╔═██╗ ╚════██║██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗\n'
    printf '  ██████╔╝██║███████║██║  ██╗███████║███████╗██║  ██║   ██║   ███████╗██║  ██║\n'
    printf '  ╚═════╝ ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝\n'
    printf "${R}                    ☠  Arch Linux Disk Space Destroyer   ☠${NC}\n"
    printf "${RD}  ══════════════════════════════════════════════════════════════════════════${NC}\n"
}

print_banner_small() {
    printf "${RB}  ☠ DISKSLAYER ${R} — %s${NC}\n" "$1"
    printf "${RD}  ──────────────────────────────────────────────────────────────────────${NC}\n"
}

# ━━━ DISCO INFO ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
read_disk_info() {
    local df_out
    df_out=$(df -h "$SCAN_PATH" 2>/dev/null | tail -1)
    TOTAL_DISK=$(awk '{print $2}' <<< "$df_out")
    USED_DISK=$(awk  '{print $3}' <<< "$df_out")
    FREE_DISK=$(awk  '{print $4}' <<< "$df_out")
    USE_PCT=$(awk    '{print $5}' <<< "$df_out" | tr -d '%')
    [[ -z "$USE_PCT" || "$USE_PCT" == "-" ]] && USE_PCT=0
}

read_pacman_cache() {
    [[ -d /var/cache/pacman/pkg ]] \
        && PACMAN_CACHE_SIZE=$(du -sh /var/cache/pacman/pkg 2>/dev/null | awk '{print $1}') \
        || PACMAN_CACHE_SIZE="N/A"
}

# ━━━ SCAN TOP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
do_scan() {
    local scan_root="${1:-$SCAN_PATH}"
    local depth="${2:-4}"
    ITEMS=(); SIZES=(); TYPES=()

    cls
    print_banner
    printf "\n${RB}  ◈ ESCANEANDO: ${R}%s${NC}\n\n" "$scan_root"

    read_disk_info; read_pacman_cache

    printf "${RD}  ┌──────────────────────────────────────────────────────────┐${NC}\n"
    printf "${R}  │  Total ${RB}%-6s${R}  Usado ${RB}%-6s${R}  Livre ${RB}%-6s${NC}\n" \
        "$TOTAL_DISK" "$USED_DISK" "$FREE_DISK"
    printf "${R}  │  "; draw_bar "$USE_PCT" 54; printf " ${RB}%s%%${NC}\n" "$USE_PCT"
    printf "${RD}  └──────────────────────────────────────────────────────────┘${NC}\n\n"
    printf "${R}  Escaneando ${GR}(pode levar alguns segundos...)${NC}\n\n"

    local raw
    raw=$(sudo du -ahx --max-depth="$depth" "$scan_root" 2>/dev/null \
        | grep -v '^0' | sort -rh | head -300)

    local count=0
    while IFS=$'\t' read -r size path; do
        [[ -z "$path" || "$path" == "$scan_root" ]] && continue
        spin "$(basename "$path")"
        local t="F"; [[ -d "$path" ]] && t="D"
        ITEMS+=("$path"); SIZES+=("$size"); TYPES+=("$t")
        (( ++count >= 200 )) && break
    done <<< "$raw"

    printf "\r${GN}  ✔ Scan completo! ${RB}%d${GN} itens.%40s${NC}\n" "${#ITEMS[@]}" ""
    sleep 0.4
    CURSOR=0; SCROLL_OFFSET=0
}

# ━━━ SCAN BROWSE (1 nível) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
do_browse_scan() {
    ITEMS=(); SIZES=(); TYPES=()

    cls
    print_banner_small "BROWSE: $CUR_DIR"
    printf "\n${R}  Listando conteúdo de ${RB}%s${NC} ...\n\n" "$CUR_DIR"

    local raw
    raw=$(sudo du -ahx --max-depth=1 "$CUR_DIR" 2>/dev/null \
        | grep -v '^0' | sort -rh | head -300)

    while IFS=$'\t' read -r size path; do
        [[ -z "$path" || "$path" == "$CUR_DIR" ]] && continue
        local t="F"; [[ -d "$path" ]] && t="D"
        ITEMS+=("$path"); SIZES+=("$size"); TYPES+=("$t")
    done <<< "$raw"

    printf "${GN}  ✔ ${RB}%d${GN} itens em %s${NC}\n" "${#ITEMS[@]}" "$CUR_DIR"
    sleep 0.3
    CURSOR=0; SCROLL_OFFSET=0
}

# ━━━ SCAN PACMAN ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
do_pacman_scan() {
    ITEMS=(); SIZES=(); TYPES=()
    MODE="pacman"
    CUR_DIR="/var/cache/pacman/pkg"

    cls
    print_banner_small "PACMAN CACHE"
    printf "\n${R}  Escaneando /var/cache/pacman/pkg ...${NC}\n\n"

    local raw
    raw=$(sudo du -ah /var/cache/pacman/pkg 2>/dev/null \
        | grep -v '^0' | sort -rh | head -200)

    while IFS=$'\t' read -r size path; do
        [[ -z "$path" || "$path" == "/var/cache/pacman/pkg" ]] && continue
        local t="F"; [[ -d "$path" ]] && t="D"
        ITEMS+=("$path"); SIZES+=("$size"); TYPES+=("$t")
    done <<< "$raw"

    printf "${GN}  ✔ ${RB}%d${GN} pacotes encontrados.${NC}\n" "${#ITEMS[@]}"
    sleep 0.4
    CURSOR=0; SCROLL_OFFSET=0
}

# ━━━ FZF BROWSER ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
fzf_browse() {
    # Sai do modo TUI antes do fzf
    show_cursor
    tput rmcup 2>/dev/null
    stty echo 2>/dev/null

    local target="${ITEMS[$CURSOR]}"
    local base_dir
    [[ -d "$target" ]] && base_dir="$target" || base_dir="$(dirname "$target")"

    printf "${RB}\n  ☠ fzf — navegando em: ${R}%s${NC}\n\n" "$base_dir"

    printf "${GR}  carregando...${NC}\n"
    local fzf_list
    fzf_list=$(sudo du -ahx --max-depth=3 "$base_dir" 2>/dev/null \
        | grep -v '^0' | sort -rh | head -500)

    local chosen
    chosen=$(printf '%s\n' "$fzf_list" \
        | fzf \
            --ansi \
            --prompt="  ☠ DiskSlayer › " \
            --header="  [Enter] selecionar  [Esc] voltar  [Del] marcar p/ delete" \
            --color="fg:#cc0000,fg+:#ff2222,bg:#0d0d0d,bg+:#1a0000,\
hl:#ff6666,hl+:#ff0000,prompt:#ff0000,pointer:#ff0000,\
marker:#ff6600,header:#880000,border:#660000,info:#993300" \
            --pointer="☠" \
            --marker="✘" \
            --border=rounded \
            --height=85% \
            --preview='
f=$(echo {} | awk "{print \$2}")
if [ -d "$f" ]; then
    printf "📁 DIRETÓRIO\n\n"
    ls -lah --color=always "$f" 2>/dev/null | head -40
else
    printf "📄 ARQUIVO: %s\n\n" "$(du -sh "$f" 2>/dev/null | cut -f1)"
    file "$f" 2>/dev/null
    printf "\n"
    head -30 "$f" 2>/dev/null || printf "(binário ou sem permissão)\n"
fi' \
            --preview-window=right:45%:wrap \
        | awk '{print $2}')

    # Volta ao modo TUI
    tput smcup 2>/dev/null
    hide_cursor

    if [[ -n "$chosen" ]]; then
        local parent
        [[ -d "$chosen" ]] && parent="$chosen" || parent="$(dirname "$chosen")"
        NAV_STACK+=("$CUR_DIR")
        CUR_DIR="$parent"
        MODE="browse"
        do_browse_scan

        # Posiciona cursor no item escolhido se estiver na lista
        local i
        for i in "${!ITEMS[@]}"; do
            [[ "${ITEMS[$i]}" == "$chosen" ]] && CURSOR="$i" && break
        done
        adjust_scroll
    fi
}

# ━━━ RENDERIZAÇÃO ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
print_header() {
    cls
    local title
    case "$MODE" in
        top)    title="TOP MAIORES — $SCAN_PATH" ;;
        browse) title="BROWSE — $CUR_DIR" ;;
        pacman) title="PACMAN CACHE" ;;
    esac
    print_banner_small "$title"
    printf "\n"

    # Status do disco
    printf "${RD}  ┌─ DISCO ─────────────────────────────────────────────────────────────┐${NC}\n"
    printf "${R}  │  ${RB}%-7s${R} total  ${RB}%-7s${R} usado  ${RB}%-7s${R} livre  " \
        "$TOTAL_DISK" "$USED_DISK" "$FREE_DISK"
    [[ "$HAS_FZF" -eq 1 ]] \
        && printf "${GN}fzf:✔${NC}\n" \
        || printf "${RD}fzf:✘${NC}\n"
    printf "${R}  │  "; draw_bar "$USE_PCT" 60; printf " ${RB}%s%%${NC}\n" "$USE_PCT"
    printf "${R}  │  ${RD}☠ pacman cache: ${RB}%s${NC}\n" "$PACMAN_CACHE_SIZE"
    printf "${RD}  └─────────────────────────────────────────────────────────────────────┘${NC}\n\n"

    # Breadcrumb no modo browse
    if [[ "$MODE" == "browse" ]]; then
        printf "${R}  📂 "
        local d
        for d in "${NAV_STACK[@]}"; do
            printf "${RD}%s ${GR}›${NC} " "$(basename "$d")"
        done
        printf "${RB}%s${NC}\n\n" "$(basename "$CUR_DIR")"
    fi

    # Cabeçalho da tabela
    printf "${RD}  ╔═══╦════════╦══╦══════════════════════════════════════════════════════╗${NC}\n"
    printf "${RD}  ║${RB} # ${RD}║${RB} TAMANHO${RD}║${RB}  ${RD}║${RB} NOME / CAMINHO                                           ${RD}║${NC}\n"
    printf "${RD}  ╠═══╬════════╬══╬══════════════════════════════════════════════════════╣${NC}\n"
}

print_footer() {
    local total="${#ITEMS[@]}"
    local p1=$(( SCROLL_OFFSET + 1 ))
    local p2=$(( SCROLL_OFFSET + PAGE_SIZE ))
    (( p2 > total )) && p2=$total

    printf "${RD}  ╚═══╩════════╩══╩══════════════════════════════════════════════════════╝${NC}\n\n"
    printf "${RD}  ── %d–%d de %d" "$p1" "$p2" "$total"
    if [[ "$MODE" == "browse" && ${#NAV_STACK[@]} -gt 0 ]]; then
        printf " │ ${R}nível ${RB}%d" "${#NAV_STACK[@]}"
    fi
    printf " ──────────────────────────────────────────────────────${NC}\n\n"

    # Teclas contextuais
    printf "${R}  ${BOLD}[↑↓]${NC}${R}Nav  ${BOLD}[↵]${NC}${R}Ent  "
    (( ${#NAV_STACK[@]} > 0 )) && printf "${BOLD}[B]${NC}${RB}Voltar  "
    printf "${BOLD}[D]${NC}${R}Del  "
    printf "${BOLD}[T]${NC}${R}[...]  ${BOLD}[P]${NC}${R}Pacman  ${BOLD}[C]${NC}${R}Limpar Cache  ${BOLD}[R]${NC}${R}Atualizar  ${BOLD}[Q]${NC}${R}Sair${NC}\n\n"
}

fmt_line() {
    local idx="$1" sel="$2"
    local path="${ITEMS[$idx]}" size="${SIZES[$idx]}" type="${TYPES[$idx]}"
    local name; name=$(basename "$path")
    (( ${#name} > 50 )) && name="${name:0:47}..."
    local icon="📄"; [[ "$type" == "D" ]] && icon="📁"
    local rank=$(( idx + 1 ))

    if [[ "$sel" == "1" ]]; then
        printf "${BG_R}${W}  ►${RD}║${W}%-3d${RD}║${W}%-8s${RD}║${W}%s${RD}║${W} %-52s${RD}║${NC}" \
            "$rank" "$size" "$icon" "$name"
    else
        local c="$R"; [[ "$type" == "D" ]] && c="$RB"
        printf "${c}   ${RD}║${c}%-3d${RD}║${c}%-8s${RD}║${c}%s${RD}║${GR} %-52s${RD}║${NC}" \
            "$rank" "$size" "$icon" "$name"
    fi
}

render() {
    print_header
    local total="${#ITEMS[@]}"

    if (( total == 0 )); then
        printf "${RD}  ║${RB}  (nenhum item encontrado)%47s${RD}║${NC}\n" ""
        for (( i=1; i<PAGE_SIZE; i++ )); do
            printf "${RD}  ║%72s║${NC}\n" ""
        done
    else
        local end=$(( SCROLL_OFFSET + PAGE_SIZE ))
        (( end > total )) && end=$total
        for (( i=SCROLL_OFFSET; i<end; i++ )); do
            printf "  ${RD}║${NC}"
            local sel=0; (( i == CURSOR )) && sel=1
            fmt_line "$i" "$sel"
            printf "\n"
        done
        local shown=$(( end - SCROLL_OFFSET ))
        for (( i=shown; i<PAGE_SIZE; i++ )); do
            printf "${RD}  ║%72s║${NC}\n" ""
        done
    fi

    print_footer
}

# ━━━ SCROLL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
adjust_scroll() {
    (( CURSOR < SCROLL_OFFSET )) && SCROLL_OFFSET=$CURSOR
    (( CURSOR >= SCROLL_OFFSET + PAGE_SIZE )) && SCROLL_OFFSET=$(( CURSOR - PAGE_SIZE + 1 ))
    (( SCROLL_OFFSET < 0 )) && SCROLL_OFFSET=0
}

# ━━━ ENTRAR EM DIRETÓRIO ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
enter_item() {
    local path="${ITEMS[$CURSOR]}"
    if [[ -d "$path" ]]; then
        NAV_STACK+=("$CUR_DIR")
        CUR_DIR="$path"
        MODE="browse"
        do_browse_scan
    else
        delete_prompt "$CURSOR"
    fi
}

# ━━━ VOLTAR ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
go_back() {
    (( ${#NAV_STACK[@]} == 0 )) && return
    CUR_DIR="${NAV_STACK[-1]}"
    unset 'NAV_STACK[-1]'
    do_browse_scan
}

# ━━━ DELEÇÃO ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
delete_prompt() {
    local idx="${1:-$CURSOR}"
    local path="${ITEMS[$idx]}" size="${SIZES[$idx]}" type="${TYPES[$idx]}"

    cls; print_banner; printf "\n"
    printf "${RB}  ╔══════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${RB}  ║  ☠  CONFIRMAR DELEÇÃO                                       ║${NC}\n"
    printf "${RB}  ╠══════════════════════════════════════════════════════════════╣${NC}\n"
    printf "${R}  ║  Nome    : ${RB}%-48s${R}║${NC}\n" "$(basename "$path")"
    printf "${R}  ║  Caminho : ${RB}%-48s${R}║${NC}\n" "${path:0:48}"
    printf "${R}  ║  Tamanho : ${RB}%-48s${R}║${NC}\n" "$size"
    printf "${R}  ║  Tipo    : ${RB}%-48s${R}║${NC}\n" \
        "$( [[ $type == D ]] && echo '📁 DIRETÓRIO' || echo '📄 ARQUIVO' )"
    printf "${RB}  ╚══════════════════════════════════════════════════════════════╝${NC}\n\n"
    printf "${RB}${BLINK}  ☠  ISSO É IRREVERSÍVEL!${NC}  ${RB}Confirma? [y/N]: ${NC}"

    local ans; read -r -n1 ans; printf "\n\n"

    if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
        printf "${R}  Deletando ${RB}%s${NC}\n" "$(basename "$path")"
        local ok=1
        if [[ "$type" == "D" ]]; then
            sudo rm -rf "$path" 2>/dev/null && ok=0
        else
            sudo rm -f  "$path" 2>/dev/null && ok=0
        fi

        printf "  "
        for pct in 10 30 55 80 100; do
            printf "\r  "; draw_bar "$pct" 52; printf " ${RB}%d%%${NC}  " "$pct"; sleep 0.08
        done; printf "\n\n"

        if (( ok == 0 )); then
            printf "${GN}  ✔ Deletado! ${RB}%s${GN} liberados.${NC}\n" "$size"
            ITEMS=("${ITEMS[@]:0:$idx}" "${ITEMS[@]:$(( idx+1 ))}")
            SIZES=("${SIZES[@]:0:$idx}" "${SIZES[@]:$(( idx+1 ))}")
            TYPES=("${TYPES[@]:0:$idx}" "${TYPES[@]:$(( idx+1 ))}")
            (( CURSOR >= ${#ITEMS[@]} && CURSOR > 0 )) && (( CURSOR-- ))
            (( SCROLL_OFFSET > 0 && SCROLL_OFFSET >= ${#ITEMS[@]} )) && \
                SCROLL_OFFSET=$(( ${#ITEMS[@]} - PAGE_SIZE ))
            (( SCROLL_OFFSET < 0 )) && SCROLL_OFFSET=0
            read_disk_info
        else
            printf "${RB}  ✘ Falha! Verifique permissões.${NC}\n"
        fi
        sleep 1.2
    else
        printf "${R}  Cancelado.${NC}\n"; sleep 0.6
    fi
}

# ━━━ LIMPEZA PACMAN ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
clean_pacman_cache() {
    cls; print_banner; printf "\n"
    printf "${RB}  ☠ LIMPEZA DO CACHE PACMAN ☠${NC}\n\n"
    printf "${R}  Cache atual : ${RB}%s${NC}\n" "$PACMAN_CACHE_SIZE"
    printf "${R}  Ação        : paccache -rk2 (mantém 2 versões por pacote)${NC}\n\n"
    printf "${RB}  Confirma? [y/N]: ${NC}"

    local ans; read -r -n1 ans; printf "\n\n"

    if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
        if command -v paccache &>/dev/null; then
            sudo paccache -rk2 2>&1 | while IFS= read -r l; do
                printf "${GR}  %s${NC}\n" "$l"
            done
        else
            printf "${RD}  paccache não encontrado. Instale: sudo pacman -S pacman-contrib${NC}\n"
            printf "${R}  Fallback: pacman -Sc ...${NC}\n\n"
            sudo pacman -Sc --noconfirm 2>/dev/null
        fi
        printf "\n  "
        for pct in 20 50 80 100; do
            printf "\r  "; draw_bar "$pct" 52; printf " ${RB}%d%%${NC}  " "$pct"; sleep 0.12
        done; printf "\n\n"
        read_pacman_cache
        printf "${GN}  ✔ Cache limpo! Agora: ${RB}%s${NC}\n" "$PACMAN_CACHE_SIZE"
    else
        printf "${R}  Cancelado.${NC}\n"
    fi
    sleep 1.5
}

# ━━━ LEITURA DE TECLA ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# -d '' + n1 captura qualquer byte incluindo \n (Enter)
_read_key() {
    _KEY=""
    local e=""
    IFS= read -r -s -d '' -n1 _KEY
    if [[ "$_KEY" == $'\033' ]]; then
        IFS= read -r -s -d '' -n2 -t 0.1 e
        _KEY="${_KEY}${e}"
    fi
}

# ━━━ SPLASH ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
splash_screen() {
    cls; printf "\n"
    print_banner
    printf "\n"
    printf "${R}  Bem-vindo ao DiskSlayer para Arch Linux!${NC}\n\n"
    printf "${RD}  ──────────────────────────────────────────────────────────${NC}\n\n"
    printf "${RB}  Iniciando scan automático de ${R}%s${RB}...${NC}\n\n" "$SCAN_PATH"
    sleep 1
}

# ━━━ DEPENDÊNCIAS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
check_deps() {
    local miss=()
    for cmd in du df sudo; do
        command -v "$cmd" &>/dev/null || miss+=("$cmd")
    done
    if (( ${#miss[@]} > 0 )); then
        printf "${RB}  ✘ Dependências ausentes: %s${NC}\n" "${miss[*]}"
        printf "${R}  sudo pacman -S %s${NC}\n" "${miss[*]}"
        exit 1
    fi
}

# ━━━ MAIN LOOP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
main() {
    check_deps
    splash_screen

    tput smcup 2>/dev/null
    hide_cursor

    # Scan automático ao iniciar
    MODE="top"
    do_scan "$SCAN_PATH" 4
    read_disk_info; read_pacman_cache

    while true; do
        render

        local key; _read_key; key="$_KEY"

        case "$key" in
            $'\033[A'|'k')            # UP
                (( CURSOR > 0 )) && (( CURSOR-- ))
                adjust_scroll ;;

            $'\033[B'|'j')            # DOWN
                (( CURSOR < ${#ITEMS[@]}-1 )) && (( CURSOR++ ))
                adjust_scroll ;;

            $'\033[5~')               # PAGE UP
                (( CURSOR -= PAGE_SIZE ))
                (( CURSOR < 0 )) && CURSOR=0
                adjust_scroll ;;

            $'\033[6~')               # PAGE DOWN
                (( CURSOR += PAGE_SIZE ))
                (( CURSOR >= ${#ITEMS[@]} )) && CURSOR=$(( ${#ITEMS[@]}-1 ))
                (( CURSOR < 0 )) && CURSOR=0
                adjust_scroll ;;

            $'\033[H'|'g')            # HOME
                CURSOR=0; SCROLL_OFFSET=0 ;;

            $'\033[F'|'G')            # END
                CURSOR=$(( ${#ITEMS[@]}-1 ))
                (( CURSOR < 0 )) && CURSOR=0
                adjust_scroll ;;

            $'\n'|$'\r')              # ENTER — abre fzf no item selecionado
                (( HAS_FZF == 1 && ${#ITEMS[@]} > 0 )) && fzf_browse ;;

            'b'|'B')                  # VOLTAR
                (( ${#NAV_STACK[@]} > 0 )) && go_back ;;

            'd'|'D')                  # DELETAR
                (( ${#ITEMS[@]} > 0 )) && delete_prompt ;;

            't'|'T')                  # TOP — volta ao scan geral
                MODE="top"; NAV_STACK=(); CUR_DIR="$SCAN_PATH"
                do_scan "$SCAN_PATH" 4
                read_disk_info; read_pacman_cache ;;

            'p'|'P')                  # PACMAN
                NAV_STACK=()
                do_pacman_scan
                read_disk_info; read_pacman_cache ;;

            'c'|'C')                  # LIMPAR cache
                clean_pacman_cache
                read_disk_info; read_pacman_cache ;;

            'r'|'R')                  # RESCAN
                case "$MODE" in
                    top)    do_scan "$SCAN_PATH" 4 ;;
                    browse) do_browse_scan ;;
                    pacman) do_pacman_scan ;;
                esac
                read_disk_info; read_pacman_cache ;;

            'q'|'Q'|$'\003')          # SAIR
                break ;;
        esac
    done

    tput rmcup 2>/dev/null
    show_cursor
}

main
