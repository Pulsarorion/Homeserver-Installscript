#!/bin/bash

# Docker-Container stoppen
echo "Stoppe alle Docker-Container..."
sudo -u dockeruser docker stop $(sudo -u dockeruser docker ps -q)

# System-Update durchführen
echo "Führe System-Update durch..."
sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y

# Docker-Container starten
echo "Starte alle Docker-Container..."
sudo -u dockeruser docker start $(sudo -u dockeruser docker ps -q)

echo "System und Docker-Container wurden aktualisiert."
