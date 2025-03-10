#!/bin/bash

# Docker-Container stoppen
echo "Stoppe alle Docker-Container..."
sudo -u dockeruser docker stop $(sudo -u dockeruser docker ps -q)
sudo -u wireguarduser systemctl stop wg-quick@wg0.service

# Temporär eingehende und ausgehende Verbindungen erlauben
sudo ufw default allow incoming
sudo ufw default allow outgoing
sudo ufw reload

# System-Update durchführen
echo "Führe System-Update durch..."
sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y

# Ursprüngliche Firewall-Regeln wiederherstellen
sudo ufw default deny incoming
sudo ufw default deny outgoing
sudo ufw allow out on wg0  # Nur VPN für ausgehenden Verkehr
sudo ufw allow in on wg0   # VPN für eingehenden Verkehr
sudo ufw reload

# Docker-Container starten
echo "Starte VPN und alle Docker-Container..."
sudo -u wireguarduser systemctl start wg-quick@wg0.service
sleep 30
sudo -u dockeruser docker start $(sudo -u dockeruser docker ps -q)

echo "System und Docker-Container wurden aktualisiert."
