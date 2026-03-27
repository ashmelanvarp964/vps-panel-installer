#!/bin/bash

# ASTRA Pterodactyl Installer - Clean Working Version
# Panel + Wings + Firewall

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Variables
PANEL_DIR="/var/www/pterodactyl"
LOG_FILE="/var/log/astra_install.log"

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; echo "[$(date)] INFO: $1" >> "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; echo "[$(date)] ERROR: $1" >> "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; echo "[$(date)] WARN: $1" >> "$LOG_FILE"; }

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Please run as root: sudo bash $0${NC}"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        log_info "Detected OS: $PRETTY_NAME"
        
        if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
            log_error "Unsupported OS. Use Ubuntu 20.04/22.04/24.04 or Debian 11/12"
            exit 1
        fi
    else
        log_error "Cannot detect OS"
        exit 1
    fi
}

# Main Menu
show_menu() {
    clear
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}           ASTRA PTERODACTYL INSTALLER${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}1)${NC} Install Panel (Web Interface)"
    echo -e "${GREEN}2)${NC} Install Wings (Game Server Daemon)"
    echo -e "${GREEN}3)${NC} Install Both (Panel + Wings)"
    echo -e "${GREEN}4)${NC} Firewall Manager"
    echo -e "${GREEN}5)${NC} Exit"
    echo ""
    echo -ne "${WHITE}Choose option [1-5]: ${NC}"
    read choice
    
    case $choice in
        1) install_panel ;;
        2) install_wings ;;
        3) install_panel && install_wings ;;
        4) firewall_menu ;;
        5) exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 2; show_menu ;;
    esac
}

# Install Panel
install_panel() {
    clear
    echo -e "${CYAN}══ Panel Installation ══${NC}"
    echo ""
    
    # Get inputs
    read -p "Domain name (e.g., panel.example.com): " DOMAIN
    read -p "Admin email: " EMAIL
    read -sp "Admin password: " ADMIN_PASS; echo
    read -sp "Database password (pterodactyl user): " DB_PASS; echo
    
    log_info "Starting Panel installation..."
    
    # Update system
    log_info "Updating system..."
    apt update && apt upgrade -y
    
    # Install dependencies
    log_info "Installing dependencies..."
    apt install -y curl wget git unzip zip nginx mariadb-server redis-server \
        software-properties-common apt-transport-https ca-certificates gnupg \
        ufw supervisor cron
    
    # Install PHP
    log_info "Installing PHP 8.3..."
    add-apt-repository -y ppa:ondrej/php
    apt update
    apt install -y php8.3 php8.3-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip,intl}
    
    # Configure PHP
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.3/fpm/php.ini
    sed -i 's/^post_max_size = .*/post_max_size = 100M/' /etc/php/8.3/fpm/php.ini
    systemctl restart php8.3-fpm
    
    # Configure MariaDB
    log_info "Configuring database..."
    systemctl enable --now mariadb
    
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF
    
    # Install Composer
    log_info "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    
    # Download Panel
    log_info "Downloading Pterodactyl Panel..."
    mkdir -p $PANEL_DIR
    cd /tmp
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzf panel.tar.gz -C $PANEL_DIR --strip-components=1
    rm panel.tar.gz
    
    # Install Panel
    cd $PANEL_DIR
    composer install --no-dev --optimize-autoloader --no-interaction
    
    # Configure environment
    cp .env.example .env
    php artisan key:generate --force
    
    sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|" .env
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=panel|" .env
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|" .env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env
    sed -i "s|CACHE_DRIVER=.*|CACHE_DRIVER=redis|" .env
    sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=redis|" .env
    
    # Run migrations
    php artisan migrate --seed --force
    
    # Create admin user
    php artisan p:user:make --email="$EMAIL" --username=admin --name-first=Admin --name-last=User --password="$ADMIN_PASS" --admin=1
    
    # Set permissions
    chown -R www-data:www-data $PANEL_DIR
    chmod -R 755 $PANEL_DIR/storage $PANEL_DIR/bootstrap/cache
    
    # Configure Nginx
    log_info "Configuring Nginx..."
    rm -f /etc/nginx/sites-enabled/default
    
    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    root ${PANEL_DIR}/public;
    index index.php;
    
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
NGINX
    
    ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    
    # Install SSL
    log_info "Installing SSL certificate..."
    apt install -y certbot python3-certbot-nginx
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL
    
    # Configure queue worker
    cat > /etc/supervisor/conf.d/pteroq.conf <<SUPER
[program:pteroq]
command=php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
user=www-data
numprocs=2
autostart=true
autorestart=true
SUPER
    
    supervisorctl reread
    supervisorctl update
    
    # Setup cron
    echo "* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1" | crontab -
    
    # Configure firewall
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    echo "y" | ufw enable
    
    log_info "Panel installation complete!"
    echo -e "${GREEN}Panel URL: https://${DOMAIN}${NC}"
    echo -e "${GREEN}Username: admin${NC}"
    echo -e "${GREEN}Password: [the one you set]${NC}"
    
    read -p "Press Enter to continue..."
    show_menu
}

# Install Wings
install_wings() {
    clear
    echo -e "${CYAN}══ Wings Installation ══${NC}"
    echo ""
    
    log_info "Starting Wings installation..."
    
    # Install Docker
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker
    
    # Download Wings
    log_info "Downloading Wings..."
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
    chmod u+x /usr/local/bin/wings
    
    # Create systemd service
    cat > /etc/systemd/system/wings.service <<SERVICE
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
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE
    
    systemctl daemon-reload
    systemctl enable wings
    
    # Configure firewall
    ufw allow 8080/tcp
    ufw allow 2022/tcp
    ufw allow 25565/tcp
    ufw allow 25565/udp
    ufw allow 19132/udp
    
    log_info "Wings installation complete!"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Go to Panel → Admin → Nodes → Create Node"
    echo "2. Copy the configuration token"
    echo "3. Run: wings configure --panel-url https://YOUR-PANEL.com --token YOUR_TOKEN"
    echo "4. Run: systemctl start wings"
    echo ""
    
    read -p "Press Enter to continue..."
    show_menu
}

# Firewall Menu
firewall_menu() {
    clear
    echo -e "${CYAN}══ Firewall Manager ══${NC}"
    echo ""
    echo "1) Open Panel ports (80,443)"
    echo "2) Open Wings ports (8080,2022)"
    echo "3) Open Minecraft ports (25565,19132)"
    echo "4) Open custom port"
    echo "5) Show UFW status"
    echo "6) Back to main menu"
    echo ""
    read -p "Choose option: " fw_choice
    
    case $fw_choice in
        1) ufw allow 80/tcp; ufw allow 443/tcp; log_info "Panel ports opened" ;;
        2) ufw allow 8080/tcp; ufw allow 2022/tcp; log_info "Wings ports opened" ;;
        3) ufw allow 25565/tcp; ufw allow 25565/udp; ufw allow 19132/udp; log_info "Minecraft ports opened" ;;
        4) read -p "Port number: " port; ufw allow $port; log_info "Port $port opened" ;;
        5) ufw status verbose ;;
        6) show_menu ;;
    esac
    
    read -p "Press Enter to continue..."
    firewall_menu
}

# Run
check_root
detect_os
show_menu
