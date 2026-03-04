#!/bin/bash

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root.${NC}"
   exit 1
fi

# --- Functions ---
show_logo() {
    clear
    # Animated intro effect
    local chars=("-" "\\" "|" "/")
    for i in {1..8}; do
        clear
        echo -e "${CYAN}        ASHMEL${NC}"
        echo -e "${BLUE}  [${chars[i%4]}] Loading Panel [${chars[i%4]}]${NC}"
        sleep 0.1
    done
    
    clear
    echo -e "${CYAN}"
    echo "  █████  ███████ ██   ██ ███    ███ ███████ ██      "
    echo " ██   ██ ██      ██   ██ ████  ████ ██      ██      "
    echo " ███████ ███████ ███████ ██ ████ ██ █████   ██      "
    echo " ██   ██      ██ ██   ██ ██  ██  ██ ██      ██      "
    echo " ██   ██ ███████ ██   ██ ██      ██ ███████ ███████ "
    echo -e "${BLUE}          VPS PANEL INSTALLER - PTERODACTYL${NC}"
    echo "-----------------------------------------------------"
}

install_dependencies() {
    echo -e "${YELLOW}Updating system and installing dependencies...${NC}"
    apt update -y && apt upgrade -y
    apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg
    
    # Add PHP Repository
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    
    # Install Stack
    apt install -y php8.2 php8.2-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
    nginx mariadb-server redis-server tar unzip git
    
    # Install Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
}

install_panel() {
    show_logo
    echo -e "${CYAN}--- Panel Configuration ---${NC}"
    read -p "Enter Panel Domain (FQDN, e.g. panel.example.com): " FQDN
    read -p "Enter Admin Email: " ADMIN_EMAIL
    read -s -p "Enter Admin Password: " ADMIN_PASS
    echo ""

    install_dependencies

    # Create Database
    DB_PASSWORD=$(openssl rand -base64 12)
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel;"
    mysql -u root -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"

    # Download Pterodactyl
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    # Setup Environment
    cp .env.example .env
    composer install --no-dev --optimize-autoloader

    php artisan key:generate --force
    php artisan p:environment:setup --author="$ADMIN_EMAIL" --url="https://$FQDN" --timezone="UTC" --cache="redis" --session="redis" --queue="redis" --redis-host="127.0.0.1"
    php artisan p:environment:database --host="127.0.0.1" --port="3306" --database="panel" --username="pterodactyl" --password="$DB_PASSWORD"
    
    # Migrate and Seed
    php artisan migrate --seed --force

    # Create Admin
    php artisan p:user:make --email="$ADMIN_EMAIL" --username="admin" --first_name="Admin" --last_name="User" --password="$ADMIN_PASS" --admin=1

    # Permissions
    chown -R www-data:www-data /var/www/pterodactyl/*

    echo -e "${GREEN}Panel installed successfully!${NC}"
    sleep 3
}

install_wings() {
    show_logo
    echo -e "${YELLOW}Installing Wings (Docker Daemon)...${NC}"
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker

    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
    chmod u+x /usr/local/bin/wings
    
    echo -e "${GREEN}Wings binary installed. Please configure it via the Panel.${NC}"
    sleep 3
}

remove_panel() {
    echo -e "${RED}Removing Panel...${NC}"
    rm -rf /var/www/pterodactyl
    mysql -u root -e "DROP DATABASE IF EXISTS panel;"
    mysql -u root -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';"
    echo -e "${GREEN}Panel removed.${NC}"
    sleep 2
}

remove_wings() {
    echo -e "${RED}Removing Wings...${NC}"
    systemctl stop wings
    rm -rf /etc/pterodactyl
    rm /usr/local/bin/wings
    echo -e "${GREEN}Wings removed.${NC}"
    sleep 2
}

# --- Main Menu Loop ---
while true; do
    show_logo
    echo -e "1) ${CYAN}Install Pterodactyl Panel${NC}"
    echo -e "2) ${CYAN}Install Wings${NC}"
    echo -e "3) ${CYAN}Install Panel + Wings (Full)${NC}"
    echo -e "4) ${RED}Remove Panel${NC}"
    echo -e "5) ${RED}Remove Wings${NC}"
    echo -e "6) ${YELLOW}Exit${NC}"
    echo "-----------------------------------------------------"
    read -p "Select an option [1-6]: " OPT

    case $OPT in
        1)
            install_panel
            ;;
        2)
            install_wings
            ;;
        3)
            install_panel
            install_wings
            ;;
        4)
            remove_panel
            ;;
        5)
            remove_wings
            ;;
        6)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            sleep 1
            ;;
    esac
done
