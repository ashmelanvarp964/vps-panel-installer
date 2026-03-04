#!/bin/bash

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root.${NC}"
   exit 1
fi

# --- Helper Functions ---
animate_text() {
    local text="$1"
    local color="$2"
    for (( i=0; i<${#text}; i++ )); do
        echo -ne "${color}${text:$i:1}"
        sleep 0.01
    done
    echo -e "${NC}"
}

show_logo() {
    clear
    local chars=("-" "\\" "|" "/")
    for i in {1..8}; do
        clear
        echo -e "${CYAN}        ASHMEL SYSTEM INITIALIZING${NC}"
        echo -e "${BLUE}              [${chars[i%4]}]${NC}"
        sleep 0.05
    done
    
    clear
    echo -e "${CYAN}"
    echo "  █████  ███████ ██   ██ ███    ███ ███████ ██      "
    echo " ██   ██ ██      ██   ██ ████  ████ ██      ██      "
    echo " ███████ ███████ ███████ ██ ████ ██ █████   ██      "
    echo " ██   ██      ██ ██   ██ ██  ██  ██ ██      ██      "
    echo " ██   ██ ███████ ██   ██ ██      ██ ███████ ███████ "
    echo -e "${BLUE}          ASHMEL VPS PANEL INSTALLER v3.0${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
}

install_panel() {
    show_logo
    echo -e "${CYAN}[ PANEL INSTALLATION ]${NC}"
    read -p "Panel Domain (e.g., panel.domain.com): " FQDN
    read -p "Admin Email: " ADMIN_EMAIL
    read -s -p "Admin Password: " ADMIN_PASS
    echo -e "\n"

    # Dependency Setup
    apt update -y && apt install -y software-properties-common curl ca-certificates gnupg2 sudo unzip tar git
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    apt update -y
    apt install -y php8.2 php8.2-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} nginx mariadb-server redis-server
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # DB & Files
    DB_PASS=$(openssl rand -base64 14)
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel; CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1'; FLUSH PRIVILEGES;"
    
    mkdir -p /var/www/pterodactyl && cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    cp .env.example .env
    composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
    php artisan p:environment:setup --author="$ADMIN_EMAIL" --url="https://$FQDN" --timezone="UTC" --cache="redis" --session="redis" --queue="redis" --redis-host="127.0.0.1"
    php artisan p:environment:database --host="127.0.0.1" --port="3306" --database="panel" --username="pterodactyl" --password="$DB_PASS"
    php artisan migrate --seed --force
    php artisan p:user:make --email="$ADMIN_EMAIL" --username="admin" --first_name="Ashmel" --last_name="User" --password="$ADMIN_PASS" --admin=1
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    animate_text "Panel Installed!" "$GREEN"
    sleep 2
}

install_blueprint_nebula() {
    if [ ! -d "/var/www/pterodactyl" ]; then
        echo -e "${RED}Error: Install Pterodactyl first!${NC}"
        sleep 2
        return
    fi

    show_logo
    animate_text "Installing Node.js & Dependencies..." "$MAGENTA"
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    apt install -y nodejs

    cd /var/www/pterodactyl
    
    # 1. Install Blueprint Framework
    animate_text "Fetching Blueprint Framework..." "$CYAN"
    curl -L https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip -o release.zip
    unzip -o release.zip
    rm release.zip
    bash blueprint.sh # Initial init

    # 2. Download Nebula Theme via Command
    # Note: Replace the URL below with your specific Nebula download link if you have a private one.
    animate_text "Downloading Nebula Theme via URL..." "$YELLOW"
    curl -L -o nebula.blueprint https://github.com/PR0XY-S3RVICES/Nebula/releases/latest/download/nebula.blueprint
    
    # 3. Automatic Installation
    animate_text "Executing Nebula Installation..." "$GREEN"
    php blueprint.sh install nebula

    chown -R www-data:www-data /var/www/pterodactyl/*
    animate_text "Nebula Theme Installed Successfully!" "$GREEN"
    sleep 3
}

# --- Menu Loop ---
while true; do
    show_logo
    echo -e "  [1] ${CYAN}Install Pterodactyl Panel${NC}"
    echo -e "  [2] ${CYAN}Install Wings${NC}"
    echo -e "  [3] ${CYAN}Full Setup (Panel + Wings)${NC}"
    echo -e "  [4] ${MAGENTA}Install Blueprint + Nebula Theme (Command)${NC}"
    echo -e "  [5] ${RED}Uninstall Everything${NC}"
    echo -e "  [6] ${YELLOW}Exit${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -ne "${BLUE}Select Option: ${NC}"
    read OPT

    case $OPT in
        1) install_panel ;;
        2) 
            curl -sSL https://get.docker.com/ | CHANNEL=stable bash
            systemctl enable --now docker
            curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
            chmod u+x /usr/local/bin/wings
            animate_text "Wings Installed." "$GREEN"
            sleep 2
            ;;
        3) install_panel; install_wings ;;
        4) install_blueprint_nebula ;;
        5) 
            rm -rf /var/www/pterodactyl
            mysql -u root -e "DROP DATABASE IF EXISTS panel;"
            animate_text "Wiped." "$RED"; sleep 2 ;;
        6) exit 0 ;;
        *) echo "Invalid Selection"; sleep 1 ;;
    esac
done
