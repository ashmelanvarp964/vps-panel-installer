#!/bin/bash
 
# ╔══════════════════════════════════════════════════════════════╗
# ║   ✦  A S T R A  —  Pterodactyl Automated Installer  ✦      ║
# ║   Panel · Wings · Blueprint · Firewall Manager              ║
# ║   Ubuntu 20.04/22.04/24.04 · Debian 11/12                  ║
# ║   by JishnuTech — github.com/jishnutech                     ║
# ╚══════════════════════════════════════════════════════════════╝
 
# ── Strict mode ───────────────────────────────────────────────
set -euo pipefail
IFS=$'\n\t'
 
# ── Colors ────────────────────────────────────────────────────
R='\033[0;31m';  LR='\033[1;31m'
G='\033[0;32m';  LG='\033[1;32m'
Y='\033[1;33m'
B='\033[0;34m';  LB='\033[1;34m'
M='\033[0;35m';  LM='\033[1;35m'
C='\033[0;36m';  LC='\033[1;36m'
W='\033[1;37m'
DIM='\033[2m';   BOLD='\033[1m';  BLINK='\033[5m'
NC='\033[0m'
HIDE_CURSOR='\033[?25l'; SHOW_CURSOR='\033[?25h'
CLEAR_LINE='\033[2K'
 
# ── Globals ───────────────────────────────────────────────────
MIN_RAM_MB=1024
MIN_DISK_GB=10
OS=""
OS_VER=""
PHP_VER="8.3"           # will be set by detect_php_ver()
PANEL_DIR="/var/www/pterodactyl"
LOG_FILE="/var/log/astra_install.log"
 
# ── Trap: always restore cursor & show log hint on error ──────
trap '_rc=$?; echo -e "${SHOW_CURSOR}"; tput cnorm 2>/dev/null
      [[ $_rc -ne 0 ]] && echo -e "\n  ${LR}${BOLD}Error! Check ${LOG_FILE} for details.${NC}\n"
      exit $_rc' EXIT
trap 'echo -e "${SHOW_CURSOR}"; tput cnorm 2>/dev/null; echo ""; exit 130' INT TERM
 
# ═══════════════════════════════════════════════════════════════
# ANIMATION LAYER
# ═══════════════════════════════════════════════════════════════
 
hide_cursor() { printf '%b' "${HIDE_CURSOR}"; tput civis 2>/dev/null || true; }
show_cursor() { printf '%b' "${SHOW_CURSOR}"; tput cnorm 2>/dev/null || true; }
 
# Portable sub-second sleep  (sleep_ms 120 → 0.12 s)
sleep_ms() {
    local ms="${1:-100}"
    local sec
    sec=$(awk "BEGIN{printf \"%.3f\",$ms/1000}")
    sleep "$sec" 2>/dev/null || true
}
 
# Typewriter: type_text "text" COLOR DELAY_MS
type_text() {
    local text="$1" color="${2:-$NC}" delay="${3:-28}"
    local i
    printf '%b' "${color}"
    for ((i=0;i<${#text};i++)); do
        printf '%s' "${text:$i:1}"
        sleep_ms "$delay"
    done
    printf '%b\n' "${NC}"
}
 
# Braille spinner — spinner $! "label"
spinner() {
    local pid=$1 msg="${2:-Working…}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local cols=("$LC" "$LM" "$LG" "$LB" "$Y" "$LC" "$LM" "$LG")
    local i=0
    hide_cursor
    while kill -0 "$pid" 2>/dev/null; do
        local f="${frames[$((i%${#frames[@]}))]}"
        local c="${cols[$((i%${#cols[@]}))]}"
        printf '\r  %b%b%b  %b%b%b   ' "$c" "$BOLD" "$f" "$NC" "$W" "$msg" "$NC"
        sleep_ms 80
        ((i++)) || true
    done
    printf '\r%b' "${CLEAR_LINE}"
    show_cursor
}
 
# Animated fill bar:  animate_progress "label" STEPS
animate_progress() {
    local label="${1:-Progress}" steps="${2:-25}"
    hide_cursor
    local i col
    for ((i=0;i<=steps;i++)); do
        local filled=$(( i*40/steps ))
        local empty=$(( 40-filled ))
        local pct=$(( i*100/steps ))
        if   ((pct<40)); then col="$R"
        elif ((pct<70)); then col="$Y"
        else col="$LG"; fi
        local bar
        bar=$(printf '█%.0s' $(seq 1 "$filled") 2>/dev/null || printf '%*s' "$filled" '' | tr ' ' '█')
        local spc
        spc=$(printf '░%.0s' $(seq 1 "$empty")  2>/dev/null || printf '%*s' "$empty"  '' | tr ' ' '░')
        printf '\r  %b%b%b  %b[%b%b%b%b]%b %b%b%d%%%b   ' \
            "$DIM" "$label" "$NC" \
            "$col" "$BOLD" "$bar" "$NC$DIM" "$spc" "$NC" \
            "$W$BOLD" "" "$pct" "$NC"
        sleep_ms 55
    done
    printf '\r%b  %b%b[✔]%b  %b%s done%b\n' \
        "${CLEAR_LINE}" "$LG" "$BOLD" "$NC" "$W" "$label" "$NC"
    show_cursor
}
 
# Animated separator
anim_sep() {
    local col="${1:-$M}"
    printf '  %b' "$col"
    local i; for ((i=0;i<62;i++)); do printf '━'; sleep_ms 6; done
    printf '%b\n' "$NC"
}
 
# Fade lines:  fade_lines DELAY_MS "line1" "line2" …
fade_lines() {
    local delay="$1"; shift
    local l; for l in "$@"; do printf '%b\n' "$l"; sleep_ms "$delay"; done
}
 
# Rainbow char-by-char
rainbow_echo() {
    local text="$1"
    local cols=("$LR" "$Y" "$LG" "$LC" "$LB" "$M" "$LM")
    local i
    for ((i=0;i<${#text};i++)); do
        printf '%b%b%s' "${cols[$((i%${#cols[@]}))]}" "$BOLD" "${text:$i:1}"
        sleep_ms 14
    done
    printf '%b\n' "$NC"
}
 
# Wipe-in with cursor block
wipe_in() {
    local text="$1" col="${2:-$W}"
    local i
    for ((i=1;i<=${#text};i++)); do
        printf '\r  %b%b%s%b█%b   ' "$col" "$BOLD" "${text:0:$i}" "$DIM" "$NC"
        sleep_ms 18
    done
    printf '\r  %b%b%s%b   \n' "$col" "$BOLD" "$text" "$NC"
}
 
# ═══════════════════════════════════════════════════════════════
# BOOT INTRO  (stars → ASTRA logo)
# ═══════════════════════════════════════════════════════════════
 
boot_intro() {
    hide_cursor
    clear
 
    # ── Starfield burst ──────────────────────────────
    local STARS=('·' '✦' '✧' '⋆' '★' '✶' '✸' '✹' '°' '*')
    local STAR_COLS=("$LC" "$LB" "$W" "$LM" "$Y" "$LC" "$W")
    local p r c
    for p in $(seq 1 8); do
        clear
        for r in $(seq 1 7); do
            printf '  '
            for c in $(seq 1 72); do
                if (( RANDOM % 3 == 0 )); then
                    local sc="${STAR_COLS[$((RANDOM%${#STAR_COLS[@]}))]}"
                    local st="${STARS[$((RANDOM%${#STARS[@]}))]}"
                    printf '%b%b%s%b' "$sc" "$BOLD" "$st" "$NC"
                else
                    printf ' '
                fi
            done
            printf '\n'
        done
        sleep_ms 70
    done
 
    # ── Meteor streaks ───────────────────────────────
    for p in $(seq 1 4); do
        clear
        local streak_row=$(( RANDOM % 7 + 1 ))
        for r in $(seq 1 8); do
            printf '  '
            for c in $(seq 1 72); do
                if (( r == streak_row && c > 20 && c < 60 )); then
                    printf '%b%b━%b' "$LC" "$BOLD" "$NC"
                elif (( RANDOM % 4 == 0 )); then
                    local sc="${STAR_COLS[$((RANDOM%${#STAR_COLS[@]}))]}"
                    printf '%b%s%b' "$sc" "${STARS[$((RANDOM%${#STARS[@]}))]}" "$NC"
                else
                    printf ' '
                fi
            done
            printf '\n'
        done
        sleep_ms 90
    done
 
    sleep_ms 150
    clear
 
    # ── ASTRA logo reveal (line by line, colour-shifting) ──
    # ASCII art for "ASTRA"
    local ASTRA_L1='     ▄▄▄·  .▄▄ ·▄▄▄▄▄▄▄  ▄▄▄   ▄▄▄· '
    local ASTRA_L2='    ▐█ ▀█ ▐█ ▀.•██  ▀▄ █·▀▄ █·▐█ ▀█ '
    local ASTRA_L3='    ▄█▀▀█ ▄▀▀▀█▄▐█.▪▐▀▀▄ ▐▀▀▄ ▄█▀▀█ '
    local ASTRA_L4='    ▐█ ▪▐▌▐█▄▪▐█▐█▌·▐█•█▌▐█•█▌▐█ ▪▐▌'
    local ASTRA_L5='     ▀  ▀  ▀▀▀▀ ▀▀▀ .▀  ▀.▀  ▀ ▀  ▀ '
 
    local ACOLS=("$LC" "$LB" "$W" "$LB" "$LC")
    local ALINES=("$ASTRA_L1" "$ASTRA_L2" "$ASTRA_L3" "$ASTRA_L4" "$ASTRA_L5")
 
    echo ""
    echo ""
    local i
    for ((i=0;i<5;i++)); do
        printf '  %b%b%s%b\n' "${ACOLS[$i]}" "$BOLD" "${ALINES[$i]}" "$NC"
        sleep_ms 80
    done
 
    echo ""
    sleep_ms 150
 
    # Sub-title typewriter
    printf '  %b%b' "$DIM" "$W"
    type_text "  ✦  Pterodactyl Automated Installer  ✦" "$W" 22
    printf '%b' "$NC"
    echo ""
 
    anim_sep "$LC"
 
    fade_lines 110 \
        "  ${DIM}  Panel · Wings · Blueprint · Firewall Manager${NC}" \
        "  ${DIM}  Ubuntu 20.04 / 22.04 / 24.04  ·  Debian 11 / 12${NC}" \
        "  ${DIM}  by JishnuTech${NC}"
 
    anim_sep "$LC"
    echo ""
    sleep_ms 700
    show_cursor
}
 
# ═══════════════════════════════════════════════════════════════
# STATIC BANNER  (used on every menu redraw — no delay)
# ═══════════════════════════════════════════════════════════════
 
print_banner() {
    clear
    echo ""
    printf '%b%b' "$LC" "$BOLD"
    echo '     ▄▄▄·  .▄▄ ·▄▄▄▄▄▄▄  ▄▄▄   ▄▄▄· '
    echo '    ▐█ ▀█ ▐█ ▀.•██  ▀▄ █·▀▄ █·▐█ ▀█ '
    echo '    ▄█▀▀█ ▄▀▀▀█▄▐█.▪▐▀▀▄ ▐▀▀▄ ▄█▀▀█ '
    echo '    ▐█ ▪▐▌▐█▄▪▐█▐█▌·▐█•█▌▐█•█▌▐█ ▪▐▌'
    echo '     ▀  ▀  ▀▀▀▀ ▀▀▀ .▀  ▀.▀  ▀ ▀  ▀ '
    printf '%b\n' "$NC"
    printf '  %b  ✦  Pterodactyl Automated Installer  ·  by JishnuTech  ✦%b\n' "$DIM$W" "$NC"
    echo ""
    printf '  %b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$LC" "$NC"
    printf '  %b  Panel · Wings · Blueprint · Firewall Manager%b\n' "$DIM" "$NC"
    printf '  %b  Ubuntu 20.04/22.04/24.04 · Debian 11/12%b\n' "$DIM" "$NC"
    printf '  %b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$LC" "$NC"
    echo ""
}
 
# ═══════════════════════════════════════════════════════════════
# LOG HELPERS
# ═══════════════════════════════════════════════════════════════
 
_log() { printf '%b\n' "$*" | tee -a "$LOG_FILE" >/dev/null; }
 
log_info()    { printf '  %b[✦ INFO]%b   %s\n' "$LG" "$NC" "$*"; _log "[INFO]  $*"; }
log_warn()    { printf '  %b[⚠ WARN]%b   %s\n' "$Y"  "$NC" "$*"; _log "[WARN]  $*"; }
log_error()   { printf '  %b[✖ ERROR]%b  %s\n' "$LR" "$NC" "$*"; _log "[ERROR] $*"; }
 
log_success() {
    printf '  %b%b[✔]%b ' "$LG" "$BOLD" "$NC"
    type_text "$*" "$LG" 18
    _log "[OK]    $*"
}
 
log_step() {
    printf '\n  %b%b  ◈  %b' "$LC" "$BOLD" "$NC"
    wipe_in "$*" "$W"
    printf '  %b' "$DIM"
    local i; for ((i=0;i<48;i++)); do printf '─'; sleep_ms 5; done
    printf '%b\n' "$NC"
    _log "==> $*"
}
 
log_fire() {
    printf '  %b%b✦ %b' "$LM" "$BOLD" "$NC"
    type_text "$*" "$Y" 22
}
 
# Run a command, show spinner, log output
run_cmd() {
    local label="$1"; shift
    _log "RUN: $*"
    set +e
    ("$@" >> "$LOG_FILE" 2>&1) &
    local pid=$!
    spinner $pid "$label"
    wait $pid
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        log_error "$label — failed (exit $rc). See $LOG_FILE"
        return $rc
    fi
    log_success "$label"
    return 0
}
 
# ═══════════════════════════════════════════════════════════════
# SYSTEM CHECKS
# ═══════════════════════════════════════════════════════════════
 
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        printf '\n  %b[✖]%b Must run as root: %bsudo bash %s%b\n\n' \
            "$LR" "$NC" "$BOLD" "$0" "$NC"
        exit 1
    fi
    mkdir -p /var/log
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
}
 
detect_os() {
    log_step "Detecting OS"
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release not found."
        exit 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    OS="${ID}"
    OS_VER="${VERSION_ID}"
    log_info "OS: ${PRETTY_NAME:-$OS $OS_VER}"
 
    case "$OS" in
        ubuntu)
            case "$OS_VER" in
                20.04|22.04|24.04) ;;
                *) log_warn "Ubuntu $OS_VER: untested. Proceeding…" ;;
            esac ;;
        debian)
            case "$OS_VER" in
                11|12) ;;
                *) log_warn "Debian $OS_VER: untested. Proceeding…" ;;
            esac ;;
        *)
            log_error "Unsupported OS: $OS (need Ubuntu or Debian)"
            exit 1 ;;
    esac
}
 
check_requirements() {
    log_step "Checking system resources"
    local RAM_MB DISK_GB
    RAM_MB=$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)
    DISK_GB=$(df / --output=avail -BG | tail -1 | tr -d 'G ')
 
    printf '  %b  RAM:  %b' "$LC" "$NC"
    local i
    for ((i=0;i<=RAM_MB;i+=RAM_MB/20+1)); do
        printf '\r  %b  RAM:  %b%b%d MB%b   ' "$LC" "$NC" "$LG$BOLD" "$i" "$NC"
        sleep_ms 35
    done
    printf '\r  %b  RAM:  %b%b%d MB%b\n' "$LC" "$NC" "$LG$BOLD" "$RAM_MB" "$NC"
 
    printf '  %b  Disk: %b' "$LC" "$NC"
    for ((i=0;i<=DISK_GB;i+=DISK_GB/20+1)); do
        printf '\r  %b  Disk: %b%b%d GB%b   ' "$LC" "$NC" "$LG$BOLD" "$i" "$NC"
        sleep_ms 35
    done
    printf '\r  %b  Disk: %b%b%d GB free%b\n' "$LC" "$NC" "$LG$BOLD" "$DISK_GB" "$NC"
 
    [[ $RAM_MB  -lt $MIN_RAM_MB  ]] && log_warn "Low RAM (${RAM_MB}MB). Recommend ≥${MIN_RAM_MB}MB."
    [[ $DISK_GB -lt $MIN_DISK_GB ]] && log_warn "Low disk (${DISK_GB}GB). Recommend ≥${MIN_DISK_GB}GB."
    sleep_ms 200
}
 
# Detect best PHP version available for the OS
detect_php_ver() {
    # Try 8.3 → 8.2 → 8.1 in order
    local v
    for v in 8.3 8.2 8.1; do
        if apt-cache show "php${v}" >/dev/null 2>&1; then
            PHP_VER="$v"
            log_info "PHP version selected: ${PHP_VER}"
            return 0
        fi
    done
    PHP_VER="8.1"
    log_warn "Could not auto-detect PHP version. Defaulting to ${PHP_VER}."
}
 
update_system() {
    log_step "Updating system packages"
    run_cmd "apt-get update" apt-get update -y
    run_cmd "apt-get upgrade" apt-get upgrade -y
    run_cmd "Install core deps" apt-get install -y \
        curl wget git unzip tar zip \
        software-properties-common apt-transport-https \
        ca-certificates gnupg lsb-release \
        ufw iptables iptables-persistent \
        supervisor cron
}
 
# ═══════════════════════════════════════════════════════════════
# FIREWALL
# ═══════════════════════════════════════════════════════════════
 
fw_open() {
    local PORT="$1" PROTO="${2:-tcp}"
    ufw allow "${PORT}/${PROTO}" >/dev/null 2>&1 || true
    iptables  -I INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT 2>/dev/null || true
    ip6tables -I INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT 2>/dev/null || true
    printf '  %b  ✦%b  Port %b%s/%s%b opened\n' "$LG" "$NC" "$BOLD$W" "$PORT" "$PROTO" "$NC"
    sleep_ms 60
}
 
fw_range() {
    local FROM="$1" TO="$2" PROTO="${3:-tcp}"
    ufw allow "${FROM}:${TO}/${PROTO}" >/dev/null 2>&1 || true
    iptables  -I INPUT -p "$PROTO" --dport "${FROM}:${TO}" -j ACCEPT 2>/dev/null || true
    ip6tables -I INPUT -p "$PROTO" --dport "${FROM}:${TO}" -j ACCEPT 2>/dev/null || true
    printf '  %b  ✦%b  Range %b%s-%s/%s%b opened\n' "$LG" "$NC" "$BOLD$W" "$FROM" "$TO" "$PROTO" "$NC"
    sleep_ms 60
}
 
setup_ufw() {
    log_step "Configuring UFW firewall"
    ufw --force reset  >/dev/null 2>&1 || true
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    fw_open 22 tcp        # SSH — always keep
    ufw --force enable >/dev/null 2>&1 || true
    log_success "UFW initialised (SSH port 22 preserved)."
}
 
open_panel_ports() {
    log_step "Opening Panel ports (HTTP/HTTPS)"
    fw_open 80  tcp
    fw_open 443 tcp
    log_success "Panel ports open: 80/tcp, 443/tcp"
}
 
open_wings_ports() {
    log_step "Opening Wings ports"
    fw_open 8080 tcp   # Wings HTTPS API
    fw_open 2022 tcp   # SFTP
    log_success "Wings ports open: 8080/tcp, 2022/tcp"
}
 
open_mc_ports() {
    log_step "Opening Minecraft server ports"
    fw_open  25565 tcp; fw_open  25565 udp  # Java default
    fw_open  19132 udp                       # Bedrock default
    fw_range 25500 25600 tcp; fw_range 25500 25600 udp  # Java alloc range
    fw_range 19000 19200 udp                             # Bedrock alloc range
    log_success "Minecraft ports open."
    fade_lines 70 \
        "  ${DIM}  Java default:       ${W}25565/tcp+udp${NC}" \
        "  ${DIM}  Bedrock default:    ${W}19132/udp${NC}" \
        "  ${DIM}  Java alloc range:   ${W}25500-25600/tcp+udp${NC}" \
        "  ${DIM}  Bedrock alloc range:${W}19000-19200/udp${NC}"
    log_warn "Remember: add these IPs/ports in Panel → Admin → Nodes → Allocations"
}
 
firewall_menu() {
    while true; do
        print_banner
        printf '  %b%b' "$LC" "$BOLD"; type_text "[ 🔥 FIREWALL PORT MANAGER ]" "$LC" 20
        echo ""
        printf '  %b  UFW + iptables manager for Pterodactyl & Minecraft%b\n' "$DIM" "$NC"
        echo ""
        fade_lines 55 \
            "  ${LG}  1)${NC}  ${BOLD}Open Panel ports${NC}         ${DIM}80, 443${NC}" \
            "  ${LG}  2)${NC}  ${BOLD}Open Wings ports${NC}         ${DIM}8080, 2022${NC}" \
            "  ${LG}  3)${NC}  ${BOLD}Open Minecraft ports${NC}     ${DIM}25565, 19132, 25500-25600, 19000-19200${NC}" \
            "  ${LG}  4)${NC}  ${BOLD}Open ALL ports${NC}           ${DIM}Panel + Wings + Minecraft${NC}" \
            "  ${LG}  5)${NC}  ${BOLD}Open custom port${NC}" \
            "  ${LG}  6)${NC}  ${BOLD}Open custom port range${NC}" \
            "  ${LC}  7)${NC}  ${BOLD}Show UFW status${NC}" \
            "  ${R}   8)${NC}  ${BOLD}Back to main menu${NC}"
        echo ""
        show_cursor
        printf '  %b%bChoice [1-8]:%b ' "$W" "$BOLD" "$NC"; read -r FW
 
        case "$FW" in
            1) open_panel_ports; _pause ;;
            2) open_wings_ports; _pause ;;
            3) open_mc_ports;    _pause ;;
            4) open_panel_ports; open_wings_ports; open_mc_ports
               log_fire "All ports opened!"; _pause ;;
            5) show_cursor
               printf '  %bPort number:%b '   "$W" "$NC"; read -r CP
               printf '  %bProtocol [tcp/udp/both, default tcp]:%b ' "$W" "$NC"; read -r CPRO
               CPRO="${CPRO:-tcp}"
               if [[ "$CPRO" == "both" ]]; then fw_open "$CP" tcp; fw_open "$CP" udp
               else fw_open "$CP" "$CPRO"; fi
               _pause ;;
            6) show_cursor
               printf '  %bStart port:%b ' "$W" "$NC"; read -r P1
               printf '  %bEnd port:%b   ' "$W" "$NC"; read -r P2
               printf '  %bProtocol [tcp/udp/both, default tcp]:%b ' "$W" "$NC"; read -r RPRO
               RPRO="${RPRO:-tcp}"
               if [[ "$RPRO" == "both" ]]; then fw_range "$P1" "$P2" tcp; fw_range "$P1" "$P2" udp
               else fw_range "$P1" "$P2" "$RPRO"; fi
               _pause ;;
            7) echo ""; ufw status verbose 2>/dev/null || log_warn "UFW not active."; _pause ;;
            8) return ;;
            *) log_warn "Enter 1–8."; sleep_ms 700 ;;
        esac
    done
}
 
# ═══════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════
 
_pause() {
    echo ""
    show_cursor
    printf '  %bPress [Enter] to continue…%b' "$DIM" "$NC"
    read -r
}
 
prompt_yn() {
    show_cursor
    local ans
    while true; do
        printf '  %b%b?%b  %s %b[y/n]%b: ' "$Y" "$BOLD" "$NC" "$1" "$DIM" "$NC"
        read -r ans
        case "${ans,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) printf '  %b  → type y or n%b\n' "$Y" "$NC" ;;
        esac
    done
}
 
success_box() {
    local title="$1"
    echo ""
    hide_cursor
    local TOP="  ${LG}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    local MID="  ${LG}${BOLD}║   ${title}${NC}"
    local BOT="  ${LG}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    printf '%b\n' "$TOP"; sleep_ms 70
    printf '%b\n' "$MID"; sleep_ms 70
    printf '%b\n' "$BOT"; sleep_ms 150
    local f
    for f in 1 2 3; do
        printf '\r  %b%b🌟  %s  🌟%b   ' "$Y" "$BOLD" "$title" "$NC"; sleep_ms 280
        printf '\r  %b%b✦   %s   ✦%b   ' "$LC" "$BOLD" "$title" "$NC"; sleep_ms 280
    done
    printf '\r  %b%b✦   %s   ✦%b\n' "$LG" "$BOLD" "$title" "$NC"
    echo ""
    show_cursor
}
 
# ═══════════════════════════════════════════════════════════════
# PHP & REPO SETUP
# ═══════════════════════════════════════════════════════════════
 
install_php_repo() {
    log_step "Adding PHP repository"
    case "$OS" in
        ubuntu)
            run_cmd "Add ondrej/php PPA" bash -c \
                'add-apt-repository -y ppa:ondrej/php >> '"$LOG_FILE"' 2>&1'
            ;;
        debian)
            run_cmd "Import sury.org key" bash -c \
                'curl -fsSL https://packages.sury.org/php/apt.gpg \
                 | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg'
            run_cmd "Add sury.org repo" bash -c \
                'echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] \
                 https://packages.sury.org/php/ $(lsb_release -sc) main" \
                 > /etc/apt/sources.list.d/sury-php.list'
            ;;
    esac
    run_cmd "apt-get update (PHP repo)" apt-get update -y
}
 
install_php() {
    log_step "Installing PHP ${PHP_VER}"
    local EXTS="cli gd mysql pdo mbstring tokenizer bcmath xml fpm curl zip intl"
    local PKGS=()
    local e
    for e in $EXTS; do PKGS+=("php${PHP_VER}-${e}"); done
    run_cmd "Install PHP ${PHP_VER}" apt-get install -y "php${PHP_VER}" "${PKGS[@]}"
    animate_progress "PHP ${PHP_VER} setup" 20
    log_success "PHP ${PHP_VER} installed."
 
    # Ensure FPM socket path is right
    systemctl enable "php${PHP_VER}-fpm" --now >> "$LOG_FILE" 2>&1 || true
}
 
# ═══════════════════════════════════════════════════════════════
# MARIADB
# ═══════════════════════════════════════════════════════════════
 
install_mariadb() {
    log_step "Installing MariaDB"
    run_cmd "Install MariaDB" apt-get install -y mariadb-server
    systemctl enable mariadb --now >> "$LOG_FILE" 2>&1
 
    log_step "Securing MariaDB & creating database"
    local DB_ROOT_PASS="$1"
    local DB_PTERO_PASS="$2"
 
    # Handle both auth_socket and password auth
    mysql -u root 2>/dev/null <<SQLEOF || \
    mysql -u root -p"${DB_ROOT_PASS}" 2>/dev/null <<SQLEOF2 || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE DATABASE IF NOT EXISTS panel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PTERO_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQLEOF
SQLEOF2
    animate_progress "MariaDB configuration" 15
    log_success "MariaDB ready. Database: panel / User: pterodactyl"
}
 
# ═══════════════════════════════════════════════════════════════
# REDIS
# ═══════════════════════════════════════════════════════════════
 
install_redis() {
    log_step "Installing Redis"
    run_cmd "Install Redis" apt-get install -y redis-server
    systemctl enable redis-server --now >> "$LOG_FILE" 2>&1
    log_success "Redis running."
}
 
# ═══════════════════════════════════════════════════════════════
# COMPOSER
# ═══════════════════════════════════════════════════════════════
 
install_composer() {
    log_step "Installing Composer"
    run_cmd "Download & install Composer" bash -c \
        'php -r "copy('"'"'https://getcomposer.org/installer'"'"', '"'"'composer-setup.php'"'"');"
         php composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
         php -r "unlink('"'"'composer-setup.php'"'"');"'
    log_success "Composer $(composer --version --no-ansi 2>/dev/null | head -1) ready."
}
 
# ═══════════════════════════════════════════════════════════════
# NGINX  (fully correct for Pterodactyl)
# ═══════════════════════════════════════════════════════════════
 
install_nginx() {
    log_step "Installing Nginx"
    # Remove apache2 if present (common conflict)
    apt-get remove -y apache2 apache2-* 2>/dev/null >> "$LOG_FILE" 2>&1 || true
    run_cmd "Install Nginx" apt-get install -y nginx
    systemctl enable nginx --now >> "$LOG_FILE" 2>&1
    log_success "Nginx installed."
}
 
configure_nginx_ssl() {
    local FQDN="$1"
    local PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"
 
    log_step "Configuring Nginx for ${FQDN}"
 
    # Remove default
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default
 
    # Write the Pterodactyl vhost — SSL version (used after certbot)
    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINXEOF
# ── Pterodactyl Panel — generated by ASTRA installer ──────────
server {
    listen 80;
    listen [::]:80;
    server_name ${FQDN};
 
    # Redirect all HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}
 
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${FQDN};
 
    root ${PANEL_DIR}/public;
    index index.php;
 
    # ── Logging ────────────────────────────────────────────────
    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log warn;
 
    # ── SSL (Let's Encrypt) ────────────────────────────────────
    ssl_certificate     /etc/letsencrypt/live/${FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FQDN}/privkey.pem;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_stapling        on;
    ssl_stapling_verify on;
 
    # ── Security Headers ───────────────────────────────────────
    add_header X-Content-Type-Options  "nosniff"            always;
    add_header X-XSS-Protection        "1; mode=block"      always;
    add_header X-Frame-Options         "SAMEORIGIN"         always;
    add_header X-Robots-Tag            "none"               always;
    add_header Referrer-Policy         "same-origin"        always;
    add_header Content-Security-Policy "frame-ancestors 'self'" always;
 
    # ── Uploads ────────────────────────────────────────────────
    client_max_body_size  100m;
    client_body_timeout   120s;
    sendfile              off;
 
    # ── Laravel routing ────────────────────────────────────────
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
 
    # ── Static assets — aggressive cache ──────────────────────
    location ~* \.(css|js|gif|img|ico|jpeg|jpg|png|svg|webp|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
 
    # ── PHP-FPM ────────────────────────────────────────────────
    location ~ \.php$ {
        fastcgi_split_path_info  ^(.+\.php)(/.+)$;
        fastcgi_pass             unix:${PHP_SOCK};
        fastcgi_index            index.php;
        include                  fastcgi_params;
        fastcgi_param            SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param            HTTP_PROXY      "";
        fastcgi_param            PHP_VALUE       "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size      16k;
        fastcgi_buffers          4 16k;
        fastcgi_connect_timeout  300;
        fastcgi_send_timeout     300;
        fastcgi_read_timeout     300;
    }
 
    # ── Deny dot-files ─────────────────────────────────────────
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGINXEOF
 
    ln -sf /etc/nginx/sites-available/pterodactyl.conf \
           /etc/nginx/sites-enabled/pterodactyl.conf
 
    # Verify config is valid
    if ! nginx -t >> "$LOG_FILE" 2>&1; then
        log_error "Nginx config test failed! Check $LOG_FILE"
        cat /var/log/nginx/error.log 2>/dev/null | tail -20 >> "$LOG_FILE"
        return 1
    fi
    log_success "Nginx config written and validated."
}
 
configure_nginx_nossl() {
    # Temporary HTTP-only vhost for certbot webroot / panel access before SSL
    local FQDN="$1"
    local PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"
 
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default
 
    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${FQDN};
 
    root ${PANEL_DIR}/public;
    index index.php;
 
    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log warn;
 
    client_max_body_size 100m;
    client_body_timeout  120s;
    sendfile             off;
 
    location /.well-known/acme-challenge/ { allow all; }
 
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
 
    location ~ \.php$ {
        fastcgi_split_path_info  ^(.+\.php)(/.+)$;
        fastcgi_pass             unix:${PHP_SOCK};
        fastcgi_index            index.php;
        include                  fastcgi_params;
        fastcgi_param            SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param            HTTP_PROXY      "";
        fastcgi_param            PHP_VALUE       "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size      16k;
        fastcgi_buffers          4 16k;
        fastcgi_connect_timeout  300;
        fastcgi_send_timeout     300;
        fastcgi_read_timeout     300;
    }
 
    location ~ /\.(?!well-known).* { deny all; }
}
NGINXEOF
 
    ln -sf /etc/nginx/sites-available/pterodactyl.conf \
           /etc/nginx/sites-enabled/pterodactyl.conf
 
    nginx -t >> "$LOG_FILE" 2>&1 || { log_error "Nginx config invalid"; return 1; }
    systemctl reload nginx >> "$LOG_FILE" 2>&1
    log_success "Nginx (HTTP-only) configured and reloaded."
}
 
obtain_ssl() {
    local FQDN="$1" EMAIL="$2"
    log_step "Obtaining Let's Encrypt SSL certificate"
    run_cmd "Install Certbot" apt-get install -y certbot python3-certbot-nginx
 
    # Use webroot method first (more reliable), fall back to nginx plugin
    certbot certonly \
        --webroot \
        --webroot-path="${PANEL_DIR}/public" \
        --agree-tos \
        --no-eff-email \
        -m "$EMAIL" \
        -d "$FQDN" \
        --non-interactive \
        >> "$LOG_FILE" 2>&1 \
    || certbot certonly \
        --standalone \
        --agree-tos \
        --no-eff-email \
        -m "$EMAIL" \
        -d "$FQDN" \
        --non-interactive \
        --pre-hook  "systemctl stop nginx" \
        --post-hook "systemctl start nginx" \
        >> "$LOG_FILE" 2>&1 \
    || {
        log_warn "SSL certificate could not be obtained automatically."
        log_warn "You can run: certbot certonly --nginx -d ${FQDN} manually later."
        return 1
    }
 
    log_success "SSL certificate obtained for ${FQDN}."
    # Setup auto-renewal
    (crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") \
        | sort -u | crontab - 2>/dev/null
    log_info "Auto-renewal cron job added."
    return 0
}
 
# ═══════════════════════════════════════════════════════════════
# PANEL INSTALLER
# ═══════════════════════════════════════════════════════════════
 
install_panel() {
    print_banner
    printf '  %b%b' "$LC" "$BOLD"; type_text "[ ✦ PANEL INSTALLER ]" "$LC" 22
    echo ""
    log_warn "Installs: Nginx · PHP ${PHP_VER} · MariaDB · Redis · Composer · Let's Encrypt SSL"
    echo ""
    show_cursor
 
    # ── Collect inputs ────────────────────────────────
    printf '  %b  Domain %b(e.g. panel.example.com)%b: ' "$W$BOLD" "$DIM" "$NC"; read -r PANEL_FQDN
    [[ -z "$PANEL_FQDN" ]] && { log_error "Domain is required."; _pause; return; }
 
    printf '  %b  Admin email %b(for SSL & account)%b: '  "$W$BOLD" "$DIM" "$NC"; read -r ADMIN_EMAIL
    [[ -z "$ADMIN_EMAIL" ]] && { log_error "Email is required."; _pause; return; }
 
    printf '  %b  Admin username %b[default: admin]%b: '  "$W$BOLD" "$DIM" "$NC"; read -r ADMIN_USER
    ADMIN_USER="${ADMIN_USER:-admin}"
 
    printf '  %b  Admin password %b(hidden)%b: '          "$W$BOLD" "$DIM" "$NC"
    read -rs ADMIN_PASS; echo ""
    [[ -z "$ADMIN_PASS" ]] && { log_error "Password is required."; _pause; return; }
 
    printf '  %b  First name %b[default: Admin]%b: '      "$W$BOLD" "$DIM" "$NC"; read -r ADMIN_FIRST
    ADMIN_FIRST="${ADMIN_FIRST:-Admin}"
 
    printf '  %b  Last name %b[default: User]%b: '        "$W$BOLD" "$DIM" "$NC"; read -r ADMIN_LAST
    ADMIN_LAST="${ADMIN_LAST:-User}"
 
    printf '  %b  DB root password %b(new)%b: '           "$W$BOLD" "$DIM" "$NC"
    read -rs DB_ROOT; echo ""
    [[ -z "$DB_ROOT" ]] && { log_error "DB root password required."; _pause; return; }
 
    printf '  %b  DB pterodactyl password %b(new)%b: '    "$W$BOLD" "$DIM" "$NC"
    read -rs DB_PASS; echo ""
    [[ -z "$DB_PASS" ]] && { log_error "DB pterodactyl password required."; _pause; return; }
 
    printf '  %b  Timezone %b[default: UTC]%b: '          "$W$BOLD" "$DIM" "$NC"; read -r TZ_IN
    TIMEZONE="${TZ_IN:-UTC}"
 
    echo ""
    anim_sep "$C"
    fade_lines 75 \
        "  ${LC}${BOLD}  Installation Summary${NC}" \
        "  ${W}  Domain:   ${BOLD}${PANEL_FQDN}${NC}" \
        "  ${W}  Email:    ${BOLD}${ADMIN_EMAIL}${NC}" \
        "  ${W}  Username: ${BOLD}${ADMIN_USER}${NC}" \
        "  ${W}  Timezone: ${BOLD}${TIMEZONE}${NC}"
    anim_sep "$C"
    echo ""
 
    prompt_yn "Start Panel installation?" || { _pause; return; }
 
    detect_os
    check_requirements
    update_system
    install_php_repo
    detect_php_ver
    install_php
    install_mariadb "$DB_ROOT" "$DB_PASS"
    install_redis
    install_nginx
    install_composer
    setup_ufw
    open_panel_ports
 
    # ── Download Panel ────────────────────────────────
    log_step "Downloading Pterodactyl Panel"
    run_cmd "Create directory" bash -c "mkdir -p ${PANEL_DIR}"
    run_cmd "Download panel archive" bash -c \
        "curl -Lo /tmp/panel.tar.gz \
         'https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz'"
    run_cmd "Extract panel archive" bash -c \
        "tar -xzf /tmp/panel.tar.gz -C ${PANEL_DIR} && rm /tmp/panel.tar.gz"
    run_cmd "Set storage permissions" bash -c \
        "chmod -R 755 ${PANEL_DIR}/storage ${PANEL_DIR}/bootstrap/cache"
    animate_progress "Panel extraction" 20
    log_success "Panel downloaded and extracted."
 
    # ── Configure .env ────────────────────────────────
    log_step "Configuring Panel environment"
    cd "$PANEL_DIR"
 
    run_cmd "Copy .env" cp .env.example .env
 
    run_cmd "Composer install" bash -c \
        "cd ${PANEL_DIR} && COMPOSER_ALLOW_SUPERUSER=1 \
         composer install --no-dev --optimize-autoloader --no-interaction --no-progress 2>&1"
 
    run_cmd "Generate app key" bash -c \
        "cd ${PANEL_DIR} && php artisan key:generate --force"
 
    # Write env values properly (artisan env:set style via sed)
    local ENV="${PANEL_DIR}/.env"
    sed -i "s|APP_ENV=.*|APP_ENV=production|"                              "$ENV"
    sed -i "s|APP_DEBUG=.*|APP_DEBUG=false|"                               "$ENV"
    sed -i "s|APP_URL=.*|APP_URL=https://${PANEL_FQDN}|"                   "$ENV"
    sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=${TIMEZONE}|"                   "$ENV"
    sed -i "s|DB_CONNECTION=.*|DB_CONNECTION=mysql|"                       "$ENV"
    sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|"                              "$ENV"
    sed -i "s|DB_PORT=.*|DB_PORT=3306|"                                    "$ENV"
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=panel|"                           "$ENV"
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|"                     "$ENV"
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|"                     "$ENV"
    sed -i "s|CACHE_DRIVER=.*|CACHE_DRIVER=redis|"                         "$ENV"
    sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=redis|"                     "$ENV"
    sed -i "s|QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|"                 "$ENV"
    sed -i "s|REDIS_HOST=.*|REDIS_HOST=127.0.0.1|"                        "$ENV"
    sed -i "s|REDIS_PORT=.*|REDIS_PORT=6379|"                              "$ENV"
    # Mail — default to log driver (user can change later)
    sed -i "s|MAIL_MAILER=.*|MAIL_MAILER=log|"                             "$ENV"
 
    log_success ".env configured."
 
    # ── Migrations ────────────────────────────────────
    run_cmd "Run DB migrations" bash -c \
        "cd ${PANEL_DIR} && php artisan migrate --seed --force"
    animate_progress "Database migration" 25
 
    # ── Admin user ────────────────────────────────────
    run_cmd "Create admin user" bash -c \
        "cd ${PANEL_DIR} && php artisan p:user:make \
         --email='${ADMIN_EMAIL}' \
         --username='${ADMIN_USER}' \
         --name-first='${ADMIN_FIRST}' \
         --name-last='${ADMIN_LAST}' \
         --password='${ADMIN_PASS}' \
         --admin=1"
 
    # ── Permissions ───────────────────────────────────
    log_step "Setting file permissions"
    run_cmd "chown www-data" bash -c \
        "chown -R www-data:www-data ${PANEL_DIR}
         find ${PANEL_DIR} -type f -exec chmod 644 {} \;
         find ${PANEL_DIR} -type d -exec chmod 755 {} \;
         chmod -R 755 ${PANEL_DIR}/storage ${PANEL_DIR}/bootstrap/cache"
    log_success "Permissions set."
 
    # ── Queue worker (cron + supervisor) ──────────────
    log_step "Configuring queue worker & scheduler"
    # Cron
    (crontab -l 2>/dev/null | grep -v 'pterodactyl'; \
     echo "* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1") \
        | crontab - 2>/dev/null
 
    # Supervisor
    cat > /etc/supervisor/conf.d/pteroq.conf <<SUPCONF
[program:pteroq]
process_name=%(program_name)s_%(process_num)02d
command=php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=2
redirect_stderr=true
stdout_logfile=${PANEL_DIR}/storage/logs/pteroq.log
SUPCONF
    run_cmd "Reload Supervisor" bash -c \
        "supervisorctl reread >> ${LOG_FILE} 2>&1
         supervisorctl update >> ${LOG_FILE} 2>&1
         supervisorctl start pteroq:* >> ${LOG_FILE} 2>&1 || true"
    log_success "Queue worker & scheduler configured."
 
    # ── Nginx (HTTP first, then SSL) ──────────────────
    configure_nginx_nossl "$PANEL_FQDN"
    run_cmd "Start Nginx (HTTP)" systemctl reload nginx
 
    # ── SSL ───────────────────────────────────────────
    local SSL_OK=true
    obtain_ssl "$PANEL_FQDN" "$ADMIN_EMAIL" || SSL_OK=false
 
    if $SSL_OK; then
        configure_nginx_ssl "$PANEL_FQDN"
        run_cmd "Reload Nginx (HTTPS)" systemctl reload nginx
        log_success "Nginx HTTPS vhost active."
    else
        log_warn "SSL skipped — panel running over HTTP only."
        log_warn "Run: certbot certonly --nginx -d ${PANEL_FQDN} after DNS propagates."
    fi
 
    # ── Final summary ─────────────────────────────────
    success_box "✦  PANEL INSTALLATION COMPLETE!"
    local PROTO="https"
    $SSL_OK || PROTO="http"
    fade_lines 85 \
        "  ${W}${BOLD}  Panel URL:${NC}   ${PROTO}://${PANEL_FQDN}" \
        "  ${W}${BOLD}  Username:${NC}    ${ADMIN_USER}" \
        "  ${W}${BOLD}  PHP:${NC}         ${PHP_VER}" \
        "  ${W}${BOLD}  Open ports:${NC}  22/tcp · 80/tcp · 443/tcp" \
        "" \
        "  ${DIM}  Next: install Wings on your node VPS (Option 2)${NC}" \
        "  ${DIM}  Log file: ${LOG_FILE}${NC}"
    echo ""
    _pause
}
 
# ═══════════════════════════════════════════════════════════════
# WINGS INSTALLER
# ═══════════════════════════════════════════════════════════════
 
install_wings() {
    print_banner
    printf '  %b%b' "$LC" "$BOLD"; type_text "[ ✦ WINGS INSTALLER ]" "$LC" 22
    echo ""
    log_warn "Installs: Docker · Wings binary · systemd service · Minecraft firewall ports"
    echo ""
 
    prompt_yn "Proceed with Wings installation?" || { _pause; return; }
 
    detect_os
    check_requirements
    update_system
    setup_ufw
    open_wings_ports
    open_mc_ports
 
    # ── Docker ────────────────────────────────────────
    log_step "Installing Docker"
    if command -v docker &>/dev/null; then
        log_info "Docker already installed — skipping."
    else
        run_cmd "Add Docker GPG key" bash -c \
            'curl -fsSL https://download.docker.com/linux/'"${OS}"'/gpg \
             | gpg --dearmor -o /usr/share/keyrings/docker.gpg'
        run_cmd "Add Docker repo" bash -c \
            'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
             https://download.docker.com/linux/'"${OS}"' \
             $(lsb_release -cs) stable" \
             > /etc/apt/sources.list.d/docker.list'
        run_cmd "apt update (Docker repo)" apt-get update -y
        run_cmd "Install Docker CE" apt-get install -y \
            docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable docker --now >> "$LOG_FILE" 2>&1
        animate_progress "Docker installation" 22
        log_success "Docker installed."
    fi
 
    # ── Wings binary ──────────────────────────────────
    log_step "Downloading Wings"
    local ARCH
    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="amd64" || ARCH="arm64"
    run_cmd "Create /etc/pterodactyl" bash -c "mkdir -p /etc/pterodactyl"
    run_cmd "Download Wings binary (${ARCH})" bash -c \
        "curl -Lo /usr/local/bin/wings \
         'https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH}'"
    run_cmd "Make Wings executable" chmod u+x /usr/local/bin/wings
    animate_progress "Wings download" 15
    log_success "Wings binary ready (${ARCH})."
 
    # ── systemd service ───────────────────────────────
    log_step "Creating Wings systemd service"
    cat > /etc/systemd/system/wings.service <<WINGSVC
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service
 
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
 
[Install]
WantedBy=multi-user.target
WINGSVC
    run_cmd "systemd daemon-reload" systemctl daemon-reload
    run_cmd "Enable Wings service"  systemctl enable wings
    log_success "Wings service enabled (will start after config)."
 
    success_box "✦  WINGS INSTALLATION COMPLETE!"
    fade_lines 78 \
        "  ${W}${BOLD}  Firewall ports open:${NC}" \
        "  ${LC}    22/tcp${NC}              SSH" \
        "  ${LC}    8080/tcp${NC}             Wings HTTPS API  (Panel ↔ Node)" \
        "  ${LC}    2022/tcp${NC}             SFTP" \
        "  ${LC}    25565/tcp+udp${NC}        Minecraft Java (default)" \
        "  ${LC}    19132/udp${NC}             Minecraft Bedrock (default)" \
        "  ${LC}    25500-25600/tcp+udp${NC}   Java allocation range" \
        "  ${LC}    19000-19200/udp${NC}        Bedrock allocation range" \
        "" \
        "  ${W}${BOLD}  Next steps:${NC}" \
        "  ${LC}  1.${NC} Panel → Admin → Nodes → Create node" \
        "  ${LC}  2.${NC} Node → 'Configuration' tab → copy the token" \
        "  ${LC}  3.${NC} Run on THIS VPS:" \
        "     ${BOLD}    wings configure --panel-url https://panel.yourdomain.com --token TOKEN${NC}" \
        "  ${LC}  4.${NC} ${BOLD}systemctl start wings${NC}" \
        "  ${LC}  5.${NC} ${BOLD}systemctl status wings${NC}" \
        "  ${LC}  6.${NC} Panel → Nodes → Allocations → add IP with ports ${BOLD}25500–25600${NC}"
    echo ""
    _pause
}
 
# ═══════════════════════════════════════════════════════════════
# BLUEPRINT INSTALLER
# ═══════════════════════════════════════════════════════════════
 
install_blueprint() {
    print_banner
    printf '  %b%b' "$LC" "$BOLD"; type_text "[ ✦ BLUEPRINT INSTALLER ]" "$LC" 22
    echo ""
    log_warn "Blueprint is an addon/extension framework for Pterodactyl Panel."
    log_warn "Requires Panel installed at ${PANEL_DIR}"
    echo ""
 
    if [[ ! -d "$PANEL_DIR" ]]; then
        log_error "Panel not found at ${PANEL_DIR}. Run Option 1 first."
        _pause; return
    fi
    if [[ ! -f "${PANEL_DIR}/artisan" ]]; then
        log_error "Panel seems incomplete (no artisan). Re-install the Panel."
        _pause; return
    fi
 
    prompt_yn "Proceed with Blueprint installation?" || { _pause; return; }
 
    # ── Fetch version ─────────────────────────────────
    log_step "Fetching latest Blueprint release"
    local BP_VER BP_URL BP_ZIP
    BP_VER=$(curl -fsSL \
        "https://api.github.com/repos/BlueprintFramework/framework/releases/latest" \
        | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null) \
    || BP_VER=""
 
    if [[ -n "$BP_VER" ]]; then
        BP_URL="https://github.com/BlueprintFramework/framework/releases/download/${BP_VER}/framework.zip"
        BP_ZIP="framework.zip"
        log_info "Blueprint version: ${BOLD}${BP_VER}${NC}"
    else
        log_warn "Could not fetch version — using main branch."
        BP_URL="https://github.com/BlueprintFramework/framework/archive/refs/heads/main.zip"
        BP_ZIP="blueprint-main.zip"
        BP_VER="(main branch)"
    fi
 
    # ── Download & install ────────────────────────────
    log_step "Downloading Blueprint"
    run_cmd "Download Blueprint ${BP_VER}" bash -c \
        "curl -Lo /tmp/${BP_ZIP} '${BP_URL}'"
    run_cmd "Extract Blueprint" bash -c \
        "cd ${PANEL_DIR} && unzip -o /tmp/${BP_ZIP} && rm -f /tmp/${BP_ZIP} /tmp/framework.zip"
    animate_progress "Blueprint extraction" 12
 
    log_step "Running Blueprint installer"
    run_cmd "Blueprint install script" bash -c \
        "cd ${PANEL_DIR} && chmod +x blueprint.sh && bash blueprint.sh"
    log_success "Blueprint installed."
 
    log_step "Fixing permissions"
    run_cmd "chown www-data" bash -c \
        "chown -R www-data:www-data ${PANEL_DIR}"
    log_success "Permissions fixed."
 
    success_box "✦  BLUEPRINT INSTALLATION COMPLETE!"
    fade_lines 85 \
        "  ${W}${BOLD}  Version:${NC}    ${BP_VER}" \
        "  ${W}${BOLD}  Extensions:${NC} https://blueprint.zip"
    echo ""
    _pause
}
 
# ═══════════════════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════════════════
 
main_menu() {
    while true; do
        print_banner
        printf '  %b%b'; type_text "  What would you like to do?" "$W$BOLD" 20
        echo ""
 
        fade_lines 50 \
            "  ${M}  ┌────────────────────────────────────────────────────────────────┐${NC}" \
            "  ${M}  │${NC}  ${LG}1)${NC}  ${BOLD}✦ Panel Installer${NC}           ${DIM}Nginx · PHP · MariaDB · SSL${NC}     ${M}│${NC}" \
            "  ${M}  │${NC}  ${LG}2)${NC}  ${BOLD}✦ Wings Installer${NC}           ${DIM}Docker · Wings · Node setup${NC}     ${M}│${NC}" \
            "  ${M}  │${NC}  ${LG}3)${NC}  ${BOLD}✦ Blueprint Installer${NC}       ${DIM}Addon framework for Panel${NC}       ${M}│${NC}" \
            "  ${M}  │${NC}  ${LC}4)${NC}  ${BOLD}🔥 Firewall Port Manager${NC}    ${DIM}UFW · iptables · MC ports${NC}       ${M}│${NC}" \
            "  ${M}  │${NC}  ${R} 5)${NC}  ${BOLD}🚪 Exit${NC}                                                         ${M}│${NC}" \
            "  ${M}  └────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        show_cursor
        printf '  %b%bEnter choice [1-5]:%b ' "$W" "$BOLD" "$NC"
        read -r CHOICE
 
        case "$CHOICE" in
            1) check_root; install_panel ;;
            2) check_root; install_wings ;;
            3) check_root; install_blueprint ;;
            4) check_root; firewall_menu ;;
            5)
                echo ""
                rainbow_echo "  ✦  ASTRA signing off — Happy hosting!  ✦"
                echo ""
                printf '  %b  https://pterodactyl.io  ·  by JishnuTech%b\n\n' "$DIM" "$NC"
                show_cursor; exit 0 ;;
            *)
                log_warn "Invalid choice. Enter 1–5."
                sleep_ms 700 ;;
        esac
    done
}
 
# ═══════════════════════════════════════════════════════════════
# ENTRY
# ═══════════════════════════════════════════════════════════════
 
check_root
mkdir -p /var/log && touch "$LOG_FILE"
boot_intro
main_menu
