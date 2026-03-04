```bash
#!/bin/bash

# =========================
# ASHMEL PREMIUM PANEL INSTALLER
# =========================

clear

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

# Animated Logo
logo() {
echo -e "${CYAN}"
sleep 0.05
echo " █████╗ ███████╗██╗  ██╗███╗   ███╗███████╗██╗     "
sleep 0.05
echo "██╔══██╗██╔════╝██║  ██║████╗ ████║██╔════╝██║     "
sleep 0.05
echo "███████║███████╗███████║██╔████╔██║█████╗  ██║     "
sleep 0.05
echo "██╔══██║╚════██║██╔══██║██║╚██╔╝██║██╔══╝  ██║     "
sleep 0.05
echo "██║  ██║███████║██║  ██║██║ ╚═╝ ██║███████╗███████╗"
sleep 0.05
echo "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝"
echo ""
echo -e "${GREEN}      ASHMEL PTERODACTYL INSTALLER${NC}"
echo ""
}

# Loading animation
loading() {
echo -ne "${YELLOW}Loading"
for i in {1..5}; do
echo -ne "."
sleep 0.3
done
echo -e "${NC}"
}

# Install Panel
install_panel() {

loading

read -p "Panel Domain (FQDN): " DOMAIN
read -p "Admin Email: " EMAIL
read -s -p "Admin Password: " PASS
echo ""

apt update -y

apt install -y curl wget tar unzip software-properties-common

add-apt-repository ppa:ondrej/php -y
apt update

apt install -y php8.2 php8.2-cli php8.2-gd php8.2-mysql php8.2-mbstring php8.2-bcmath php8.2-xml php8.2-fpm php8.2-curl php8.2-zip

apt install -y nginx mariadb-server redis-server

curl -sL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz

chmod -R 755 storage/* bootstrap/cache/
cp .env.example .env

curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

composer install --no-dev --optimize-autoloader

php artisan key:generate --force
php artisan migrate --seed --force

php artisan p:user:make <<EOF
Ashmel
Admin
admin
$EMAIL
$PASS
yes
EOF

chown -R www-data:www-data /var/www/pterodactyl

echo ""
echo -e "${GREEN}Panel Installed Successfully${NC}"
echo "Domain: $DOMAIN"

read -p "Press enter to continue"

}

# Install Wings
install_wings() {

loading

curl -s https://pterodactyl-installer.se | bash

echo -e "${GREEN}Wings Installed${NC}"

read -p "Press enter to continue"

}

# Remove Panel
remove_panel() {

echo -e "${RED}Removing Panel...${NC}"

rm -rf /var/www/pterodactyl

apt remove nginx mariadb-server redis-server php8.2* -y

echo -e "${GREEN}Panel Removed${NC}"

read -p "Press enter to continue"

}

# Remove Wings
remove_wings() {

echo -e "${RED}Removing Wings...${NC}"

systemctl stop wings
rm -rf /etc/pterodactyl
rm -rf /usr/local/bin/wings

echo -e "${GREEN}Wings Removed${NC}"

read -p "Press enter to continue"

}

# Menu
menu() {

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}1)${NC} Install Panel"
echo -e "${GREEN}2)${NC} Install Wings"
echo -e "${GREEN}3)${NC} Install Panel + Wings"
echo -e "${RED}4)${NC} Remove Panel"
echo -e "${RED}5)${NC} Remove Wings"
echo -e "${CYAN}6)${NC} Exit"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

read -p "Select option: " choice

case $choice in
1) install_panel ;;
2) install_wings ;;
3) install_panel; install_wings ;;
4) remove_panel ;;
5) remove_wings ;;
6) exit ;;
*) echo "Invalid option" ;;
esac

}

# Main loop
while true
do
clear
logo
menu
done
```
