#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Variables
SCRIPT_MAIN="/opt/scripts/server-shutdown.sh"
SCRIPT_UPDATE="/opt/scripts/update.sh"
CRON_JOB_1="30 0 * * 1-5 ${SCRIPT_MAIN}"
CRON_JOB_2="0 17 * * 3 ${SCRIPT_UPDATE}"

# Funktion, um jq zu installieren
install_jq() {
  echo "Prüfe, ob jq installiert ist..."
  if ! command -v jq &> /dev/null; then
    echo "jq ist nicht installiert. Installiere jq..."
    apt-get install -y jq
  else
    echo "jq ist bereits installiert."
  fi
}

# Function to install Docker
install_docker() {
  echo "Prüfe, ob Docker installiert ist..."
  if ! command -v docker &> /dev/null; then
    echo "Docker ist nicht installiert. Installiere Docker..."
    apt update
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt update
    apt install -y docker-ce
    systemctl enable --now docker
  else
    echo "Docker ist bereits installiert."
  fi
}

# Function to install Docker Compose
install_docker_compose() {
  echo "Prüfe, ob Docker Compose installiert ist..."
  if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose ist nicht installiert. Installiere Docker Compose..."
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  else
    echo "Docker Compose ist bereits installiert."
  fi
}

# Function to install WireGuard
install_wireguard() {
  echo "Prüfe, ob WireGuard installiert ist..."
  if ! command -v wg > /dev/null 2>&1; then
    echo "WireGuard ist nicht installiert. Installiere WireGuard..."
    apt install -y wireguard wireguard-tools
  else
    echo "WireGuard ist bereits installiert."
  fi
}

# Function to configure WireGuard
configure_wireguard() {
  echo "Erstelle Benutzer ohne Login für WireGuard..."
  useradd --system --no-create-home --shell /usr/sbin/nologin --group wireguarduser

  echo "Konfiguriere WireGuard..."
  mkdir -p /etc/wireguard
  chown wireguarduser:wireguarduser /etc/wireguard
  chmod 700 /etc/wireguard
  touch /etc/wireguard/wg0.conf
  chown wireguarduser:wireguarduser /etc/wireguard/wg0.conf
  chmod 600 /etc/wireguard/wg0.conf
  systemctl enable wg-quick@wg0.service
  sed -i 's/^ExecStart=.*$/ExecStart=\/usr\/bin\/wg-quick up wg0/' /etc/systemd/system/wg-quick@wg0.service
  sed -i 's/^User=nobody$/User=wireguarduser/' /etc/systemd/system/wg-quick@wg0.service
  sed -i 's/^Group=nogroup$/Group=wireguarduser/' /etc/systemd/system/wg-quick@wg0.service
}

# Function to install UFW
install_ufw() {
  echo "Prüfe, ob UFW installiert ist..."
  if ! command -v ufw &> /dev/null; then
    echo "UFW ist nicht installiert. Installiere UFW..."
    apt-get install -y ufw
  else
    echo "UFW ist bereits installiert."
  fi
}

# Function to configure UFW
configure_ufw() {
  echo "Konfiguriere UFW (Firewall)..."
  ufw default deny incoming
  ufw default deny outgoing
  ufw allow out on wg0  # Nur VPN für ausgehenden Verkehr
  ufw allow in on wg0
  ufw allow 51820/udp  # WireGuard Port
  ufw allow 9117/tcp   # Jackett Web-UI Port
  ufw allow 8080/tcp   # qBittorrent Web-UI Port
  ufw allow 7878/tcp   # Radarr Web-UI Port
  ufw allow 8989/tcp   # Sonarr Web-UI Port
  ufw allow 8686/tcp   # Lidarr Web-UI Port
  ufw allow 8096/tcp   # Jellyfin Web-UI Port
  ufw allow from 192.168.1.0/24 to any
  ufw enable
}

# Function to create dockeruser and get its UID and GID
create_dockeruser() {
  echo "Erstelle Benutzer ohne Login für Docker..."
  useradd -r -M -d / -s /usr/sbin/nologin dockeruser --group dockeruser
  
  DOCKERUSER_UID=$(id -u dockeruser)
  DOCKERUSER_GID=$(id -g dockeruser)

  echo "dockeruser UID: $DOCKERUSER_UID, GID: $DOCKERUSER_GID"
}

# Function to setup Docker Compose
setup_docker_compose() {
  create_dockeruser

echo "Erstelle das Docker-Compose-Verzeichnis und die Konfigurationsdateien..."
for dir in ~/docker/config/jackett ~/docker/config/qbittorrent ~/docker/config/sonarr ~/docker/config/radarr ~/docker/config/lidarr ~/docker/config/jellyfin; do
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
  else
    echo "Verzeichnis $dir existiert bereits."
  fi
done

echo "Setze Berechtigungen und Eigentümer für Docker-Compose-Verzeichnis..."
for dir in ~/docker/config/jackett ~/docker/config/qbittorrent ~/docker/config/sonarr ~/docker/config/radarr ~/docker/config/lidarr ~/docker/config/jellyfin; do
  chown -R dockeruser:dockeruser "$dir"
  chmod -R 775 "$dir"
done

echo "Erstelle die zentralen Media-Ordner..."
for dir in /media/movies /media/music /media/series /media/downloads; do
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
  else
    echo "Verzeichnis $dir existiert bereits."
  fi
done

echo "Setze Berechtigungen und Eigentümer für Media-Ordner..."
for dir in /media/movies /media/music /media/series /media/downloads; do
  chown -R dockeruser:dockeruser "$dir"
  chmod -R 775 "$dir"
done

  echo "Erstelle docker-compose.yml..."
  cat <<EOF > ~/docker/docker-compose.yml
version: '3.8'
services:
  jackett:
    image: ghcr.io/linuxserver/jackett:latest
    container_name: jackett
    user: "dockeruser"
    environment:
      - PUID=$DOCKERUSER_UID
      - PGID=$DOCKERUSER_GID
    volumes:
      - ./config/jackett:/config
      - /media/movies:/movies
      - /media/music:/music
      - /media/series:/series
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
      - PUID=$DOCKERUSER_UID
      - PGID=$DOCKERUSER_GID
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
      - PUID=$DOCKERUSER_UID
      - PGID=$DOCKERUSER_GID
    volumes:
      - ./config/sonarr:/config
      - /media/series:/series
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
      - PUID=$DOCKERUSER_UID
      - PGID=$DOCKERUSER_GID
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
      - PUID=$DOCKERUSER_UID
      - PGID=$DOCKERUSER_GID
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
      - PUID=$DOCKERUSER_UID
      - PGID=$DOCKERUSER_GID
    volumes:
      - ./config/jellyfin:/config
      - /media/movies:/movies
      - /media/music:/music
      - /media/series:/series
    ports:
      - 8096:8096
    restart: unless-stopped
    networks:
      - vpn_network

networks:
  vpn_network:
    driver: bridge
EOF
}

# Function to set up cron jobs
setup_cron_jobs() {
  echo "Richte Update und Shutdown Scripte ein..."
  mkdir -p /opt/scripts/
  curl -L -o /opt/scripts/server-shutdown.sh https://github.com/Pulsarorion/Homeserver-Installscript/blob/main/server-shutdown.sh
  curl -L -o /opt/scripts/update.sh https://github.com/Pulsarorion/Homeserver-Installscript/blob/main/update.sh
  chmod +x /opt/scripts/server-shutdown.sh && chmod +x /opt/scripts/update.sh

  (crontab -l 2>/dev/null; echo "$CRON_JOB_1") | crontab -
  (crontab -l 2>/dev/null; echo "$CRON_JOB_2") | crontab -
}

# Function to start Jackett
start_jackett() {
  echo "Starte Jackett..."
  -u dockeruser docker-compose -f ~/docker/docker-compose.yml up -d jackett
}

# Function to read API key from Jackett
read_jackett_api_key() {
  echo "Lese Jackett API-Schlüssel..."
  JACKETT_API_KEY=$(-u dockeruser docker exec jackett cat /config/Jackett/ServerConfig.json | jq -r '.ApiKey')
  if [ -z "$JACKETT_API_KEY" ]; then
    echo "Fehler: Konnte API-Schlüssel nicht lesen." >&2
    exit 1
  fi
  echo "Jackett API-Schlüssel: $JACKETT_API_KEY"
}

# Function to update docker-compose.yml with API key
update_docker_compose_with_api_key() {
  echo "Aktualisiere docker-compose.yml mit Jackett API-Schlüssel..."
  sed -i "s/YOUR_JACKETT_API_KEY/$JACKETT_API_KEY/g" ~/docker/docker-compose.yml
  if grep -q "YOUR_JACKETT_API_KEY" ~/docker/docker-compose.yml; then
    echo "Fehler: Platzhalter nicht vollständig ersetzt." >&2
    exit 1
  fi
  echo "docker-compose.yml erfolgreich aktualisiert."
  -u dockeruser docker-compose -f ~/docker/docker-compose.yml down -d jackett
}

# Function to start docker container
start_docker_container() {
  echo "Starte die Docker-Container..."
  cd ~/docker
  -u dockeruser docker-compose up -d
}

# Function to display server information
display_server_info() {
  IP_ADDRESS=$(hostname -I | awk '{print $1}')
  VPN_STATUS=$(-u wireguarduser wg show | grep 'interface' || echo "VPN nicht aktiv")
  PORTS=$(-u dockeruser docker ps --format "{{.Names}}: {{.Ports}}")

  echo "\n===== Server-Status ====="
  echo "IP-Adresse: $IP_ADDRESS"
  echo "VPN-Status: $VPN_STATUS"
  echo "Laufende Dienste & Ports:"
  echo "$PORTS"
}

# Main function
main() {
  install_jq
  install_docker
  install_docker_compose
  install_wireguard
  configure_wireguard
  install_ufw
  configure_ufw
  setup_docker_compose
  setup_cron_jobs
  start_jackett
  sleep 30  # Wartezeit für Jackett, um vollständig zu starten
  read_jackett_api_key
  update_docker_compose_with_api_key
  start_docker_container
  display_server_info
  echo "Installation und Konfiguration abgeschlossen. Alle Dienste laufen jetzt über das VPN unter einem Benutzer ohne Login."
}

main
