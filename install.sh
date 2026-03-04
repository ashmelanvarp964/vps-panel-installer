#!/bin/bash

clear

RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
NC='\033[0m'

while true
do

clear

echo -e "${GREEN}"
echo "ASHMEL VPS PANEL INSTALLER"
echo -e "${NC}"

echo -e "${BLUE}1) Install Panel${NC}"
echo -e "${BLUE}2) Install Wings${NC}"
echo -e "${RED}3) Exit${NC}"

read -p "Select option: " choice

case $choice in

1)
echo "Installing panel..."
sleep 2
;;

2)
echo "Installing wings..."
sleep 2
;;

3)
exit
;;

*)
echo "Invalid option"
sleep 2
;;

esac

done
