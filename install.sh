#!/bin/bash

# Pterodactyl Panel & Wings Installer
# Author: iconic

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
FQDN=""
MYSQL_PASSWORD=""
MYSQL_USER="pterodactyl"
MYSQL_DB="panel"
ADMIN_EMAIL=""
ADMIN_USER="admin"
ADMIN_PASSWORD=""
OS=""
OS_VERSION=""
WEB_USER=""
PHP_SOCKET=""

# Banner
show_banner() {
    clear
    echo -e "${PURPLE}"
    echo "  ██╗ ██████╗ ██████╗ ███╗   ██╗██╗ ██████╗"
    echo "  ██║██╔════╝██╔═══██╗████╗  ██║██║██╔════╝"
    echo "  ██║██║     ██║   ██║██╔██╗ ██║██║██║     "
    echo "  ██║██║     ██║   ██║██║╚██╗██║██║██║     "
    echo "  ██║╚██████╗╚██████╔╝██║ ╚████║██║╚██████╗"
    echo "  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝ ╚═════╝"
    echo -e "${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}   Pterodactyl Panel & Wings Installer${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Error handler
error_exit() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root. Use: sudo ./install.sh"
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        error_exit "Cannot detect OS"
    fi
    
    # Set OS-specific variables
    case $OS in
        ubuntu)
            if [[ "${OS_VERSION}" == "20.04" || "${OS_VERSION}" == "22.04" || "${OS_VERSION}" == "24.04" ]]; then
                WEB_USER="www-data"
                PHP_SOCKET="/run/php/php8.3-fpm.sock"
            else
                error_exit "Ubuntu ${OS_VERSION} is not supported. Use 20.04, 22.04, or 24.04"
            fi
            ;;
        debian)
            if [[ "${OS_VERSION}" == "11" || "${OS_VERSION}" == "12" ]]; then
                WEB_USER="www-data"
                PHP_SOCKET="/run/php/php8.3-fpm.sock"
            else
                error_exit "Debian ${OS_VERSION} is not supported. Use 11 or 12"
            fi
            ;;
        centos|rhel|rocky|almalinux)
            WEB_USER="nginx"
            PHP_SOCKET="/run/php-fpm/www.sock"
            ;;
        *)
            error_exit "Unsupported OS: $OS. Supported: Ubuntu 20.04/22.04/24.04, Debian 11/12, CentOS/RHEL 8/9"
            ;;
    esac
    
    echo -e "${GREEN}Detected: $OS $OS_VERSION${NC}"
}

# Generate passwords
generate_passwords() {
    MYSQL_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
    ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9@#$%' </dev/urandom | head -c 16)
}

# Get FQDN
get_fqdn() {
    while true; do
        echo -e "${YELLOW}Enter your Fully Qualified Domain Name (FQDN):${NC}"
        read -rp "FQDN (e.g., panel.example.com): " FQDN
        
        if [[ -z "$FQDN" ]]; then
            echo -e "${RED}FQDN cannot be empty!${NC}"
        elif [[ ! "$FQDN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
            echo -e "${RED}Invalid FQDN format!${NC}"
        else
            break
        fi
    done
}

# Get admin email
get_admin_email() {
    while true; do
        echo -e "${YELLOW}Enter admin email address:${NC}"
        read -rp "Email: " ADMIN_EMAIL
        
        if [[ -z "$ADMIN_EMAIL" ]]; then
            echo -e "${RED}Email cannot be empty!${NC}"
        elif [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            echo -e "${RED}Invalid email format!${NC}"
        else
            break
        fi
    done
}

# Install dependencies for Ubuntu/Debian
install_dependencies_apt() {
    echo -e "${BLUE}[1/8] Updating system packages...${NC}"
    apt update -y && apt upgrade -y
    
    echo -e "${BLUE}[2/8] Installing base dependencies...${NC}"
    apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release
    
    echo -e "${BLUE}[3/8] Adding PHP repository...${NC}"
    if [[ "$OS" == "ubuntu" ]]; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    else
        # Debian
        curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
        dpkg -i /tmp/debsuryorg-archive-keyring.deb
        sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
    fi
    
    echo -e "${BLUE}[4/8] Adding MariaDB repository...${NC}"
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-10.11"
    
    apt update -y
    
    echo -e "${BLUE}[5/8] Installing PHP 8.3 and extensions...${NC}"
    apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl} || error_exit "Failed to install PHP"
    
    echo -e "${BLUE}[6/8] Installing MariaDB...${NC}"
    apt install -y mariadb-server || error_exit "Failed to install MariaDB"
    
    echo -e "${BLUE}[7/8] Installing Nginx and other packages...${NC}"
    apt install -y nginx tar unzip git redis-server certbot || error_exit "Failed to install Nginx/Redis"
    
    echo -e "${BLUE}[8/8] Starting services...${NC}"
    systemctl enable --now mariadb
    systemctl enable --now redis-server
    systemctl enable --now php8.3-fpm
    systemctl enable --now nginx
    
    echo -e "${GREEN}Dependencies installed successfully${NC}"
}

# Install dependencies for CentOS/RHEL
install_dependencies_dnf() {
    echo -e "${BLUE}[1/8] Updating system packages...${NC}"
    dnf update -y
    
    echo -e "${BLUE}[2/8] Installing EPEL repository...${NC}"
    dnf install -y epel-release
    
    echo -e "${BLUE}[3/8] Adding Remi repository for PHP...${NC}"
    dnf install -y https://rpms.remirepo.net/enterprise/remi-release-"$(rpm -E %rhel)".rpm
    dnf module reset php -y
    dnf module enable php:remi-8.3 -y
    
    echo -e "${BLUE}[4/8] Installing PHP 8.3 and extensions...${NC}"
    dnf install -y php php-{common,cli,gd,mysqlnd,mbstring,bcmath,xml,fpm,curl,zip,intl} || error_exit "Failed to install PHP"
    
    echo -e "${BLUE}[5/8] Installing MariaDB...${NC}"
    dnf install -y mariadb-server || error_exit "Failed to install MariaDB"
    
    echo -e "${BLUE}[6/8] Installing Nginx and other packages...${NC}"
    dnf install -y nginx tar unzip git redis certbot || error_exit "Failed to install Nginx/Redis"
    
    echo -e "${BLUE}[7/8] Configuring firewall...${NC}"
    firewall-cmd --add-service=http --permanent 2>/dev/null || true
    firewall-cmd --add-service=https --permanent 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
    
    echo -e "${BLUE}[8/8] Starting services...${NC}"
    systemctl enable --now mariadb
    systemctl enable --now redis
    systemctl enable --now php-fpm
    systemctl enable --now nginx
    
    # Fix PHP-FPM for nginx
    sed -i 's/user = apache/user = nginx/' /etc/php-fpm.d/www.conf
    sed -i 's/group = apache/group = nginx/' /etc/php-fpm.d/www.conf
    systemctl restart php-fpm
    
    echo -e "${GREEN}Dependencies installed successfully${NC}"
}

# Configure MariaDB
configure_database() {
    echo -e "${BLUE}Configuring database...${NC}"
    
    # Secure MariaDB
    mysql -u root <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    # Create database and user
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    
    echo -e "${GREEN}Database configured successfully${NC}"
}

# Download and install Pterodactyl Panel
install_panel() {
    echo -e "${BLUE}Downloading Pterodactyl Panel...${NC}"
    
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl || error_exit "Failed to create panel directory"
    
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz || error_exit "Failed to download panel"
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    rm panel.tar.gz
    
    echo -e "${BLUE}Installing Composer...${NC}"
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer || error_exit "Failed to install Composer"
    
    cp .env.example .env
    
    echo -e "${BLUE}Installing PHP dependencies...${NC}"
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction || error_exit "Composer install failed"
    
    echo -e "${BLUE}Configuring Panel...${NC}"
    php artisan key:generate --force
    
    # Configure environment
    php artisan p:environment:setup \
        --author="$ADMIN_EMAIL" \
        --url="https://$FQDN" \
        --timezone="UTC" \
        --cache="redis" \
        --session="redis" \
        --queue="redis" \
        --redis-host="127.0.0.1" \
        --redis-pass="" \
        --redis-port="6379" \
        --settings-ui=true \
        --telemetry=false \
        --no-interaction
    
    php artisan p:environment:database \
        --host="127.0.0.1" \
        --port="3306" \
        --database="$MYSQL_DB" \
        --username="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        --no-interaction
    
    echo -e "${BLUE}Running database migrations...${NC}"
    php artisan migrate --seed --force
    
    echo -e "${BLUE}Creating admin user...${NC}"
    php artisan p:user:make \
        --email="$ADMIN_EMAIL" \
        --username="$ADMIN_USER" \
        --name-first="Admin" \
        --name-last="User" \
        --password="$ADMIN_PASSWORD" \
        --admin=1 \
        --no-interaction
    
    chown -R "$WEB_USER":"$WEB_USER" /var/www/pterodactyl/*
    
    echo -e "${GREEN}Panel installed successfully${NC}"
}

# Setup SSL Certificate
setup_ssl() {
    echo -e "${BLUE}Setting up SSL certificate...${NC}"
    
    systemctl stop nginx
    
    certbot certonly --standalone \
        -d "$FQDN" \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        --no-eff-email || error_exit "Failed to obtain SSL certificate. Make sure your domain points to this server."
    
    echo -e "${GREEN}SSL certificate installed${NC}"
}

# Configure Nginx for Panel (Ubuntu/Debian)
configure_nginx_panel_apt() {
    echo -e "${BLUE}Configuring Nginx...${NC}"
    
    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${FQDN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${FQDN};

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    ssl_certificate /etc/letsencrypt/live/${FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FQDN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:${PHP_SOCKET};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t || error_exit "Nginx configuration test failed"
    
    echo -e "${GREEN}Nginx configured${NC}"
}

# Configure Nginx for Panel (CentOS/RHEL)
configure_nginx_panel_dnf() {
    echo -e "${BLUE}Configuring Nginx...${NC}"
    
    cat > /etc/nginx/conf.d/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${FQDN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${FQDN};

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    ssl_certificate /etc/letsencrypt/live/${FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FQDN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:${PHP_SOCKET};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    # Remove default config if exists
    rm -f /etc/nginx/conf.d/default.conf
    
    # SELinux permissions
    setsebool -P httpd_can_network_connect 1 2>/dev/null || true
    setsebool -P httpd_execmem 1 2>/dev/null || true
    
    nginx -t || error_exit "Nginx configuration test failed"
    
    echo -e "${GREEN}Nginx configured${NC}"
}

# Configure crontab and queue worker
configure_queue() {
    echo -e "${BLUE}Configuring queue worker and crontab...${NC}"
    
    # Add crontab entry
    (crontab -l 2>/dev/null | grep -v "pterodactyl"; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
    
    # Create queue worker service (redis service name varies by OS)
    REDIS_SERVICE="redis-server.service"
    if [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
        REDIS_SERVICE="redis.service"
    fi
    
    cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=${REDIS_SERVICE}

[Service]
User=${WEB_USER}
Group=${WEB_USER}
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now pteroq.service
    
    echo -e "${GREEN}Queue worker configured${NC}"
}

# Install Wings
install_wings() {
    echo -e "${BLUE}Installing Docker...${NC}"
    
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash || error_exit "Failed to install Docker"
    
    systemctl enable --now docker
    
    echo -e "${BLUE}Creating Wings directory...${NC}"
    mkdir -p /etc/pterodactyl
    
    echo -e "${BLUE}Downloading Wings...${NC}"
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_arm64"
    else
        error_exit "Unsupported architecture: $ARCH"
    fi
    
    chmod u+x /usr/local/bin/wings
    
    echo -e "${BLUE}Creating Wings service...${NC}"
    cat > /etc/systemd/system/wings.service <<EOF
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
EOF

    systemctl daemon-reload
    systemctl enable wings
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}   Wings Installation Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "${CYAN}1. Log into your Panel at https://your-panel-domain${NC}"
    echo -e "${CYAN}2. Go to Admin -> Locations -> Create Location${NC}"
    echo -e "${CYAN}3. Go to Admin -> Nodes -> Create New Node${NC}"
    echo -e "${CYAN}4. Click on the node -> Configuration tab${NC}"
    echo -e "${CYAN}5. Copy the config and save to: /etc/pterodactyl/config.yml${NC}"
    echo -e "${CYAN}6. Start Wings: systemctl start wings${NC}"
    echo ""
}

# Install Cloudflare Tunnel
install_cloudflare_tunnel() {
    get_fqdn
    
    echo ""
    echo -e "${YELLOW}Enter your Cloudflare Tunnel Token:${NC}"
    echo -e "${CYAN}(Get it from: Cloudflare Dashboard -> Zero Trust -> Networks -> Tunnels -> Create)${NC}"
    read -rp "Token: " CF_TOKEN
    
    if [[ -z "$CF_TOKEN" ]]; then
        echo -e "${RED}Token cannot be empty!${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Installing cloudflared...${NC}"
    
    # Detect architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        CF_ARCH="amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        CF_ARCH="arm64"
    else
        error_exit "Unsupported architecture: $ARCH"
    fi
    
    case $OS in
        ubuntu|debian)
            curl -L --output /tmp/cloudflared.deb "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}.deb"
            dpkg -i /tmp/cloudflared.deb
            rm /tmp/cloudflared.deb
            ;;
        centos|rhel|rocky|almalinux)
            curl -L --output /tmp/cloudflared.rpm "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}.rpm"
            rpm -i /tmp/cloudflared.rpm || dnf install -y /tmp/cloudflared.rpm
            rm /tmp/cloudflared.rpm
            ;;
    esac
    
    echo -e "${BLUE}Installing Cloudflare Tunnel service...${NC}"
    cloudflared service install "$CF_TOKEN" || error_exit "Failed to install cloudflared service"
    
    systemctl enable --now cloudflared
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}   Cloudflare Tunnel Installed!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Your tunnel is now running!${NC}"
    echo ""
    echo -e "${YELLOW}Configure public hostname in Cloudflare Dashboard:${NC}"
    echo -e "${CYAN}Zero Trust -> Networks -> Tunnels -> Your Tunnel -> Public Hostname${NC}"
    echo -e "${CYAN}  - Subdomain: panel (or your choice)${NC}"
    echo -e "${CYAN}  - Domain: your-domain.com${NC}"
    echo -e "${CYAN}  - Service: http://localhost:80${NC}"
    echo ""
}

# Full Panel Installation
full_panel_install() {
    get_fqdn
    get_admin_email
    generate_passwords
    
    echo ""
    echo -e "${BLUE}Starting Pterodactyl Panel installation...${NC}"
    echo -e "${CYAN}This may take 5-10 minutes depending on your server.${NC}"
    echo ""
    
    case $OS in
        ubuntu|debian)
            install_dependencies_apt
            ;;
        centos|rhel|rocky|almalinux)
            install_dependencies_dnf
            ;;
    esac
    
    configure_database
    install_panel
    setup_ssl
    
    case $OS in
        ubuntu|debian)
            configure_nginx_panel_apt
            ;;
        centos|rhel|rocky|almalinux)
            configure_nginx_panel_dnf
            ;;
    esac
    
    configure_queue
    
    systemctl restart nginx
    
    # Restart PHP-FPM
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        systemctl restart php8.3-fpm
    else
        systemctl restart php-fpm
    fi
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}   Pterodactyl Panel Installation Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Panel Access:${NC}"
    echo -e "  URL:      ${CYAN}https://${FQDN}${NC}"
    echo -e "  Username: ${CYAN}${ADMIN_USER}${NC}"
    echo -e "  Email:    ${CYAN}${ADMIN_EMAIL}${NC}"
    echo -e "  Password: ${CYAN}${ADMIN_PASSWORD}${NC}"
    echo ""
    echo -e "${YELLOW}Database Credentials:${NC}"
    echo -e "  Host:     ${CYAN}127.0.0.1${NC}"
    echo -e "  Database: ${CYAN}${MYSQL_DB}${NC}"
    echo -e "  Username: ${CYAN}${MYSQL_USER}${NC}"
    echo -e "  Password: ${CYAN}${MYSQL_PASSWORD}${NC}"
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  SAVE THESE CREDENTIALS NOW! They will not be shown again.               ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main menu
main_menu() {
    show_banner
    detect_os
    echo ""
    echo -e "${YELLOW}Select an option:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Install Pterodactyl Panel"
    echo -e "  ${GREEN}2)${NC} Install Wings (Node)"
    echo -e "  ${GREEN}3)${NC} Setup Cloudflare Tunnel"
    echo -e "  ${GREEN}4)${NC} Exit"
    echo ""
    read -rp "Enter your choice [1-4]: " choice
    
    case $choice in
        1)
            full_panel_install
            ;;
        2)
            install_wings
            ;;
        3)
            install_cloudflare_tunnel
            ;;
        4)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option!${NC}"
            sleep 2
            main_menu
            ;;
    esac
}

# Run
check_root
main_menu
