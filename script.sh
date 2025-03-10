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

# UFW (Uncomplicated Firewall) installieren und konfigurieren
echo "Installiere und konfiguriere UFW (Firewall)..."
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 51820/udp  # WireGuard Port
sudo ufw allow 9117/tcp   # Jackett Web-UI Port
sudo ufw allow 8080/tcp   # qBittorrent Web-UI Port
sudo ufw allow 7878/tcp   # Radarr Web-UI Port
sudo ufw allow 8989/tcp   # Sonarr Web-UI Port
sudo ufw allow 8686/tcp   # Lidarr Web-UI Port
sudo ufw allow 8096/tcp   # Jellyfin Web-UI Port
sudo ufw enable

# Benutzer ohne Login für Docker erstellen
echo "Erstelle Benutzer ohne Login für Docker..."
sudo useradd -r -M -d / -s /usr/sbin/nologin dockeruser

# Docker-Group hinzufügen
echo "Füge den Benutzer zur Docker-Gruppe hinzu..."
sudo usermod -aG docker dockeruser

# Docker-Compose Setup
echo "Erstelle das Docker-Compose-Verzeichnis und die Konfigurationsdateien..."
mkdir -p ~/docker/{config/wireguard,config/jackett,config/qbittorrent,config/sonarr,config/radarr,config/lidarr,config/jellyfin}

# Docker-Compose-Konfiguration (Erstellen der docker-compose.yml Datei)
cat <<EOF > ~/docker/docker-compose.yml
version: '3.8'

services:
  wireguard:
    image: linuxserver/wireguard:latest
    container_name: wireguard
    user: "dockeruser"
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - ./config/wireguard:/config
    ports:
      - 51820:51820/udp
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
    networks:
      - vpn_network

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
sudo docker-compose up -d

# Skript abgeschlossen
echo "Installation und Konfiguration abgeschlossen. Alle Dienste laufen jetzt über das VPN unter einem Benutzer ohne Login."