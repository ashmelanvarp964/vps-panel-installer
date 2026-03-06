#!/bin/bash

# --- ICONIC PANEL INSTALLER ---
# OS Support: Ubuntu 22.04+, Debian 11+
# Features: Animated Intro, Spinner, Interactive Menu

# --- Color Palette ---
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
P='\033[0;35m'
C='\033[0;36m'
W='\033[1;37m'
NC='\033[0m'

# --- Initialization ---
set -e
if [ "$EUID" -ne 0 ]; then 
  echo -e "${R}Error: This script must be run as root.${NC}"
  exit 1
fi

# --- Animation: Intro ---
animate_intro() {
    clear
    local logo=(
        "  _____ _____  ____  _   _ _____ _____ "
        " |_   _/ ____|/ __ \| \ | |_   _/ ____|"
        "   | || |    | |  | |  \| | | || |     "
        "   | || |    | |  | | . ' | | || |     "
        "  _| || |____| |__| | |\  |_| || |____ "
        " |_____\_____|\____/|_| \_|_____\_____|"
    )
    for line in "${logo[@]}"; do
        echo -e "${C}${line}${NC}"
        sleep 0.1
    done
    echo -e "\n          ${W}PREMIUM AUTOMATED INSTALLER${NC}"
    echo -e "      ${G}Checking system compatibility...${NC}\n"
    sleep 1
}

# --- UI Helper: Spinner ---
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

# --- Functions: Installation ---

install_panel() {
    echo -e "${B}[1/4] Updating repositories...${NC}"
    apt update -y &> /dev/null & show_spinner
    
    echo -e "${B}[2/4] Installing PHP 8.2 & Dependencies...${NC}"
    # Repository logic
    if [[ $(lsb_release -si) == "Ubuntu" ]]; then
        add-apt-repository -y ppa:ondrej/php &> /dev/null
    else
        curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
        echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    fi
    apt update -y &> /dev/null
    apt install -y php8.2 php8.2-{cli,fpm,mysql,gd,curl,mbstring,bcmath,xml,zip} nginx mariadb-server redis-server curl git unzip tar software-properties-common &> /dev/null & show_spinner

    echo -e "${B}[3/4] Setting up Database...${NC}"
    DB_PASS=$(openssl rand -base64 12)
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel; CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1'; FLUSH PRIVILEGES;"

    echo -e "${B}[4/4] Downloading & Configuring Panel...${NC}"
    mkdir -p /var/www/pterodactyl && cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz &> /dev/null
    tar -xzvf panel.tar.gz &> /dev/null
    chmod -R 755 storage/* bootstrap/cache/
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer &> /dev/null
    cp .env.example .env
    composer install --no-dev --optimize-autoloader &> /dev/null & show_spinner
    
    php artisan key:generate --force
    php artisan p:environment:setup --author="admin@example.com" --url="http://$(curl -s ifconfig.me)" --timezone="UTC" --cache="redis" --session="redis" --queue="redis" --redis-host="127.0.0.1"
    sed -i "s/DB_PASSWORD=/DB_PASSWORD=$DB_PASS/" .env
    php artisan migrate --seed --force

    echo -e "${Y}--- ADMIN USER CREATION ---${NC}"
    php artisan p:user:make
    chown -R www-data:www-data /var/www/pterodactyl/*
    echo -e "${G}Panel installed successfully! Database Pass: $DB_PASS${NC}"
    sleep 3
}

install_wings() {
    echo -e "${B}Installing Docker & Wings...${NC}"
    curl -sSL https://get.docker.com/ | CHANNEL=stable sh &> /dev/null & show_spinner
    systemctl enable --now docker &> /dev/null
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" &> /dev/null
    chmod +x /usr/local/bin/wings
    
    # Systemd Service
    cat <<EOF > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now wings &> /dev/null
    echo -e "${G}Wings binary installed and service started.${NC}"
    sleep 2
}

install_blueprint() {
    echo -e "${P}Installing Blueprint Framework...${NC}"
    cd /var/www/pterodactyl
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &> /dev/null
    apt install -y nodejs &> /dev/null
    npm install -g yarn &> /dev/null
    curl -sL https://github.com/BlueprintFramework/framework/releases/latest/download/blueprint.sh -o blueprint.sh
    bash blueprint.sh
    echo -e "${G}Blueprint installation finished.${NC}"
    sleep 2
}

delete_panel() {
    echo -e "${R}!!! PERMANENTLY DELETING PANEL !!!${NC}"
    rm -rf /var/www/pterodactyl
    mysql -u root -e "DROP DATABASE IF EXISTS panel; DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';"
    echo -e "${Y}Panel files and database removed.${NC}"
    sleep 2
}

delete_wings() {
    systemctl stop wings || true
    rm -rf /etc/pterodactyl /usr/local/bin/wings /etc/systemd/system/wings.service
    echo -e "${Y}Wings binary and service removed.${NC}"
    sleep 2
}

# --- Main Menu Loop ---
animate_intro
while true; do
    clear
    echo -e "${C}==========================================${NC}"
    echo -e "         ${W}ICONIC PANEL INSTALLER${NC}"
    echo -e "${C}==========================================${NC}"
    echo -e " ${W}[1]${NC} ${G}Install Pterodactyl Panel${NC}"
    echo -e " ${W}[2]${NC} ${G}Install Wings${NC}"
    echo -e " ${W}[3]${NC} ${C}Full Installation (Panel + Wings)${NC}"
    echo -e " ${W}[4]${NC} ${P}Install Blueprint Extension${NC}"
    echo -e "------------------------------------------"
    echo -e " ${W}[5]${NC} ${R}Delete Panel${NC}"
    echo -e " ${W}[6]${NC} ${R}Delete Wings${NC}"
    echo -e " ${W}[0]${NC} Exit"
    echo -e "------------------------------------------"
    echo -ne "${Y}Choose option: ${NC}"
    read -r opt

    case $opt in
        1) install_panel ;;
        2) install_wings ;;
        3) install_panel; install_wings ;;
        4) install_blueprint ;;
        5) delete_panel ;;
        6) delete_wings ;;
        0) exit 0 ;;
        *) echo -e "${R}Invalid option.${NC}"; sleep 1 ;;
    esac
done
