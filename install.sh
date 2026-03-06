```bash
#!/bin/bash

RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[1;35m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
echo -e "${RED}Please run as root${NC}"
exit
fi

spinner() {
pid=$!
spin='-\|/'
i=0
while kill -0 $pid 2>/dev/null; do
i=$(( (i+1) %4 ))
printf "\r${CYAN}[%c] Processing...${NC}" "${spin:$i:1}"
sleep .1
done
printf "\r"
}

logo(){
clear
echo -e "${CYAN}"
echo " █████╗ ███████╗██╗  ██╗███╗   ███╗███████╗██╗     "
echo "██╔══██╗██╔════╝██║  ██║████╗ ████║██╔════╝██║     "
echo "███████║███████╗███████║██╔████╔██║█████╗  ██║     "
echo "██╔══██║╚════██║██╔══██║██║╚██╔╝██║██╔══╝  ██║     "
echo "██║  ██║███████║██║  ██║██║ ╚═╝ ██║███████╗███████╗"
echo ""
echo -e "${MAGENTA}ASHMEL VPS PANEL INSTALLER v2${NC}"
echo -e "${CYAN}-----------------------------------------${NC}"
}

install_panel(){

logo
echo -e "${YELLOW}Starting Panel Installation...${NC}"

read -p "Panel Domain: " FQDN
read -p "Admin Email: " EMAIL
read -s -p "Admin Password: " PASS
echo ""

(
apt update -y
apt install -y curl tar unzip git redis-server nginx mariadb-server software-properties-common ca-certificates gnupg
) & spinner

(
add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y php8.2 php8.2-cli php8.2-common php8.2-gd php8.2-mysql php8.2-mbstring php8.2-bcmath php8.2-xml php8.2-fpm php8.2-curl php8.2-zip
) & spinner

systemctl enable --now mariadb
systemctl enable --now redis-server

DBPASS=$(openssl rand -base64 12)

mysql <<EOF
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

echo -e "${CYAN}Installing Composer...${NC}"

(
curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php
) & spinner

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

echo -e "${CYAN}Downloading Panel...${NC}"

(
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
) & spinner

cp .env.example .env

composer install --no-dev --optimize-autoloader

php artisan key:generate --force

php artisan p:environment:setup --author="$EMAIL" --url="https://$FQDN" --timezone="UTC" --cache="file" --session="database" --queue="database"

php artisan p:environment:database --host="127.0.0.1" --port="3306" --database="panel" --username="pterodactyl" --password="$DBPASS"

php artisan migrate --seed --force

php artisan p:user:make --email="$EMAIL" --username="admin" --first_name="Admin" --last_name="User" --password="$PASS" --admin=1

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

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf

systemctl restart nginx
systemctl restart php8.2-fpm

echo -e "${GREEN}Panel Installation Complete!${NC}"

}

install_wings(){

logo
echo -e "${YELLOW}Installing Wings...${NC}"

(
curl -sSL https://get.docker.com | bash
systemctl enable --now docker
) & spinner

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
systemctl start wings

echo -e "${GREEN}Wings Installed Successfully!${NC}"

}

delete_panel(){

logo
echo -e "${RED}Removing Panel...${NC}"

rm -rf /var/www/pterodactyl
rm -f /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-available/pterodactyl.conf

mysql <<EOF
DROP DATABASE IF EXISTS panel;
DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';
EOF

systemctl restart nginx

echo -e "${GREEN}Panel Deleted${NC}"

}

while true
do

logo

echo -e "${CYAN}1) Install Panel${NC}"
echo -e "${CYAN}2) Install Wings${NC}"
echo -e "${CYAN}3) Full Setup${NC}"
echo -e "${RED}4) Delete Panel${NC}"
echo -e "${YELLOW}5) Exit${NC}"

read -p "Select option: " opt

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
