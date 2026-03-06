#!/bin/bash

# ================================================================= #
#                ICONIC PANEL INSTALLER - FULL TURBO                #
# ================================================================= #

# --- Color Palette ---
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
P='\033[0;35m'
C='\033[0;36m'
W='\033[1;37m'
NC='\033[0m'

# --- Fast Init ---
set -e
export DEBIAN_FRONTEND=noninteractive

if [ "$EUID" -ne 0 ]; then 
  echo -e "${R}Error: Run as root.${NC}"
  exit 1
fi

# --- UI: Spinner ---
show_spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " ${C}[%c]${NC}  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# --- UI: Big Header ---
animate_intro() {
    clear
    echo -e "${C}"
    echo "  ██╗ ██████╗ ██████╗ ███╗   ██╗██╗ ██████╗"
    echo "  ██║██╔════╝██╔═══██╗████╗  ██║██║██╔════╝"
    echo "  ██║██║     ██║   ██║██╔██╗ ██║██║██║     "
    echo "  ██║██║     ██║   ██║██║╚██╗██║██║██║     "
    echo "  ██║╚██████╗╚██████╔╝██║ ╚████║██║╚██████╗"
    echo "  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝ ╚═════╝"
    echo -e "      ${W}P  A  N  E  L     I  N  S  T  A  L  L  E  R${NC}"
    echo -e "${C}  ===============================================${NC}"
    echo -e "          ${Y}AUTOMATIC PANEL AND WINGS INSTALLER${NC}"
    echo -e "${C}  ===============================================${NC}"
}

install_panel() {
    animate_intro
    
    # --- Interactive Inputs ---
    echo -e "${W}Please enter the following details:${NC}"
    read -p "FQDN (e.g. panel.example.com): " FQDN
    read -p "Admin Email: " ADMIN_EMAIL
    read -p "Admin Username: " ADMIN_USER
    read -p "Admin First Name: " ADMIN_FIRST
    read -p "Admin Last Name: " ADMIN_LAST
    read -s -p "Admin Password: " ADMIN_PASS
    echo -e "\n"

    echo -e "${B}>> Fast-tracking Dependencies & Redis...${NC}"
    
    # Repo Setup
    OS=$(lsb_release -si)
    if [ "$OS" == "Ubuntu" ]; then
        add-apt-repository -y ppa:ondrej/php &> /dev/null
    else
        apt install -y wget &> /dev/null
        wget -O /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg &> /dev/null
        echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    fi

    # Batch Install
    apt-get update -y &> /dev/null
    apt-get install -y -qq php8.2 php8.2-{cli,fpm,mysql,gd,curl,mbstring,bcmath,xml,zip} nginx mariadb-server redis-server curl git unzip tar &> /dev/null & show_spinner

    # --- Redis & MariaDB Auto-Config ---
    systemctl enable --now redis-server
    DB_PASS=$(openssl rand -base64 12)
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel; CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1'; FLUSH PRIVILEGES;"

    # --- Panel Files ---
    mkdir -p /var/www/pterodactyl && cd /var/www/pterodactyl
    curl -sL https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv
    chmod -R 755 storage/* bootstrap/cache/

    # --- Composer Turbo ---
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer &> /dev/null
    cp .env.example .env
    composer install --no-dev --optimize-autoloader --quiet &> /dev/null & show_spinner
    
    # --- Environment Auto-Setup ---
    php artisan key:generate --force
    php artisan p:environment:setup --author="$ADMIN_EMAIL" --url="https://$FQDN" --timezone="UTC" --cache="redis" --session="redis" --queue="redis" --redis-host="127.0.0.1"
    sed -i "s/DB_PASSWORD=/DB_PASSWORD=$DB_PASS/" .env
    
    # Database Migration
    php artisan migrate --seed --force --quiet

    # --- Admin Creation ---
    php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --first_name="$ADMIN_FIRST" --last_name="$ADMIN_LAST" --password="$ADMIN_PASS" --admin=1

    # Permissions
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    echo -e "${G}✔ PANEL INSTALLED!${NC}"
    echo -e "${W}Login at: ${CYAN}https://$FQDN${NC}"
    echo -e "${W}DB Pass: ${Y}$DB_PASS${NC}"
    sleep 3
}

install_wings() {
    animate_intro
    echo -e "${B}>> Deploying Docker & Wings...${NC}"
    curl -sSL https://get.docker.com/ | CHANNEL=stable sh &> /dev/null & show_spinner
    systemctl enable --now docker &> /dev/null

    mkdir -p /etc/pterodactyl
    curl -L -s -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
    chmod +x /usr/local/bin/wings
    
    # Fast Service Creation
    printf "[Unit]\nDescription=Pterodactyl Wings\nAfter=docker.service\n[Service]\nUser=root\nWorkingDirectory=/etc/pterodactyl\nExecStart=/usr/local/bin/wings\nRestart=always\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/wings.service
    systemctl enable --now wings &> /dev/null
    echo -e "${G}✔ WINGS READY!${NC}"
    sleep 2
}

# --- Main Logic ---
while true; do
    animate_intro
    echo -e "  ${W}[1]${NC} ${G}FAST INSTALL PANEL${NC}"
    echo -e "  ${W}[2]${NC} ${G}FAST INSTALL WINGS${NC}"
    echo -e "  ${W}[3]${NC} ${B}FULL TURBO INSTALL${NC}"
    echo -e "  ${W}[4]${NC} ${P}INSTALL BLUEPRINT${NC}"
    echo -e "  ${C}───────────────────────────────────────────────${NC}"
    echo -e "  ${W}[5] Delete Panel  [6] Delete Wings  [0] Exit${NC}"
    echo -ne "  ${W}CHOICE:${NC} "
    read -r opt
    case $opt in
        1) install_panel ;;
        2) install_wings ;;
        3) install_panel; install_wings ;;
        4) cd /var/www/pterodactyl && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs && npm install -g yarn && curl -sL https://github.com/BlueprintFramework/framework/releases/latest/download/blueprint.sh -o blueprint.sh && bash blueprint.sh ;;
        5) rm -rf /var/www/pterodactyl && mysql -e "DROP DATABASE IF EXISTS panel;" ;;
        6) systemctl stop wings && rm -rf /etc/pterodactyl /usr/local/bin/wings ;;
        0) exit 0 ;;
    esac
done
