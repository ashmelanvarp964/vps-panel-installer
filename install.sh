#!/bin/bash
################################################################################
# ICONIC TESCH PTERODACTYL PANEL INSTALLER
# Complete automatic installation script for Pterodactyl Panel + Wings
# Version: 2.0.0
# Author: Iconic Tesch
# Supported OS: Ubuntu 20.04, 22.04, 24.04 | Debian 11, 12
################################################################################

# ================ CONFIGURATION ================
# You can modify these variables before running
PANEL_DOMAIN=""                    # Leave empty for IP-based installation
LETSENCRYPT_EMAIL=""                # Email for SSL (optional)
TIMEZONE="Asia/Kolkata"             # Set your timezone
INSTALL_WINGS="yes"                  # Install Wings? (yes/no)
ICONIC_WELCOME="yes"                 # Show branded messages?

# Branding colors
ICONIC_GREEN='\033[0;32m'
ICONIC_BLUE='\033[0;34m'
ICONIC_GOLD='\033[0;33m'
ICONIC_RED='\033[0;31m'
ICONIC_CYAN='\033[0;36m'
ICONIC_PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# ================ INITIALIZATION ================
set -e  # Exit on error
set -u  # Exit on undefined variable

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${ICONIC_RED}This script must be run as root!${NC}" 
   exit 1
fi

# ================ BRANDING FUNCTIONS ================
show_banner() {
    clear
    echo -e "${ICONIC_GREEN}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_GOLD}         ██╗ ██████╗ ██████╗ ███╗   ██╗██╗ ██████╗          ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_GOLD}         ██║██╔════╝██╔═══██╗████╗  ██║██║██╔════╝          ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_GOLD}         ██║██║     ██║   ██║██╔██╗ ██║██║██║               ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_GOLD}         ██║██║     ██║   ██║██║╚██╗██║██║██║               ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_GOLD}         ██║╚██████╗╚██████╔╝██║ ╚████║██║╚██████╗          ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_GOLD}         ╚═╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝ ╚═════╝          ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_BLUE}           ████████╗███████╗███████╗ ██████╗██╗  ██╗         ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_BLUE}           ╚══██╔══╝██╔════╝██╔════╝██╔════╝██║  ██║         ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_BLUE}              ██║   █████╗  ███████╗██║     ███████║         ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_BLUE}              ██║   ██╔══╝  ╚════██║██║     ██╔══██║         ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_BLUE}              ██║   ███████╗███████║╚██████╗██║  ██║         ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}│${ICONIC_BLUE}              ╚═╝   ╚══════╝╚══════╝ ╚═════╝╚═╝  ╚═╝         ${ICONIC_GREEN}│${NC}"
    echo -e "${ICONIC_GREEN}└─────────────────────────────────────────────────────────┘${NC}"
    echo -e "${ICONIC_PURPLE}              Pterodactyl Panel Automatic Installer v2.0${NC}"
    echo -e "${ICONIC_GOLD}              ⚡ Powered by Iconic Tesch ⚡${NC}"
    echo ""
}

show_progress() {
    echo -e "${ICONIC_CYAN}[ICONIC]${NC} $1"
}

show_success() {
    echo -e "${ICONIC_GREEN}[✓]${NC} $1"
}

show_error() {
    echo -e "${ICONIC_RED}[✗]${NC} $1"
}

show_warning() {
    echo -e "${ICONIC_GOLD}[!]${NC} $1"
}

# ================ SYSTEM CHECKS ================
check_system() {
    show_progress "Checking system compatibility..."
    
    # Check OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        show_error "Cannot detect OS"
        exit 1
    fi
    
    # Supported OS check
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        show_error "This script only supports Ubuntu and Debian"
        exit 1
    fi
    
    # Version check
    if [[ "$OS" == "ubuntu" ]]; then
        if [[ "$VERSION" != "20.04" && "$VERSION" != "22.04" && "$VERSION" != "24.04" ]]; then
            show_error "Ubuntu version must be 20.04, 22.04, or 24.04"
            exit 1
        fi
    elif [[ "$OS" == "debian" ]]; then
        if [[ "$VERSION" != "11" && "$VERSION" != "12" ]]; then
            show_error "Debian version must be 11 or 12"
            exit 1
        fi
    fi
    
    show_success "System: $OS $VERSION"
    
    # Check memory
    total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $total_ram -lt 1000 ]]; then
        show_warning "Less than 1GB RAM detected. Performance may be poor."
    else
        show_success "Memory: ${total_ram}MB"
    fi
    
    # Check disk space
    available_disk=$(df -m / | awk 'NR==2 {print $4}')
    if [[ $available_disk -lt 5120 ]]; then
        show_error "At least 5GB free disk space required"
        exit 1
    else
        show_success "Disk space: ${available_disk}MB available"
    fi
}

# ================ INSTALLATION FUNCTIONS ================
install_dependencies() {
    show_progress "Installing system dependencies..."
    
    apt update -y
    apt upgrade -y
    
    # Install required packages
    apt install -y curl wget git unzip zip tar \
        software-properties-common apt-transport-https \
        ca-certificates gnupg lsb-release \
        ufw fail2ban redis-server \
        nginx certbot python3-certbot-nginx \
        mariadb-server mariadb-client
        
    show_success "Dependencies installed"
}

install_php() {
    show_progress "Installing PHP 8.2..."
    
    if [[ "$OS" == "ubuntu" ]]; then
        add-apt-repository ppa:ondrej/php -y
    elif [[ "$OS" == "debian" ]]; then
        curl -sSL https://packages.sury.org/php/README.txt | bash -s
    fi
    
    apt update -y
    apt install -y php8.2 php8.2-{cli,common,mbstring,bcmath,xml,fpm,curl,zip,mysql,gd,tokenizer,redis}
    
    # Configure PHP
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.2/fpm/php.ini
    sed -i 's/post_max_size = .*/post_max_size = 100M/' /etc/php/8.2/fpm/php.ini
    sed -i 's/max_execution_time = .*/max_execution_time = 180/' /etc/php/8.2/fpm/php.ini
    
    systemctl enable php8.2-fpm
    systemctl start php8.2-fpm
    
    show_success "PHP 8.2 installed"
}

install_composer() {
    show_progress "Installing Composer..."
    
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    
    show_success "Composer installed"
}

install_mariadb() {
    show_progress "Configuring MariaDB..."
    
    systemctl enable mariadb
    systemctl start mariadb
    
    # Secure MariaDB installation
    mysql -e "DELETE FROM mysql.user WHERE User=''"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
    mysql -e "DROP DATABASE IF EXISTS test"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
    mysql -e "FLUSH PRIVILEGES"
    
    show_success "MariaDB configured"
}

install_redis() {
    show_progress "Configuring Redis..."
    
    systemctl enable redis-server
    systemctl start redis-server
    
    show_success "Redis configured"
}

setup_panel_database() {
    show_progress "Creating panel database..."
    
    DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 24 | head -n 1)
    
    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD'"
    mysql -u root -e "CREATE DATABASE panel"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION"
    mysql -u root -e "FLUSH PRIVILEGES"
    
    # Save credentials
    echo "Database: panel" > /root/pterodactyl_db_credentials.txt
    echo "Username: pterodactyl" >> /root/pterodactyl_db_credentials.txt
    echo "Password: $DB_PASSWORD" >> /root/pterodactyl_db_credentials.txt
    
    show_success "Database created. Credentials saved to /root/pterodactyl_db_credentials.txt"
}

install_panel() {
    show_progress "Installing Pterodactyl Panel..."
    
    # Create pterodactyl user
    useradd -r -m -d /var/www/pterodactyl -s /bin/bash pterodactyl
    
    # Download panel
    cd /var/www
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzf panel.tar.gz -C pterodactyl
    chown -R pterodactyl:pterodactyl /var/www/pterodactyl
    chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache
    
    # Install dependencies
    cd /var/www/pterodactyl
    sudo -u pterodactyl composer install --no-dev --optimize-autoloader --no-interaction
    
    # Setup environment
    sudo -u pterodactyl cp .env.example .env
    
    # Generate key
    php artisan key:generate --force
    
    # Configure environment
    sudo -u pterodactyl php artisan p:environment:setup \
        --author="$LETSENCRYPT_EMAIL" \
        --url="http://${PANEL_DOMAIN:-$(curl -4s https://ifconfig.io)}" \
        --timezone="$TIMEZONE" \
        --cache="redis" \
        --session="redis" \
        --queue="redis" \
        --redis-host="localhost" \
        --redis-pass="null" \
        --redis-port="6379" \
        --settings-ui="yes"
    
    show_progress "Configuring database connection..."
    
    # Configure database
    sudo -u pterodactyl php artisan p:environment:database \
        --host="127.0.0.1" \
        --port="3306" \
        --database="panel" \
        --username="pterodactyl" \
        --password="$DB_PASSWORD"
    
    # Run migrations
    sudo -u pterodactyl php artisan migrate --seed --force
    
    # Create admin user
    echo ""
    echo -e "${ICONIC_GOLD}Please enter admin account details:${NC}"
    read -p "Admin Email: " ADMIN_EMAIL
    read -p "Admin Username: " ADMIN_USERNAME
    read -s -p "Admin Password: " ADMIN_PASSWORD
    echo ""
    
    sudo -u pterodactyl php artisan p:user:make \
        --email="$ADMIN_EMAIL" \
        --username="$ADMIN_USERNAME" \
        --password="$ADMIN_PASSWORD" \
        --admin=1
    
    # Set permissions
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    show_success "Pterodactyl Panel installed"
}

configure_nginx() {
    show_progress "Configuring Nginx..."
    
    if [[ -z "$PANEL_DOMAIN" ]]; then
        # IP-based installation
        SERVER_IP=$(curl -4s https://ifconfig.io)
        cat > /etc/nginx/sites-available/pterodactyl << EOF
server {
    listen 80;
    server_name $SERVER_IP;
    
    root /var/www/pterodactyl/public;
    index index.php;
    
    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log;
    
    client_max_body_size 100m;
    client_body_timeout 120s;
    
    sendfile off;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF
    else
        # Domain-based installation
        cat > /etc/nginx/sites-available/pterodactyl << EOF
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $PANEL_DOMAIN;
    
    root /var/www/pterodactyl/public;
    index index.php;
    
    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log;
    
    client_max_body_size 100m;
    client_body_timeout 120s;
    
    sendfile off;
    
    ssl_certificate /etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PANEL_DOMAIN/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;
    
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_read_timeout 300s;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF
    fi
    
    # Enable site
    ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test and reload
    nginx -t
    systemctl reload nginx
    
    show_success "Nginx configured"
}

setup_ssl() {
    if [[ -n "$PANEL_DOMAIN" && -n "$LETSENCRYPT_EMAIL" ]]; then
        show_progress "Setting up SSL certificate..."
        
        certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email "$LETSENCRYPT_EMAIL"
        
        # Setup auto-renewal
        systemctl enable certbot.timer
        systemctl start certbot.timer
        
        show_success "SSL certificate installed"
    fi
}

install_wings() {
    show_progress "Installing Pterodactyl Wings..."
    
    # Install Docker
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    
    # Install required packages
    apt install -y docker-compose-plugin
    
    # Create necessary directories
    mkdir -p /etc/pterodactyl /var/lib/pterodactyl
    
    # Download wings
    curl -L -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
    chmod u+x /usr/local/bin/wings
    
    # Create systemd service
    cat > /etc/systemd/system/wings.service << 'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/pid.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=600

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable wings
    
    show_success "Wings installed"
    
    # Configure Wings
    echo ""
    show_warning "To complete Wings setup, you need to:"
    echo "1. Go to your Panel admin area (http://$SERVER_IP/admin/nodes)"
    echo "2. Create a new node"
    echo "3. Generate a configuration token"
    echo "4. Run: wings configure --panel http://$SERVER_IP --token YOUR_TOKEN --node 1"
    echo ""
}

configure_firewall() {
    show_progress "Configuring firewall..."
    
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow 8080/tcp comment 'Wings HTTP'
    ufw allow 2022/tcp comment 'Wings SFTP'
    
    # Game ports range
    ufw allow 25565:26000/tcp comment 'Game Ports TCP'
    ufw allow 25565:26000/udp comment 'Game Ports UDP'
    
    echo "y" | ufw enable
    ufw reload
    
    show_success "Firewall configured"
}

setup_cron() {
    show_progress "Setting up cron jobs..."
    
    # Add cron for panel
    echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1" | crontab -u www-data -
    
    show_success "Cron jobs configured"
}

configure_queue_worker() {
    show_progress "Configuring queue worker..."
    
    cat > /etc/systemd/system/pteroq.service << EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable pteroq
    systemctl start pteroq
    
    show_success "Queue worker configured"
}

# ================ MAIN INSTALLATION ================
main() {
    show_banner
    
    echo -e "${ICONIC_GOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e "${ICONIC_GOLD}     Welcome to Iconic Tesch Pterodactyl Installer${NC}"
    echo -e "${ICONIC_GOLD}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Ask for installation preferences
    read -p "Enter your domain (leave empty for IP-based): " PANEL_DOMAIN
    if [[ -n "$PANEL_DOMAIN" ]]; then
        read -p "Enter email for SSL (required for domain): " LETSENCRYPT_EMAIL
    fi
    
    read -p "Install Wings as well? (yes/no): " INSTALL_WINGS
    
    # System checks
    check_system
    
    # Installation
    install_dependencies
    install_php
    install_composer
    install_mariadb
    install_redis
    
    setup_panel_database
    install_panel
    configure_nginx
    
    if [[ -n "$PANEL_DOMAIN" && -n "$LETSENCRYPT_EMAIL" ]]; then
        setup_ssl
    fi
    
    configure_firewall
    setup_cron
    configure_queue_worker
    
    if [[ "$INSTALL_WINGS" == "yes" ]]; then
        install_wings
    fi
    
    # Final output
    echo ""
    echo -e "${ICONIC_GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${ICONIC_GOLD}     🎉 INSTALLATION COMPLETE! 🎉${NC}"
    echo -e "${ICONIC_GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${ICONIC_CYAN}Panel URL:${NC} http://${PANEL_DOMAIN:-$(curl -4s https://ifconfig.io)}"
    echo -e "${ICONIC_CYAN}Database Credentials:${NC} /root/pterodactyl_db_credentials.txt"
    echo ""
    echo -e "${ICONIC_GOLD}Next Steps:${NC}"
    echo "1. Visit your panel URL and login with your admin credentials"
    echo "2. Configure your nodes and locations"
    echo "3. Add allocations (ports) for your game servers"
    echo ""
    
    if [[ "$INSTALL_WINGS" == "yes" ]]; then
        echo -e "${ICONIC_PURPLE}To complete Wings setup:${NC}"
        echo "1. Go to Panel > Admin > Nodes"
        echo "2. Create a new node and copy the configuration token"
        echo "3. Run: wings configure --panel http://${PANEL_DOMAIN:-$(curl -4s https://ifconfig.io)} --token YOUR_TOKEN --node 1"
        echo "4. Start Wings: systemctl start wings"
        echo ""
    fi
    
    echo -e "${ICONIC_GREEN}Thank you for using Iconic Tesch Installer!${NC}"
    echo -e "${ICONIC_GOLD}Support: https://discord.gg/iconictesch${NC}"
    echo ""
}

# Run main function
main
