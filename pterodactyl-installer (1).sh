#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║   ✦  A S T R A  — Pterodactyl Automated Installer  ✦       ║
# ║   Panel · Wings · Blueprint · Firewall Manager              ║
# ║   Ubuntu 20.04 / 22.04 / 24.04  ·  Debian 11 / 12          ║
# ║   by JishnuTech                                             ║
# ╚══════════════════════════════════════════════════════════════╝
# NOTE: NO set -e / set -u on purpose — they break animations,
#       subshells, and interactive prompts. All errors handled
#       explicitly via return-code checks.

# ── Colors ────────────────────────────────────────────────────
R='\033[0;31m';  LR='\033[1;31m'
G='\033[0;32m';  LG='\033[1;32m'
Y='\033[1;33m'
B='\033[0;34m';  LB='\033[1;34m'
M='\033[0;35m';  LM='\033[1;35m'
C='\033[0;36m';  LC='\033[1;36m'
W='\033[1;37m'
DIM='\033[2m';  BOLD='\033[1m'
NC='\033[0m'
HC='\033[?25l'   # hide cursor
SC='\033[?25h'   # show cursor
CL='\033[2K'     # clear line

# ── Globals ───────────────────────────────────────────────────
MIN_RAM=1024
MIN_DISK=10
OS_ID=""
OS_VER=""
PHP_VER="8.3"
PANEL_DIR="/var/www/pterodactyl"
LOG="/var/log/astra.log"

# ── Always restore cursor on exit / Ctrl+C ────────────────────
trap 'printf "%b\n" "${SC}"; tput cnorm 2>/dev/null; exit' EXIT
trap 'printf "%b\n" "${SC}"; tput cnorm 2>/dev/null; echo ""; exit 0' INT TERM

###############################################################
# ANIMATION PRIMITIVES
###############################################################

_hide() { printf '%b' "$HC"; tput civis 2>/dev/null; }
_show() { printf '%b' "$SC"; tput cnorm 2>/dev/null; }

# sleep_ms 80  →  sleep 0.080 s
_ms() {
    local s
    s=$(awk "BEGIN{printf \"%.3f\",${1:-100}/1000}")
    sleep "$s" 2>/dev/null || true
}

# type_text "string" COLOR DELAY_MS
type_text() {
    local txt="$1" col="${2:-$NC}" delay="${3:-25}" i
    printf '%b' "$col"
    for ((i=0; i<${#txt}; i++)); do
        printf '%s' "${txt:$i:1}"
        _ms "$delay"
    done
    printf '%b\n' "$NC"
}

# rainbow_echo "string"
rainbow_echo() {
    local txt="$1" i
    local cols=("$LR" "$Y" "$LG" "$LC" "$LB" "$M" "$LM")
    for ((i=0; i<${#txt}; i++)); do
        printf '%b%b%s' "${cols[$((i % ${#cols[@]}))]}" "$BOLD" "${txt:$i:1}"
        _ms 14
    done
    printf '%b\n' "$NC"
}

# wipe_in "string" COLOR
wipe_in() {
    local txt="$1" col="${2:-$W}" i
    for ((i=1; i<=${#txt}; i++)); do
        printf '\r  %b%b%s%b█%b   ' "$col" "$BOLD" "${txt:0:$i}" "$DIM" "$NC"
        _ms 18
    done
    printf '\r  %b%b%s%b   \n' "$col" "$BOLD" "$txt" "$NC"
}

# fade_lines DELAY "line" "line" ...
fade_lines() {
    local delay="$1"; shift
    local l
    for l in "$@"; do
        printf '%b\n' "$l"
        _ms "$delay"
    done
}

# anim_sep COLOR
anim_sep() {
    local col="${1:-$LC}" i
    printf '  %b' "$col"
    for ((i=0; i<62; i++)); do printf '━'; _ms 5; done
    printf '%b\n' "$NC"
}

# spinner PID "label"
spinner() {
    local pid=$1 msg="${2:-Working…}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local cols=("$LC" "$LM" "$LG" "$LB" "$Y" "$LC" "$LM" "$LG")
    local i=0
    _hide
    while kill -0 "$pid" 2>/dev/null; do
        local f="${frames[$((i % ${#frames[@]}))]}"
        local c="${cols[$((i % ${#cols[@]}))]}"
        printf '\r  %b%b%b%b  %b%s%b   ' "$c" "$BOLD" "$f" "$NC" "$W" "$msg" "$NC"
        _ms 80
        i=$(( i + 1 ))
    done
    printf '\r%b' "$CL"
    _show
}

# animate_progress "label" STEPS
animate_progress() {
    local lbl="${1:-Progress}" steps="${2:-25}" i col
    _hide
    for ((i=0; i<=steps; i++)); do
        local filled=$(( i * 40 / steps ))
        local empty=$(( 40 - filled ))
        local pct=$(( i * 100 / steps ))
        if   (( pct < 40 )); then col="$R"
        elif (( pct < 75 )); then col="$Y"
        else col="$LG"; fi
        local bar="" spc=""
        local j
        for ((j=0; j<filled; j++)); do bar="${bar}█"; done
        for ((j=0; j<empty;  j++)); do spc="${spc}░"; done
        printf '\r  %b%s%b  %b[%b%s%b%s%b]%b %b%d%%%b   ' \
            "$DIM" "$lbl" "$NC" \
            "$col" "$BOLD" "$bar" "$NC$DIM" "$spc" "$NC" \
            "$NC" "$W$BOLD" "$pct" "$NC"
        _ms 50
    done
    printf '\r%b  %b%b[✔]%b  %b%s%b\n' "$CL" "$LG" "$BOLD" "$NC" "$W" "$lbl" "$NC"
    _show
}

###############################################################
# BOOT INTRO
###############################################################

boot_intro() {
    _hide
    clear

    # Starfield frames
    local STARS=('·' '✦' '✧' '⋆' '★' '✶' '°' '*' '·' '✦')
    local SCOLS=("$LC" "$LB" "$W" "$LM" "$Y")
    local p r c sc st

    for p in $(seq 1 7); do
        clear
        for r in $(seq 1 8); do
            printf '  '
            for c in $(seq 1 72); do
                if (( RANDOM % 3 == 0 )); then
                    sc="${SCOLS[$((RANDOM % ${#SCOLS[@]}))]}"
                    st="${STARS[$((RANDOM % ${#STARS[@]}))]}"
                    printf '%b%b%s%b' "$sc" "$BOLD" "$st" "$NC"
                else
                    printf ' '
                fi
            done
            printf '\n'
        done
        _ms 65
    done

    # Meteor streaks
    local sr
    for p in $(seq 1 4); do
        clear
        sr=$(( RANDOM % 7 + 1 ))
        for r in $(seq 1 9); do
            printf '  '
            for c in $(seq 1 72); do
                if (( r == sr && c > 18 && c < 58 )); then
                    printf '%b%b━%b' "$LC" "$BOLD" "$NC"
                elif (( RANDOM % 5 == 0 )); then
                    sc="${SCOLS[$((RANDOM % ${#SCOLS[@]}))]}"
                    printf '%b%s%b' "$sc" "${STARS[$((RANDOM % ${#STARS[@]}))]}" "$NC"
                else
                    printf ' '
                fi
            done
            printf '\n'
        done
        _ms 85
    done

    clear
    echo ""
    echo ""

    # ASTRA logo — reveal line by line
    local LINES=(
        '     ▄▄▄·  .▄▄ ·▄▄▄▄▄▄▄  ▄▄▄   ▄▄▄· '
        '    ▐█ ▀█ ▐█ ▀.•██  ▀▄ █·▀▄ █·▐█ ▀█ '
        '    ▄█▀▀█ ▄▀▀▀█▄▐█.▪▐▀▀▄ ▐▀▀▄ ▄█▀▀█ '
        '    ▐█ ▪▐▌▐█▄▪▐█▐█▌·▐█•█▌▐█•█▌▐█ ▪▐▌'
        '     ▀  ▀  ▀▀▀▀ ▀▀▀ .▀  ▀.▀  ▀ ▀  ▀ '
    )
    local LCOLS=("$LC" "$LB" "$W" "$LB" "$LC")
    local i
    for ((i=0; i<${#LINES[@]}; i++)); do
        printf '  %b%b%s%b\n' "${LCOLS[$i]}" "$BOLD" "${LINES[$i]}" "$NC"
        _ms 80
    done

    echo ""
    _ms 120

    printf '  %b%b' "$DIM" "$W"
    type_text "  ✦  Pterodactyl Automated Installer  ✦" "$W" 20
    echo ""

    anim_sep "$LC"
    fade_lines 100 \
        "  ${DIM}  Panel · Wings · Blueprint · Firewall Manager${NC}" \
        "  ${DIM}  Ubuntu 20.04/22.04/24.04  ·  Debian 11/12${NC}" \
        "  ${DIM}  by JishnuTech${NC}"
    anim_sep "$LC"
    echo ""
    _ms 600
    _show
}

###############################################################
# STATIC BANNER (fast, no animation — for menu redraws)
###############################################################

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
    printf '  %b✦  Pterodactyl Automated Installer  ·  by JishnuTech  ✦%b\n' "$DIM$W" "$NC"
    echo ""
    printf '  %b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$LC" "$NC"
    printf '  %bPanel · Wings · Blueprint · Firewall · Ubuntu/Debian%b\n' "$DIM" "$NC"
    printf '  %b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$LC" "$NC"
    echo ""
}

###############################################################
# LOG HELPERS
###############################################################

_log()       { echo "$(date '+%H:%M:%S') $*" >> "$LOG" 2>/dev/null || true; }
log_info()   { printf '  %b[✦ INFO]%b   %s\n' "$LG" "$NC" "$*"; _log "[INFO]  $*"; }
log_warn()   { printf '  %b[⚠ WARN]%b   %s\n' "$Y"  "$NC" "$*"; _log "[WARN]  $*"; }
log_error()  { printf '  %b[✖ ERR ]%b   %s\n' "$LR" "$NC" "$*"; _log "[ERROR] $*"; }
log_ok()     { printf '  %b%b[✔]%b  ' "$LG" "$BOLD" "$NC"; type_text "$*" "$LG" 16; _log "[OK]    $*"; }

log_step() {
    echo ""
    printf '  %b%b  ◈  %b' "$LC" "$BOLD" "$NC"
    wipe_in "$*" "$W"
    printf '  %b' "$DIM"
    local i; for ((i=0; i<50; i++)); do printf '─'; _ms 4; done
    printf '%b\n' "$NC"
    _log ">>> $*"
}

# run_task "label" command [args...]
# Runs command in background, shows spinner, returns exit code
run_task() {
    local label="$1"; shift
    _log "CMD: $*"
    ( "$@" >> "$LOG" 2>&1 ) &
    local pid=$!
    spinner $pid "$label"
    wait $pid
    local rc=$?
    if (( rc != 0 )); then
        log_error "$label failed (rc=$rc) — see $LOG"
    else
        log_ok "$label"
    fi
    return $rc
}

###############################################################
# PROMPT HELPERS
###############################################################

_pause() {
    echo ""
    _show
    printf '  %bPress [Enter] to continue…%b' "$DIM" "$NC"
    read -r _DUMMY
}

prompt_yn() {
    _show
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
    _hide
    printf '  %b%b╔══════════════════════════════════════════════════════════════╗%b\n' "$LG" "$BOLD" "$NC"
    _ms 60
    printf '  %b%b║%b  %b%b %s %b\n' "$LG" "$BOLD" "$NC" "$LG" "$BOLD" "$title" "$NC"
    _ms 60
    printf '  %b%b╚══════════════════════════════════════════════════════════════╝%b\n' "$LG" "$BOLD" "$NC"
    _ms 120
    local f
    for f in 1 2 3; do
        printf '\r  %b%b🌟  %s  🌟%b   ' "$Y" "$BOLD" "$title" "$NC"; _ms 260
        printf '\r  %b%b✦   %s   ✦%b   ' "$LC" "$BOLD" "$title" "$NC"; _ms 260
    done
    printf '\r  %b%b✦   %s   ✦%b\n' "$LG" "$BOLD" "$title" "$NC"
    echo ""
    _show
}

###############################################################
# ROOT CHECK & OS DETECT
###############################################################

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        printf '\n  %b[✖]%b  Run as root:  %bsudo bash %s%b\n\n' "$LR" "$NC" "$BOLD" "$0" "$NC"
        exit 1
    fi
    mkdir -p "$(dirname "$LOG")"
    touch "$LOG"
    chmod 600 "$LOG"
}

detect_os() {
    log_step "Detecting operating system"
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release missing."
        return 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-}"
    OS_VER="${VERSION_ID:-}"
    log_info "OS: ${PRETTY_NAME:-$OS_ID $OS_VER}"
    case "$OS_ID" in
        ubuntu|debian) ;;
        *)
            log_error "Unsupported OS: $OS_ID  (need Ubuntu or Debian)"
            return 1 ;;
    esac
}

check_resources() {
    log_step "Checking server resources"
    local ram disk i

    ram=$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)
    disk=$(df / --output=avail -BG 2>/dev/null | tail -1 | tr -d 'G ')
    disk=${disk// /}

    printf '  %b  RAM : %b' "$LC" "$NC"
    for ((i=0; i<=ram; i+=ram/20+1)); do
        printf '\r  %b  RAM : %b%b%d MB%b   ' "$LC" "$NC" "$LG$BOLD" "$i" "$NC"
        _ms 30
    done
    printf '\r  %b  RAM : %b%b%d MB%b\n' "$LC" "$NC" "$LG$BOLD" "$ram" "$NC"

    printf '  %b  Disk: %b' "$LC" "$NC"
    for ((i=0; i<=disk; i+=disk/20+1)); do
        printf '\r  %b  Disk: %b%b%d GB%b   ' "$LC" "$NC" "$LG$BOLD" "$i" "$NC"
        _ms 30
    done
    printf '\r  %b  Disk: %b%b%d GB free%b\n' "$LC" "$NC" "$LG$BOLD" "$disk" "$NC"

    (( ram  < MIN_RAM  )) && log_warn "Low RAM (${ram}MB) — recommend ≥${MIN_RAM}MB."
    (( disk < MIN_DISK )) && log_warn "Low disk (${disk}GB) — recommend ≥${MIN_DISK}GB."
    _ms 150
}

###############################################################
# PACKAGE & DEPENDENCY INSTALL
###############################################################

update_system() {
    log_step "Updating system packages"
    run_task "apt-get update"   apt-get update -y
    run_task "apt-get upgrade"  apt-get upgrade -y -o Dpkg::Options::="--force-confdef" \
                                                    -o Dpkg::Options::="--force-confold"
    run_task "Install base deps" apt-get install -y --no-install-recommends \
        curl wget git unzip tar zip \
        software-properties-common apt-transport-https \
        ca-certificates gnupg lsb-release \
        ufw iptables supervisor cron
}

add_php_repo() {
    log_step "Adding PHP repository"
    case "$OS_ID" in
        ubuntu)
            run_task "Add ondrej/php PPA" bash -c \
                'LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php'
            ;;
        debian)
            run_task "Import sury.org GPG key" bash -c \
                'curl -fsSL https://packages.sury.org/php/apt.gpg \
                 | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg'
            run_task "Add sury.org repo" bash -c \
                'echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] \
                https://packages.sury.org/php/ $(lsb_release -sc) main" \
                > /etc/apt/sources.list.d/sury-php.list'
            ;;
    esac
    run_task "apt-get update (PHP)" apt-get update -y
}

detect_php() {
    local v
    for v in 8.3 8.2 8.1; do
        if apt-cache show "php${v}" >/dev/null 2>&1; then
            PHP_VER="$v"
            log_info "PHP ${PHP_VER} selected."
            return 0
        fi
    done
    PHP_VER="8.1"
    log_warn "PHP version auto-detect failed — defaulting to ${PHP_VER}."
}

install_php() {
    log_step "Installing PHP ${PHP_VER}"
    local exts="cli gd mysql pdo mbstring tokenizer bcmath xml fpm curl zip intl readline"
    local pkgs=("php${PHP_VER}")
    local e
    for e in $exts; do pkgs+=("php${PHP_VER}-${e}"); done
    run_task "Install PHP ${PHP_VER} + extensions" apt-get install -y "${pkgs[@]}"
    animate_progress "PHP ${PHP_VER}" 18
    run_task "Enable php${PHP_VER}-fpm" systemctl enable --now "php${PHP_VER}-fpm"
    log_ok "PHP ${PHP_VER} ready."
}

install_mariadb() {
    local db_root="$1" db_pass="$2"
    log_step "Installing MariaDB"
    run_task "Install MariaDB server" apt-get install -y mariadb-server
    run_task "Enable MariaDB" systemctl enable --now mariadb

    log_step "Configuring MariaDB"
    # Use a temp SQL file to avoid heredoc issues with set -e / subshells
    cat > /tmp/_astra_db.sql <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${db_root}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\\_%';
CREATE DATABASE IF NOT EXISTS panel
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1'
    IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON panel.*
    TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    # Try passwordless first (fresh install), then fall back with root password
    if ! mysql -u root < /tmp/_astra_db.sql >> "$LOG" 2>&1; then
        if ! mysql -u root -p"${db_root}" < /tmp/_astra_db.sql >> "$LOG" 2>&1; then
            log_warn "MariaDB auto-config had issues — check $LOG"
        fi
    fi
    rm -f /tmp/_astra_db.sql
    animate_progress "MariaDB" 14
    log_ok "MariaDB ready (database: panel, user: pterodactyl)."
}

install_redis() {
    log_step "Installing Redis"
    run_task "Install Redis" apt-get install -y redis-server
    run_task "Enable Redis" systemctl enable --now redis-server
    log_ok "Redis running."
}

install_nginx() {
    log_step "Installing Nginx"
    # Remove Apache if present — it conflicts on port 80
    if dpkg -l apache2 >/dev/null 2>&1; then
        run_task "Remove apache2" apt-get remove -y --purge apache2 apache2-utils apache2-bin
    fi
    run_task "Install Nginx" apt-get install -y nginx
    run_task "Enable Nginx" systemctl enable --now nginx
    log_ok "Nginx installed."
}

install_composer() {
    log_step "Installing Composer"
    run_task "Download Composer installer" bash -c \
        'curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php'
    run_task "Install Composer" bash -c \
        'php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
         rm -f /tmp/composer-setup.php'
    log_ok "Composer ready."
}

###############################################################
# NGINX CONFIG
###############################################################

# Write HTTP-only vhost (used before SSL is obtained)
_nginx_http() {
    local fqdn="$1"
    local sock="/run/php/php${PHP_VER}-fpm.sock"
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${fqdn};

    root ${PANEL_DIR}/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log warn;

    client_max_body_size 100m;
    client_body_timeout  120s;
    sendfile off;

    # Allow Let's Encrypt challenge
    location ^~ /.well-known/acme-challenge/ {
        allow all;
        root /var/www/letsencrypt;
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass   unix:${sock};
        fastcgi_index  index.php;
        include        fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param  HTTP_PROXY "";
        fastcgi_param  PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_read_timeout    300;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout    300;
        fastcgi_buffer_size     16k;
        fastcgi_buffers         4 16k;
        fastcgi_intercept_errors off;
    }

    location ~ /\.(?!well-known) { deny all; }
}
NGINX

    ln -sf /etc/nginx/sites-available/pterodactyl.conf \
           /etc/nginx/sites-enabled/pterodactyl.conf

    if nginx -t >> "$LOG" 2>&1; then
        systemctl reload nginx >> "$LOG" 2>&1
        log_ok "Nginx HTTP vhost active."
    else
        log_error "Nginx config test failed — check $LOG"
        return 1
    fi
}

# Write full HTTPS vhost (after SSL cert obtained)
_nginx_https() {
    local fqdn="$1"
    local sock="/run/php/php${PHP_VER}-fpm.sock"

    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${fqdn};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${fqdn};

    root ${PANEL_DIR}/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log warn;

    client_max_body_size 100m;
    client_body_timeout  120s;
    sendfile off;

    # ── SSL ────────────────────────────────────────────────────
    ssl_certificate     /etc/letsencrypt/live/${fqdn}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${fqdn}/privkey.pem;
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

    # ── Routing ────────────────────────────────────────────────
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # Static asset cache
    location ~* \.(css|js|gif|ico|jpeg|jpg|png|svg|webp|woff|woff2|ttf|eot)$ {
        expires    30d;
        add_header Cache-Control "public, no-transform";
        try_files  \$uri \$uri/ /index.php?\$query_string;
    }

    # ── PHP-FPM ────────────────────────────────────────────────
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass   unix:${sock};
        fastcgi_index  index.php;
        include        fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param  HTTP_PROXY "";
        fastcgi_param  PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_read_timeout    300;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout    300;
        fastcgi_buffer_size     16k;
        fastcgi_buffers         4 16k;
        fastcgi_intercept_errors off;
    }

    location ~ /\.(?!well-known) { deny all; }
}
NGINX

    if nginx -t >> "$LOG" 2>&1; then
        systemctl reload nginx >> "$LOG" 2>&1
        log_ok "Nginx HTTPS vhost active."
    else
        log_error "Nginx HTTPS config failed — check $LOG"
        return 1
    fi
}

# Obtain Let's Encrypt cert with webroot (no downtime)
obtain_ssl() {
    local fqdn="$1" email="$2"
    log_step "Obtaining Let's Encrypt SSL certificate"
    run_task "Install certbot" apt-get install -y certbot python3-certbot-nginx

    mkdir -p /var/www/letsencrypt

    # Try webroot first
    if certbot certonly \
        --webroot \
        --webroot-path=/var/www/letsencrypt \
        --agree-tos \
        --no-eff-email \
        -m "$email" \
        -d "$fqdn" \
        --non-interactive \
        >> "$LOG" 2>&1; then
        log_ok "SSL certificate obtained (webroot)."
        # Auto-renewal cron
        ( crontab -l 2>/dev/null | grep -v 'certbot renew'; \
          echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'" ) \
          | crontab - 2>/dev/null || true
        log_ok "Auto-renewal cron added."
        return 0
    fi

    # Fall back: standalone (briefly stops nginx)
    log_warn "Webroot failed, trying standalone…"
    systemctl stop nginx >> "$LOG" 2>&1 || true
    if certbot certonly \
        --standalone \
        --agree-tos \
        --no-eff-email \
        -m "$email" \
        -d "$fqdn" \
        --non-interactive \
        >> "$LOG" 2>&1; then
        systemctl start nginx >> "$LOG" 2>&1 || true
        log_ok "SSL certificate obtained (standalone)."
        ( crontab -l 2>/dev/null | grep -v 'certbot renew'; \
          echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'" ) \
          | crontab - 2>/dev/null || true
        return 0
    fi

    systemctl start nginx >> "$LOG" 2>&1 || true
    log_warn "SSL could not be obtained automatically."
    log_warn "Panel will run over HTTP. Run: certbot certonly --nginx -d ${fqdn}"
    return 1
}

###############################################################
# FIREWALL
###############################################################

fw_open() {
    local port="$1" proto="${2:-tcp}"
    ufw allow "${port}/${proto}"  >/dev/null 2>&1 || true
    iptables  -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
    ip6tables -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
    printf '  %b  ✦%b  %b%s/%s%b opened\n' "$LG" "$NC" "$W$BOLD" "$port" "$proto" "$NC"
    _ms 55
}

fw_range() {
    local from="$1" to="$2" proto="${3:-tcp}"
    ufw allow "${from}:${to}/${proto}" >/dev/null 2>&1 || true
    iptables  -I INPUT -p "$proto" --dport "${from}:${to}" -j ACCEPT 2>/dev/null || true
    ip6tables -I INPUT -p "$proto" --dport "${from}:${to}" -j ACCEPT 2>/dev/null || true
    printf '  %b  ✦%b  %b%s-%s/%s%b opened\n' "$LG" "$NC" "$W$BOLD" "$from" "$to" "$proto" "$NC"
    _ms 55
}

setup_ufw() {
    log_step "Configuring UFW firewall"
    ufw --force reset         >/dev/null 2>&1 || true
    ufw default deny incoming >/dev/null 2>&1 || true
    ufw default allow outgoing>/dev/null 2>&1 || true
    fw_open 22 tcp
    ufw --force enable        >/dev/null 2>&1 || true
    log_ok "UFW enabled (SSH 22/tcp preserved)."
}

open_panel_ports() {
    log_step "Opening Panel firewall ports"
    fw_open 80  tcp
    fw_open 443 tcp
    log_ok "Panel ports: 80/tcp, 443/tcp"
}

open_wings_ports() {
    log_step "Opening Wings firewall ports"
    fw_open 8080 tcp
    fw_open 2022 tcp
    log_ok "Wings ports: 8080/tcp, 2022/tcp"
}

open_mc_ports() {
    log_step "Opening Minecraft allocation ports"
    fw_open  25565 tcp; fw_open  25565 udp
    fw_open  19132 udp
    fw_range 25500 25600 tcp; fw_range 25500 25600 udp
    fw_range 19000 19200 udp
    log_ok "Minecraft ports opened."
    fade_lines 65 \
        "  ${DIM}  Java default:        ${W}25565/tcp+udp${NC}" \
        "  ${DIM}  Bedrock default:     ${W}19132/udp${NC}" \
        "  ${DIM}  Java alloc range:    ${W}25500-25600/tcp+udp${NC}" \
        "  ${DIM}  Bedrock alloc range: ${W}19000-19200/udp${NC}"
    log_warn "Add these in Panel → Admin → Nodes → [node] → Allocations"
}

###############################################################
# FIREWALL MANAGER MENU
###############################################################

firewall_menu() {
    local fw_choice
    while true; do
        print_banner
        printf '  %b%b' "$LC" "$BOLD"
        type_text "[ 🔥 FIREWALL PORT MANAGER ]" "$LC" 18
        echo ""
        fade_lines 50 \
            "  ${LG}  1)${NC}  ${BOLD}Open Panel ports${NC}         ${DIM}80, 443${NC}" \
            "  ${LG}  2)${NC}  ${BOLD}Open Wings ports${NC}         ${DIM}8080, 2022${NC}" \
            "  ${LG}  3)${NC}  ${BOLD}Open Minecraft ports${NC}     ${DIM}25565 · 19132 · 25500-25600 · 19000-19200${NC}" \
            "  ${LG}  4)${NC}  ${BOLD}Open ALL ports${NC}           ${DIM}Panel + Wings + Minecraft${NC}" \
            "  ${LG}  5)${NC}  ${BOLD}Custom port${NC}" \
            "  ${LG}  6)${NC}  ${BOLD}Custom port range${NC}" \
            "  ${LC}  7)${NC}  ${BOLD}Show UFW status${NC}" \
            "  ${R}   8)${NC}  ${BOLD}Back to main menu${NC}"
        echo ""
        _show
        printf '  %b%bChoice [1-8]:%b ' "$W" "$BOLD" "$NC"
        read -r fw_choice

        case "$fw_choice" in
            1) open_panel_ports; _pause ;;
            2) open_wings_ports; _pause ;;
            3) open_mc_ports; _pause ;;
            4) open_panel_ports; open_wings_ports; open_mc_ports
               printf '  %b%b✦%b  ALL ports opened!\n' "$LM" "$BOLD" "$NC"
               _pause ;;
            5) _show
               printf '  Port number: '; read -r _cp
               printf '  Protocol [tcp/udp/both] (default tcp): '; read -r _cpro
               _cpro="${_cpro:-tcp}"
               if [[ "$_cpro" == "both" ]]; then
                   fw_open "$_cp" tcp; fw_open "$_cp" udp
               else
                   fw_open "$_cp" "$_cpro"
               fi
               _pause ;;
            6) _show
               printf '  Start port: '; read -r _p1
               printf '  End port:   '; read -r _p2
               printf '  Protocol [tcp/udp/both] (default tcp): '; read -r _rpro
               _rpro="${_rpro:-tcp}"
               if [[ "$_rpro" == "both" ]]; then
                   fw_range "$_p1" "$_p2" tcp; fw_range "$_p1" "$_p2" udp
               else
                   fw_range "$_p1" "$_p2" "$_rpro"
               fi
               _pause ;;
            7) echo ""
               ufw status verbose 2>/dev/null || log_warn "UFW not active."
               _pause ;;
            8) return ;;
            *) log_warn "Enter 1–8."; _ms 600 ;;
        esac
    done
}

###############################################################
# PANEL INSTALLER
###############################################################

install_panel() {
    print_banner
    printf '  %b%b' "$LC" "$BOLD"
    type_text "[ ✦ PANEL INSTALLER ]" "$LC" 22
    echo ""
    log_warn "Will install: Nginx · PHP · MariaDB · Redis · Composer · SSL"
    echo ""
    _show

    # ── Gather inputs ─────────────────────────────────
    local FQDN EMAIL ADMIN_USER ADMIN_PASS ADMIN_FIRST ADMIN_LAST \
          DB_ROOT DB_PASS TIMEZONE

    printf '  %b  Domain %b(e.g. panel.example.com)%b: '  "$W$BOLD" "$DIM" "$NC"
    read -r FQDN
    [[ -z "$FQDN" ]] && { log_error "Domain cannot be empty."; _pause; return; }

    printf '  %b  Admin email%b: ' "$W$BOLD" "$NC"
    read -r EMAIL
    [[ -z "$EMAIL" ]] && { log_error "Email cannot be empty."; _pause; return; }

    printf '  %b  Admin username %b[default: admin]%b: ' "$W$BOLD" "$DIM" "$NC"
    read -r ADMIN_USER
    ADMIN_USER="${ADMIN_USER:-admin}"

    printf '  %b  Admin password %b(hidden)%b: ' "$W$BOLD" "$DIM" "$NC"
    read -rs ADMIN_PASS; echo ""
    [[ -z "$ADMIN_PASS" ]] && { log_error "Password cannot be empty."; _pause; return; }

    printf '  %b  First name %b[default: Admin]%b: ' "$W$BOLD" "$DIM" "$NC"
    read -r ADMIN_FIRST
    ADMIN_FIRST="${ADMIN_FIRST:-Admin}"

    printf '  %b  Last name  %b[default: User]%b: '  "$W$BOLD" "$DIM" "$NC"
    read -r ADMIN_LAST
    ADMIN_LAST="${ADMIN_LAST:-User}"

    printf '  %b  DB root password%b: ' "$W$BOLD" "$NC"
    read -rs DB_ROOT; echo ""
    [[ -z "$DB_ROOT" ]] && { log_error "DB root password cannot be empty."; _pause; return; }

    printf '  %b  DB pterodactyl password%b: ' "$W$BOLD" "$NC"
    read -rs DB_PASS; echo ""
    [[ -z "$DB_PASS" ]] && { log_error "DB password cannot be empty."; _pause; return; }

    printf '  %b  Timezone %b[default: UTC]%b: ' "$W$BOLD" "$DIM" "$NC"
    read -r TIMEZONE
    TIMEZONE="${TIMEZONE:-UTC}"

    echo ""
    anim_sep "$C"
    fade_lines 70 \
        "  ${LC}${BOLD}  Summary${NC}" \
        "  ${W}  Domain:    ${BOLD}${FQDN}${NC}" \
        "  ${W}  Email:     ${BOLD}${EMAIL}${NC}" \
        "  ${W}  Username:  ${BOLD}${ADMIN_USER}${NC}" \
        "  ${W}  Timezone:  ${BOLD}${TIMEZONE}${NC}"
    anim_sep "$C"
    echo ""

    prompt_yn "Begin Panel installation?" || { _pause; return; }

    # ── Install stack ─────────────────────────────────
    detect_os         || { _pause; return; }
    check_resources
    update_system
    add_php_repo
    detect_php
    install_php
    install_mariadb "$DB_ROOT" "$DB_PASS"
    install_redis
    install_nginx
    install_composer
    setup_ufw
    open_panel_ports

    # ── Download Panel ────────────────────────────────
    log_step "Downloading Pterodactyl Panel"
    run_task "Create panel directory" bash -c "mkdir -p ${PANEL_DIR}"
    run_task "Download panel.tar.gz" bash -c \
        "curl -Lo /tmp/panel.tar.gz \
         https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
    run_task "Extract panel" bash -c \
        "tar -xzf /tmp/panel.tar.gz -C ${PANEL_DIR} --strip-components=1
         rm -f /tmp/panel.tar.gz"
    run_task "Storage permissions" bash -c \
        "chmod -R 755 ${PANEL_DIR}/storage ${PANEL_DIR}/bootstrap/cache"
    animate_progress "Panel extraction" 18

    # ── Composer install ──────────────────────────────
    log_step "Running Composer install"
    run_task "composer install" bash -c \
        "cd ${PANEL_DIR}
         COMPOSER_ALLOW_SUPERUSER=1 composer install \
           --no-dev --optimize-autoloader --no-interaction --no-progress 2>&1"
    animate_progress "Composer" 15

    # ── Environment ───────────────────────────────────
    log_step "Configuring .env"
    cp "${PANEL_DIR}/.env.example" "${PANEL_DIR}/.env"

    run_task "Generate app key" bash -c \
        "cd ${PANEL_DIR} && php artisan key:generate --force"

    local ENV="${PANEL_DIR}/.env"
    # Use sed with | delimiter so paths don't confuse it
    sed -i "s|APP_ENV=.*|APP_ENV=production|"                         "$ENV"
    sed -i "s|APP_DEBUG=.*|APP_DEBUG=false|"                          "$ENV"
    sed -i "s|APP_URL=.*|APP_URL=https://${FQDN}|"                   "$ENV"
    sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=${TIMEZONE}|"             "$ENV"
    sed -i "s|DB_CONNECTION=.*|DB_CONNECTION=mysql|"                  "$ENV"
    sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|"                         "$ENV"
    sed -i "s|DB_PORT=.*|DB_PORT=3306|"                               "$ENV"
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=panel|"                      "$ENV"
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|"                "$ENV"
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|"                 "$ENV"
    sed -i "s|CACHE_DRIVER=.*|CACHE_DRIVER=redis|"                    "$ENV"
    sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=redis|"                "$ENV"
    sed -i "s|QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|"            "$ENV"
    sed -i "s|REDIS_HOST=.*|REDIS_HOST=127.0.0.1|"                   "$ENV"
    sed -i "s|REDIS_PORT=.*|REDIS_PORT=6379|"                         "$ENV"
    sed -i "s|MAIL_MAILER=.*|MAIL_MAILER=log|"                        "$ENV"
    log_ok ".env configured."

    # ── DB migrations ─────────────────────────────────
    log_step "Running database migrations"
    run_task "php artisan migrate --seed" bash -c \
        "cd ${PANEL_DIR} && php artisan migrate --seed --force"
    animate_progress "Migrations" 22

    # ── Admin user ────────────────────────────────────
    log_step "Creating admin user"
    run_task "p:user:make" bash -c "cd ${PANEL_DIR} && php artisan p:user:make \
        --email='${EMAIL}' \
        --username='${ADMIN_USER}' \
        --name-first='${ADMIN_FIRST}' \
        --name-last='${ADMIN_LAST}' \
        --password='${ADMIN_PASS}' \
        --admin=1"

    # ── Permissions ───────────────────────────────────
    log_step "Setting file permissions"
    run_task "chown www-data" bash -c \
        "chown -R www-data:www-data ${PANEL_DIR}
         find ${PANEL_DIR} -type f -exec chmod 644 {} \;
         find ${PANEL_DIR} -type d -exec chmod 755 {} \;
         chmod -R 755 ${PANEL_DIR}/storage ${PANEL_DIR}/bootstrap/cache"

    # ── Queue worker ──────────────────────────────────
    log_step "Setting up queue worker & cron"
    # Scheduler cron
    ( crontab -l 2>/dev/null | grep -v 'pterodactyl'; \
      echo "* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1" ) \
      | crontab - 2>/dev/null || true

    # Supervisor
    cat > /etc/supervisor/conf.d/pteroq.conf <<'SUPEOF'
[program:pteroq]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=2
redirect_stderr=true
stdout_logfile=/var/www/pterodactyl/storage/logs/pteroq.log
SUPEOF

    run_task "Reload supervisor" bash -c \
        "supervisorctl reread 2>/dev/null || true
         supervisorctl update 2>/dev/null || true
         supervisorctl start pteroq:* 2>/dev/null || true"
    log_ok "Queue worker configured."

    # ── Nginx HTTP first ──────────────────────────────
    log_step "Configuring Nginx (HTTP)"
    _nginx_http "$FQDN"

    # ── SSL ───────────────────────────────────────────
    local SSL_OK=true
    obtain_ssl "$FQDN" "$EMAIL" || SSL_OK=false

    if $SSL_OK; then
        log_step "Switching Nginx to HTTPS"
        _nginx_https "$FQDN"
        # Fix APP_URL if needed
        sed -i "s|APP_URL=.*|APP_URL=https://${FQDN}|" "${PANEL_DIR}/.env"
    else
        sed -i "s|APP_URL=.*|APP_URL=http://${FQDN}|" "${PANEL_DIR}/.env"
    fi

    run_task "Clear & cache config" bash -c \
        "cd ${PANEL_DIR} && php artisan config:cache && php artisan route:cache && php artisan view:cache"

    # ── Done ──────────────────────────────────────────
    success_box "✦  PANEL INSTALLATION COMPLETE!"
    local proto="https"; $SSL_OK || proto="http"
    fade_lines 80 \
        "  ${W}${BOLD}  Panel URL:${NC}   ${proto}://${FQDN}" \
        "  ${W}${BOLD}  Username:${NC}    ${ADMIN_USER}" \
        "  ${W}${BOLD}  PHP:${NC}         ${PHP_VER}" \
        "  ${W}${BOLD}  Ports open:${NC}  22/tcp  80/tcp  443/tcp" \
        "" \
        "  ${DIM}  Next: install Wings on your node VPS → Option 2${NC}" \
        "  ${DIM}  Full log: ${LOG}${NC}"
    echo ""
    _pause
}

###############################################################
# WINGS INSTALLER
###############################################################

install_wings() {
    print_banner
    printf '  %b%b' "$LC" "$BOLD"
    type_text "[ ✦ WINGS INSTALLER ]" "$LC" 22
    echo ""
    log_warn "Installs: Docker · Wings binary · systemd service · MC firewall ports"
    echo ""

    prompt_yn "Proceed with Wings installation?" || { _pause; return; }

    detect_os   || { _pause; return; }
    check_resources
    update_system
    setup_ufw
    open_wings_ports
    open_mc_ports

    # ── Docker ────────────────────────────────────────
    log_step "Installing Docker"
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker already installed — skipping."
    else
        run_task "Add Docker GPG key" bash -c \
            "curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg \
             | gpg --dearmor -o /usr/share/keyrings/docker.gpg 2>/dev/null"
        run_task "Add Docker apt repo" bash -c \
            "echo \"deb [arch=\$(dpkg --print-architecture) \
             signed-by=/usr/share/keyrings/docker.gpg] \
             https://download.docker.com/linux/${OS_ID} \
             \$(lsb_release -cs) stable\" \
             > /etc/apt/sources.list.d/docker.list"
        run_task "apt-get update (Docker)" apt-get update -y
        run_task "Install Docker CE" apt-get install -y \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin
        run_task "Enable Docker" systemctl enable --now docker
        animate_progress "Docker" 20
        log_ok "Docker installed."
    fi

    # ── Wings ─────────────────────────────────────────
    log_step "Downloading Wings binary"
    local arch
    arch=$(uname -m)
    [[ "$arch" == "x86_64" ]] && arch="amd64" || arch="arm64"

    run_task "Create /etc/pterodactyl" bash -c "mkdir -p /etc/pterodactyl"
    run_task "Download Wings (${arch})" bash -c \
        "curl -Lo /usr/local/bin/wings \
         https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${arch}"
    run_task "chmod +x wings" chmod u+x /usr/local/bin/wings
    animate_progress "Wings" 14
    log_ok "Wings binary ready (${arch})."

    # ── systemd ───────────────────────────────────────
    log_step "Creating Wings systemd service"
    cat > /etc/systemd/system/wings.service <<'WSVC'
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
WSVC

    run_task "systemd daemon-reload" systemctl daemon-reload
    run_task "Enable Wings service"  systemctl enable wings
    log_ok "Wings service enabled."

    success_box "✦  WINGS INSTALLATION COMPLETE!"
    fade_lines 75 \
        "  ${W}${BOLD}  Ports open:${NC}" \
        "  ${LC}    22/tcp${NC}              SSH" \
        "  ${LC}    8080/tcp${NC}             Wings API (Panel ↔ Node)" \
        "  ${LC}    2022/tcp${NC}             SFTP" \
        "  ${LC}    25565/tcp+udp${NC}        Minecraft Java" \
        "  ${LC}    19132/udp${NC}             Minecraft Bedrock" \
        "  ${LC}    25500-25600/tcp+udp${NC}   Java alloc range" \
        "  ${LC}    19000-19200/udp${NC}        Bedrock alloc range" \
        "" \
        "  ${W}${BOLD}  Next steps:${NC}" \
        "  ${LC}  1.${NC} Panel → Admin → Nodes → Create node" \
        "  ${LC}  2.${NC} Node 'Configuration' tab → copy the token" \
        "  ${LC}  3.${NC} Run on this VPS:" \
        "     ${BOLD}wings configure --panel-url https://panel.domain.com --token TOKEN${NC}" \
        "  ${LC}  4.${NC} ${BOLD}systemctl start wings${NC}" \
        "  ${LC}  5.${NC} Panel → Nodes → Allocations → add ports ${BOLD}25500–25600${NC}"
    echo ""
    _pause
}

###############################################################
# BLUEPRINT INSTALLER
###############################################################

install_blueprint() {
    print_banner
    printf '  %b%b' "$LC" "$BOLD"
    type_text "[ ✦ BLUEPRINT INSTALLER ]" "$LC" 22
    echo ""
    log_warn "Blueprint = addon/extension framework for Pterodactyl Panel."
    log_warn "Requires Panel at ${PANEL_DIR}."
    echo ""

    if [[ ! -d "$PANEL_DIR" ]] || [[ ! -f "${PANEL_DIR}/artisan" ]]; then
        log_error "Panel not found. Install Panel first (Option 1)."
        _pause; return
    fi

    prompt_yn "Proceed with Blueprint installation?" || { _pause; return; }

    log_step "Fetching latest Blueprint version"
    local BP_VER BP_URL BP_ZIP
    BP_VER=$(curl -fsSL \
        "https://api.github.com/repos/BlueprintFramework/framework/releases/latest" \
        2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/') || BP_VER=""

    if [[ -n "$BP_VER" ]]; then
        BP_URL="https://github.com/BlueprintFramework/framework/releases/download/${BP_VER}/framework.zip"
        BP_ZIP="framework.zip"
        log_info "Blueprint: ${BP_VER}"
    else
        log_warn "Could not detect version — using main branch."
        BP_URL="https://github.com/BlueprintFramework/framework/archive/refs/heads/main.zip"
        BP_ZIP="blueprint-main.zip"
        BP_VER="(main)"
    fi

    log_step "Downloading & installing Blueprint"
    run_task "Download Blueprint" bash -c \
        "curl -Lo /tmp/${BP_ZIP} '${BP_URL}'"
    run_task "Extract Blueprint" bash -c \
        "cd ${PANEL_DIR} && unzip -o /tmp/${BP_ZIP}
         rm -f /tmp/${BP_ZIP} 2>/dev/null || true"
    animate_progress "Blueprint extract" 10

    run_task "Run Blueprint installer" bash -c \
        "cd ${PANEL_DIR} && chmod +x blueprint.sh && bash blueprint.sh"
    log_ok "Blueprint installed."

    run_task "Fix permissions" bash -c \
        "chown -R www-data:www-data ${PANEL_DIR}"

    success_box "✦  BLUEPRINT INSTALLATION COMPLETE!"
    fade_lines 80 \
        "  ${W}${BOLD}  Version:${NC}    ${BP_VER}" \
        "  ${W}${BOLD}  Extensions:${NC} https://blueprint.zip"
    echo ""
    _pause
}

###############################################################
# MAIN MENU
###############################################################

main_menu() {
    local choice
    while true; do
        print_banner
        printf '  %b%b' "$W" "$BOLD"
        type_text "  What would you like to do?" "$W" 20
        echo ""

        fade_lines 48 \
            "  ${M}  ┌──────────────────────────────────────────────────────────────┐${NC}" \
            "  ${M}  │${NC}  ${LG}1)${NC}  ${BOLD}✦ Panel Installer${NC}         ${DIM}Nginx · PHP · MariaDB · SSL${NC}    ${M}│${NC}" \
            "  ${M}  │${NC}  ${LG}2)${NC}  ${BOLD}✦ Wings Installer${NC}         ${DIM}Docker · Wings · Node setup${NC}    ${M}│${NC}" \
            "  ${M}  │${NC}  ${LG}3)${NC}  ${BOLD}✦ Blueprint Installer${NC}     ${DIM}Addon framework for Panel${NC}      ${M}│${NC}" \
            "  ${M}  │${NC}  ${LC}4)${NC}  ${BOLD}🔥 Firewall Port Manager${NC}  ${DIM}UFW · iptables · MC ports${NC}      ${M}│${NC}" \
            "  ${M}  │${NC}  ${R} 5)${NC}  ${BOLD}🚪 Exit${NC}                                                     ${M}│${NC}" \
            "  ${M}  └──────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        _show
        printf '  %b%bEnter choice [1-5]:%b ' "$W" "$BOLD" "$NC"
        read -r choice

        case "$choice" in
            1) install_panel ;;
            2) install_wings ;;
            3) install_blueprint ;;
            4) firewall_menu ;;
            5)
                echo ""
                rainbow_echo "  ✦  ASTRA signing off — Happy hosting!  ✦"
                echo ""
                printf '  %bhttps://pterodactyl.io  ·  by JishnuTech%b\n\n' "$DIM" "$NC"
                _show
                exit 0 ;;
            *)
                log_warn "Invalid choice — enter 1 to 5."
                _ms 600 ;;
        esac
    done
}

###############################################################
# ENTRY POINT
###############################################################

check_root
boot_intro
main_menu
