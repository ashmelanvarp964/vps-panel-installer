#!/bin/bash

# ==============================================================================
# AstraCloud-ICONIC - Pterodactyl Auto-Installer
# Multi-OS Support: Ubuntu, Debian, CentOS, AlmaLinux, Rocky Linux
# ==============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# App Info
APP_NAME="AstraCloud-ICONIC"
PANEL_VERSION="v1.11.5"

# --- HELPER FUNCTIONS ---

banner() {
    clear
    echo -e "${CYAN}"
    echo "  ================================================================== "
    echo "                _        _               ____ _                 _    "
    echo "               / \   ___| |_ _ __ __ _  / ___| | ___  _   _  __| |   "
    echo "              / _ \ / __| __| '__/ _\` | | |   | |/ _ \| | | |/ _\`  |
    echo "             / ___ \\__ \ |_| | | (_| | | |___| | (_) | |_| | (_| |  "
    echo "            /_/   \_\___/\__|_|  \__,_|  \____|_|\___/ \__,_|\__,_|  "
    echo "                                                                     "
    echo "                        AstraCloud-ICONIC                            "
    echo "  ================================================================== "
    echo -e "${NC}"
}

print_status() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
exit_error() { print_error "$1"; exit 1; }

# --- OS DETECTION ---

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        exit_error "Could not detect OS. This script requires a Linux distribution with /etc/os-release."
    fi

    case "$OS" in
        ubuntu|debian)
            PKG_MANAGER="apt"
            PHP_FPM_SERVICE="php8.3-fpm"
            PHP_SOCKET="/run/php/php8.3-fpm.sock"
            NGINX_USER="www-data"
            ;;
        centos|almalinux|rocky)
            PKG_MANAGER="dnf"
            PHP_FPM_SERVICE="php-fpm"
            PHP_SOCKET="/run/php-fpm/www.sock"
            NGINX_USER="nginx"
            ;;
        *)
            exit_error "Unsupported OS: $OS. Supported: Ubuntu, Debian, CentOS, Alma, Rocky."
            ;;
    esac
}

generate_password() {
    < /dev/urandom tr -dc 'A-Za-z0-9' | head -c 24
}

# --- PANEL INSTALLER ---

install_panel() {
    banner
    echo -e "${YELLOW}--- Pterodactyl Panel Installation ---${NC}"
    
    read -p "Enter FQDN (e.g., panel.example.com): " PANEL_URL
    read -p "Enter Admin Email: " ADMIN_EMAIL
    read -p "Enter Admin Username: " ADMIN_USER
    read -s -p "Enter Admin Password: " ADMIN_PASS
    echo ""

    if [[ -z "$PANEL_URL" || -z "$ADMIN_EMAIL" || -z "$ADMIN_USER" || -z "$ADMIN_PASS" ]]; then
        exit_error "All fields are required."
    fi

    # 1. Dependency Installation
    print_status "Installing dependencies for $OS..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt update && apt upgrade -y
        apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg2 sudo lsb-release nginx mariadb-server redis-server tar unzip git
        if [[ "$OS" == "ubuntu" ]]; then
            add-apt-repository ppa:ondrej/php -y
        else
            curl -sSL https://packages.sury.org/php/README.txt | bash -x
        fi
        apt update
        apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,curl,zip,intl,sqlite3,fpm}
    else
        dnf install -y epel-release
        dnf install -y https://rpms.remirepo.net/enterprise/remi-release-$(echo $VER | cut -d. -f1).rpm
        dnf module reset php -y
        dnf module enable php:remi-8.3 -y
        dnf install -y curl nginx mariadb-server redis tar unzip git php php-{common,cli,gd,mysqlnd,mbstring,bcmath,xml,curl,zip,intl,sqlite3,fpm}
        systemctl enable --now mariadb redis nginx php-fpm
    fi

    # 2. Composer
    print_status "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # 3. Database
    DB_PASSWORD=$(generate_password)
    print_status "Configuring Database..."
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel;"
    mysql -u root -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"

    # 4. Download Panel
    print_status "Downloading Pterodactyl..."
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    # 5. Config
    print_status "Configuring environment..."
    cp .env.example .env
    composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
    php artisan p:environment:setup --author="$ADMIN_EMAIL" --url="http://$PANEL_URL" --timezone="UTC" --cache="redis" --session="redis" --queue="redis" --redis-host="127.0.0.1" --redis-port="6379"
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env
    sed -i "s/DB_HOST=.*/DB_HOST=127.0.0.1/" .env
    php artisan migrate --seed --force

    # 6. Admin User
    print_status "Creating admin user..."
    php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --name-first="Admin" --name-last="User" --password="$ADMIN_PASS" --admin=1

    # 7. Permissions
    chown -R $NGINX_USER:$NGINX_USER /var/www/pterodactyl/*

    # 8. Queue Worker
    print_status "Setting up queue worker..."
    cat <<EOF > /etc/systemd/system/pteroq.service
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=$NGINX_USER
Group=$NGINX_USER
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now pteroq

    # 9. Nginx Configuration
    print_status "Configuring Nginx..."
    CONF_PATH="/etc/nginx/sites-available/pterodactyl.conf"
    if [[ "$PKG_MANAGER" == "dnf" ]]; then CONF_PATH="/etc/nginx/conf.d/pterodactyl.conf"; fi
    
    mkdir -p /etc/nginx/sites-available
    cat <<EOF > $CONF_PATH
server {
    listen 80;
    server_name $PANEL_URL;
    root /var/www/pterodactyl/public;
    index index.php;
    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:$PHP_SOCKET;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
    }
}
EOF
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        rm -f /etc/nginx/sites-enabled/default
    fi
    systemctl restart nginx $PHP_FPM_SERVICE

    show_port_info
    print_success "Panel installation complete on $OS!"
}

# --- WINGS INSTALLER ---

install_wings() {
    banner
    echo -e "${YELLOW}--- Pterodactyl Wings Installation ---${NC}"

    print_status "Installing Docker..."
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker

    ARCH=$(uname -m)
    WINGS_ARCH="amd64"
    if [[ "$ARCH" == "aarch64" ]]; then WINGS_ARCH="arm64"; fi

    print_status "Downloading Wings..."
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$WINGS_ARCH"
    chmod +x /usr/local/bin/wings

    print_status "Creating Wings service..."
    cat <<EOF > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable wings
    
    show_port_info
    print_success "Wings binary installed. Please paste your config.yml into /etc/pterodactyl/ and start the service."
}

# --- PORT INFORMATION ---

show_port_info() {
    echo -e "\n${CYAN}------------------------------------------${NC}"
    echo -e "${CYAN}PORT INFORMATION (IMPORTANT)${NC}"
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e "${GREEN}Pterodactyl Panel Port: 80 / 443${NC}"
    echo -e "Used to access the web panel."
    echo ""
    echo -e "${GREEN}Wings Port: 8080${NC}"
    echo -e "Used by the panel to communicate with this node."
    echo ""
    echo -e "${YELLOW}Firewall Notes:${NC}"
    echo -e "- Ensure ports 80, 443, and 8080 are OPEN in your VPS firewall."
    echo -e "- If using Cloudflare Tunnel, only port 22 (SSH) is strictly needed externally."
    echo -e "${CYAN}------------------------------------------${NC}\n"
}

# --- MAIN MENU ---

main_menu() {
    if [[ "$EUID" -ne 0 ]]; then exit_error "Please run as root."; fi
    detect_os
    banner
    echo -e "OS Detected: $OS $VER"
    echo -e "1) Install Pterodactyl Panel"
    echo -e "2) Install Wings (Node)"
    echo -e "3) Exit"
    echo ""
    read -p "Choose an option: " OPTION

    case $OPTION in
        1) install_panel ;;
        2) install_wings ;;
        3) exit 0 ;;
        *) main_menu ;;
    esac
}

main_menu
