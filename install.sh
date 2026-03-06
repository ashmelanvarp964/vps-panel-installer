```bash
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run this script as root.${NC}"
   exit 1
fi

animate() {
    text=$1
    for ((i=0;i<${#text};i++)); do
        echo -ne "${text:$i:1}"
        sleep 0.01
    done
    echo ""
}

logo() {
clear
echo -e "${CYAN}"
echo " █████  ███████ ██   ██ ███    ███ ███████ ██      "
echo "██   ██ ██      ██   ██ ████  ████ ██      ██      "
echo "███████ ███████ ███████ ██ ████ ██ █████   ██      "
echo "██   ██      ██ ██   ██ ██  ██  ██ ██      ██      "
echo "██   ██ ███████ ██   ██ ██      ██ ███████ ███████ "
echo -e "${BLUE}ASHMEL VPS PANEL INSTALLER v10${NC}"
echo ""
}

install_panel(){

logo

echo -e "${CYAN}Panel Installation${NC}"

read -p "Domain (panel.example.com): " FQDN
read -p "Admin Email: " EMAIL
read -s -p "Admin Password: " PASSWORD
echo ""

animate "Updating system..."

apt update -y

apt install -y \
curl \
tar \
unzip \
git \
redis-server \
nginx \
mariadb-server \
software-properties-common \
ca-certificates \
gnupg \
lsb-release

add-apt-repository -y ppa:ondrej/php
apt update -y

apt install -y \
php8.2 \
php8.2-cli \
php8.2-common \
php8.2-gd \
php8.2-mysql \
php8.2-mbstring \
php8.2-bcmath \
php8.2-xml \
php8.2-fpm \
php8.2-curl \
php8.2-zip

systemctl enable --now mariadb
systemctl enable --now redis-server

DBPASS=$(openssl rand -base64 12)

mysql <<EOF
CREATE DATABASE panel;
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz

tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

cp .env.example .env

composer install --no-dev --optimize-autoloader

php artisan key:generate --force

php artisan p:environment:setup \
--author="$EMAIL" \
--url="https://$FQDN" \
--timezone="UTC" \
--cache="redis" \
--session="database" \
--queue="redis" \
--redis-host="127.0.0.1" \
--redis-pass="null" \
--redis-port="6379"

php artisan p:environment:database \
--host="127.0.0.1" \
--port="3306" \
--database="panel" \
--username="pterodactyl" \
--password="$DBPASS"

php artisan migrate --seed --force

php artisan p:user:make \
--email="$EMAIL" \
--username="admin" \
--first_name="Admin" \
--last_name="User" \
--password="$PASSWORD" \
--admin=1

chown -R www-data:www-data /var/www/pterodactyl

cat <<EOF > /etc/nginx/sites-available/pterodactyl.conf
server {
    listen 80;
    server_name $FQDN;

    root /var/www/pterodactyl/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf

systemctl restart nginx
systemctl restart php8.2-fpm

echo -e "${GREEN}Panel Installed Successfully!${NC}"

}

install_wings(){

logo

echo "Installing Docker..."

curl -sSL https://get.docker.com | bash

systemctl enable --now docker

mkdir -p /etc/pterodactyl

curl -L -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64

chmod +x /usr/local/bin/wings

cat <<EOF > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wings

echo -e "${GREEN}Wings Installed.${NC}"

}

delete_panel(){

rm -rf /var/www/pterodactyl
rm -f /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-available/pterodactyl.conf

mysql <<EOF
DROP DATABASE panel;
DROP USER 'pterodactyl'@'127.0.0.1';
EOF

systemctl restart nginx

echo "Panel deleted."

}

while true
do

logo

echo "1) Install Panel"
echo "2) Install Wings"
echo "3) Full Setup"
echo "4) Delete Panel"
echo "5) Exit"

read -p "Choose: " opt

case $opt in

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
delete_panel
;;

5)
exit
;;

*)
echo "Invalid option"
sleep 1
;;

esac

done
```
