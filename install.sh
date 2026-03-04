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
   echo -e "${RED}Error: This script must be run as root (sudo).${NC}"
   exit 1
fi

# --- UI Functions ---
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
    echo -e "${BLUE}          ASHMEL VPS PANEL INSTALLER v8.0${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
}

# --- Panel Installation ---
install_panel() {
    show_logo
    echo -e "${CYAN}[ PANEL INSTALLATION ]${NC}"
    read -p "Panel Domain (FQDN): " FQDN
    read -p "Admin Email: " ADMIN_EMAIL
    read -s -p "Admin Password: " ADMIN_PASS
    echo -e "\n"

    animate_text "Installing Dependencies & MariaDB..." "$YELLOW"
    apt update -y && apt install -y software-properties-common curl ca-certificates gnupg2 sudo unzip tar git
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    apt update -y
    apt install -y php8.2 php8.2-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} nginx mariadb-server
    
    # FIX: Ensure MariaDB is running and enabled
    systemctl enable mariadb
    systemctl start mariadb
    sleep 2 # Give MariaDB time to start

    animate_text "Configuring Database Permissions..." "$CYAN"
    DB_PASS=$(openssl rand -base64 14)
    # Ensure local root access is active and create the pterodactyl user
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    mkdir -p /var/www/pterodactyl && cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    cp .env.example .env
    composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
    
    # FIX: Automating the connection to avoid the error in your image
    animate_text "Linking Panel to Database..." "$YELLOW"
    php artisan p:environment:setup --author="$ADMIN_EMAIL" --url="https://$FQDN" --timezone="UTC" --cache="file" --session="database" --queue="database"
    php artisan p:environment:database --host="127.0.0.1" --port="3306" --database="panel" --username="pterodactyl" --password="$DB_PASS"
    
    php artisan migrate --seed --force
    php artisan p:user:make --email="$ADMIN_EMAIL" --username="admin" --first_name="Ashmel" --last_name="User" --password="$ADMIN_PASS" --admin=1
    chown -R www-data:www-data /var/www/pterodactyl/*

    # Nginx Config
    cat <<EOF > /etc/nginx/sites-available/pterodactyl.conf
server {
    listen 80;
    server_name $FQDN;
    root /var/www/pterodactyl/public;
    index index.php;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
    ln -s -f /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    systemctl restart nginx
    animate_text "Panel Fixed and Installed! Access at http://$FQDN" "$GREEN"; sleep 2
}

# --- Wings Installation ---
install_wings() {
    animate_text "Installing Docker and Wings..." "$YELLOW"
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
    chmod u+x /usr/local/bin/wings
    animate_text "Wings Installed." "$GREEN"; sleep 2
}

# --- Extension Sub-Menu ---
extension_menu() {
    while true; do
        show_logo
        echo -e "  ${MAGENTA}[ EXTENSIONS MENU ]${NC}"
        echo -e "  [1] Install Blueprint Framework"
        echo -e "  [2] Install Nebula Theme"
        echo -e "  [3] Back to Main Menu"
        echo -e "${CYAN}-----------------------------------------------------${NC}"
        echo -ne "${BLUE}Select Option: ${NC}"
        read EXOPT
        case $EXOPT in
            1)
                animate_text "Installing Node.js & Blueprint..." "$YELLOW"
                curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
                apt install -y nodejs
                cd /var/www/pterodactyl
                curl -L https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip -o release.zip
                unzip -o release.zip && rm release.zip
                bash blueprint.sh
                animate_text "Blueprint Ready." "$GREEN"; sleep 2 ;;
            2)
                if [ ! -f "/var/www/pterodactyl/blueprint.sh" ]; then
                    echo -e "${RED}Error: Install Blueprint first!${NC}"; sleep 2
                else
                    animate_text "Installing Nebula Theme..." "$CYAN"
                    cd /var/www/pterodactyl
                    curl -L -o nebula.blueprint https://github.com/prplwtf/Nebula/releases/latest/download/nebula.blueprint
                    php blueprint.sh install nebula
                    chown -R www-data:www-data /var/www/pterodactyl/*
                    animate_text "Nebula Theme Installed!" "$GREEN"; sleep 2
                fi ;;
            3) break ;;
        esac
    done
}

# --- Deep Clean Delete Functions ---
delete_panel() {
    show_logo
    animate_text "Full Panel Wipe in progress..." "$RED"
    rm -rf /var/www/pterodactyl
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    systemctl restart nginx
    mysql -u root -e "DROP DATABASE IF EXISTS panel; DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';"
    animate_text "Panel wiped." "$GREEN"; sleep 2
}

delete_wings() {
    show_logo
    animate_text "Stopping and Deleting Wings..." "$RED"
    systemctl stop wings 2>/dev/null
    rm -rf /etc/pterodactyl
    rm -f /usr/local/bin/wings
    rm -f /etc/systemd/system/wings.service
    systemctl daemon-reload
    animate_text "Wings wiped." "$GREEN"; sleep 2
}

# --- Main Menu Loop ---
while true; do
    show_logo
    echo -e "  [1] ${CYAN}Fix/Install Pterodactyl Panel${NC}"
    echo -e "  [2] ${CYAN}Install Wings${NC}"
    echo -e "  [3] ${CYAN}Full Setup (Panel + Wings)${NC}"
    echo -e "  [4] ${MAGENTA}Extensions (Blueprint & Nebula)${NC}"
    echo -e "  [5] ${RED}Delete Panel (Deep Clean)${NC}"
    echo -e "  [6] ${RED}Delete Wings (Deep Clean)${NC}"
    echo -e "  [7] ${YELLOW}Exit Installer${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -ne "${BLUE}Select Action: ${NC}"
    read OPT
    case $OPT in
        1) install_panel ;;
        2) install_wings ;;
        3) install_panel; install_wings ;;
        4) extension_menu ;;
        5) delete_panel ;;
        6) delete_wings ;;
        7) exit 0 ;;
        *) echo -e "${RED}Invalid Selection${NC}"; sleep 1 ;;
    esac
done
