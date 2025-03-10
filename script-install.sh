#!/bin/bash

# Überprüfen, ob Docker und Docker-Compose installiert sind, und diese installieren, wenn nötig
echo "Prüfe, ob Docker installiert ist..."
if ! command -v docker &> /dev/null; then
    echo "Docker ist nicht installiert. Installiere Docker..."
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt update
    sudo apt install -y docker-ce
    sudo systemctl enable --now docker
else
    echo "Docker ist bereits installiert."
fi

echo "Prüfe, ob Docker Compose installiert ist..."
if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose ist nicht installiert. Installiere Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose ist bereits installiert."
fi

# Überprüfen ob WireGuard installiert ist, und diesen installieren, wenn nötig
echo "Prüfe, ob WireGuard installiert ist..."
if ! command -v wg > /dev/null 2>&1; then
    echo "WireGuard ist nicht installiert. Installiere WireGuard..."
    sudo apt update
    sudo apt install -y wireguard wireguard-tools
else
    echo "WireGuard ist bereits installiert."

# Einen neuen Benutzer ohne Login für WireGuard erstellen
echo "Erstelle Benutzer ohne Login für WireGuard..."
sudo useradd --system --no-create-home --shell /usr/sbin/nologin --group wireguarduser

# WireGuard konfigurieren
# Ordner erstellen
sudo mkdir -p /etc/wireguard
sudo chown wireguarduser:wireguarduser /etc/wireguard
sudo chmod 700 /etc/wireguard
# Konfigurationsdatei erstellen
sudo touch /etc/wireguard/wg0.conf
sudo chown wireguarduser:wireguarduser /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
# Auto-Start einrichten
sudo systemctl enable wg-quick@wg0.service
# Ausführung unter wireguarduser setzen
sudo sed -i 's/^ExecStart=.*$/ExecStart=\/usr\/bin\/wg-quick up wg0/' /etc/systemd/system/wg-quick@wg0.service
sudo sed -i 's/^User=nobody$/User=wireguarduser/' /etc/systemd/system/wg-quick@wg0.service
sudo sed -i 's/^Group=nogroup$/Group=wireguarduser/' /etc/systemd/system/wg-quick@wg0.service

# UFW (Uncomplicated Firewall) installieren und konfigurieren
echo "Installiere und konfiguriere UFW (Firewall)..."
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default deny outgoing
sudo ufw allow out on wg0  # Nur VPN für ausgehenden Verkehr
sudo ufw allow in on wg0
sudo ufw allow 51820/udp  # WireGuard Port
sudo ufw allow 9117/tcp   # Jackett Web-UI Port
sudo ufw allow 8080/tcp   # qBittorrent Web-UI Port
sudo ufw allow 7878/tcp   # Radarr Web-UI Port
sudo ufw allow 8989/tcp   # Sonarr Web-UI Port
sudo ufw allow 8686/tcp   # Lidarr Web-UI Port
sudo ufw allow 8096/tcp   # Jellyfin Web-UI Port
sudo ufw allow from 192.168.1.0/24 to any
sudo ufw enable

# Benutzer ohne Login für Docker erstellen
echo "Erstelle Benutzer ohne Login für Docker..."
sudo useradd -r -M -d / -s /usr/sbin/nologin dockeruser --group dockeruser

# Docker-Compose Setup
echo "Erstelle das Docker-Compose-Verzeichnis und die Konfigurationsdateien..."
mkdir -p ~/docker/{config/jackett,config/qbittorrent,config/sonarr,config/radarr,config/lidarr,config/jellyfin}

# Docker-Compose-Konfiguration (Erstellen der docker-compose.yml Datei)
cat <<EOF > ~/docker/docker-compose.yml
version: '3.8'

services:
  jackett:
    image: ghcr.io/linuxserver/jackett:latest
    container_name: jackett
    user: "dockeruser"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./config/jackett:/config
      - /media/movies:/movies
      - /media/music:/music
    ports:
      - 9117:9117
    restart: unless-stopped
    networks:
      - vpn_network

  qbittorrent:
    image: linuxserver/qbittorrent:latest
    container_name: qbittorrent
    user: "dockeruser"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /media/downloads:/downloads
      - ./config/qbittorrent:/config
    ports:
      - 8080:8080
    restart: unless-stopped
    network_mode: service:wireguard
    depends_on:
      - wireguard
    environment:
      - WEBUI_PORT=8080
      - UPLOAD_SPEED=0  # Verhindert das Hochladen
    networks:
      - vpn_network

  sonarr:
    image: ghcr.io/linuxserver/sonarr:latest
    container_name: sonarr
    user: "dockeruser"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./config/sonarr:/config
      - /media/movies:/movies
    ports:
      - 8989:8989
    restart: unless-stopped
    depends_on:
      - jackett
      - qbittorrent
    environment:
      - SONARR_DOWNLOAD_CLIENT=qBittorrent
      - SONARR_DOWNLOAD_CLIENT_HOST=qbittorrent
      - SONARR_DOWNLOAD_CLIENT_PORT=8080
      - SONARR_DOWNLOAD_CLIENT_USERNAME=admin
      - SONARR_DOWNLOAD_CLIENT_PASSWORD=adminadmin
      - SONARR_INDEXER=Jackett
      - SONARR_INDEXER_HOST=jackett
      - SONARR_INDEXER_PORT=9117
      - SONARR_INDEXER_APIKEY=YOUR_JACKETT_API_KEY
    networks:
      - vpn_network

  radarr:
    image: ghcr.io/radarr/radarr:latest
    container_name: radarr
    user: "dockeruser"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./config/radarr:/config
      - /media/movies:/movies
    ports:
      - 7878:7878
    restart: unless-stopped
    depends_on:
      - jackett
      - qbittorrent
    environment:
      - RADARR_DOWNLOAD_CLIENT=qBittorrent
      - RADARR_DOWNLOAD_CLIENT_HOST=qbittorrent
      - RADARR_DOWNLOAD_CLIENT_PORT=8080
      - RADARR_DOWNLOAD_CLIENT_USERNAME=admin
      - RADARR_DOWNLOAD_CLIENT_PASSWORD=adminadmin
      - RADARR_INDEXER=Jackett
      - RADARR_INDEXER_HOST=jackett
      - RADARR_INDEXER_PORT=9117
      - RADARR_INDEXER_APIKEY=YOUR_JACKETT_API_KEY
    networks:
      - vpn_network

  lidarr:
    image: ghcr.io/lidarr/lidarr:latest
    container_name: lidarr
    user: "dockeruser"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./config/lidarr:/config
      - /media/music:/music
    ports:
      - 8686:8686
    restart: unless-stopped
    depends_on:
      - jackett
      - qbittorrent
    environment:
      - LIDARR_DOWNLOAD_CLIENT=qBittorrent
      - LIDARR_DOWNLOAD_CLIENT_HOST=qbittorrent
      - LIDARR_DOWNLOAD_CLIENT_PORT=8080
      - LIDARR_DOWNLOAD_CLIENT_USERNAME=admin
      - LIDARR_DOWNLOAD_CLIENT_PASSWORD=adminadmin
      - LIDARR_INDEXER=Jackett
      - LIDARR_INDEXER_HOST=jackett
      - LIDARR_INDEXER_PORT=9117
      - LIDARR_INDEXER_APIKEY=YOUR_JACKETT_API_KEY
    networks:
      - vpn_network

  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    user: "dockeruser"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./config/jellyfin:/config
      - /media/movies:/movies
      - /media/music:/music
    ports:
      - 8096:8096
    restart: unless-stopped
    networks:
      - vpn_network

networks:
  vpn_network:
    driver: bridge
EOF

# Docker-Compose Container starten
echo "Starte die Docker-Container..."
cd ~/docker
sudo -u dockeruser docker-compose up -d

# Skript abgeschlossen
echo "Installation und Konfiguration abgeschlossen. Alle Dienste laufen jetzt über das VPN unter einem Benutzer ohne Login."

# Update und Shutdown Sctipte einrichten
sudo mkdir -p /opt/scripts/
sudo curl -L -o /opt/scripts/server-shutdown.sh https://github.com/Pulsarorion/Homeserver-Installscript/blob/main/server-shutdown.sh
sudo curl -L -o /opt/scripts/update.sh https://github.com/Pulsarorion/Homeserver-Installscript/blob/main/update.sh
sudo chmod +x /opt/scripts/server-shutdown.sh && sudo chmod +x /opt/scripts/update.sh

SCRIPT_MAIN="/opt/scripts/server-shutdown.sh" # Pfad zu Server Shutdown Script
SCRIPT_UPDATE="/opt/scripts/update.sh" # Pfad zu Server Update Script

CRON_JOB_1="30 0 * * 1-5 $SCRIPT_MAIN"
CRON_JOB_2="0 17 * * 3 $SCRIPT_UPDATE"

(crontab -l 2>/dev/null; echo "$CRON_JOB_1") | crontab -
(crontab -l 2>/dev/null; echo "$CRON_JOB_2") | crontab -

# Server-Informationen ausgeben
IP_ADDRESS=$(hostname -I | awk '{print $1}')
VPN_STATUS=$(sudo wg show | grep 'interface' || echo "VPN nicht aktiv")
PORTS=$(sudo docker ps --format "{{.Names}}: {{.Ports}}")

echo "\n===== Server-Status ====="
echo "IP-Adresse: $IP_ADDRESS"
echo "VPN-Status: $VPN_STATUS"
echo "Laufende Dienste & Ports:"
echo "$PORTS"
