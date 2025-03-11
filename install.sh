#!/bin/bash

# Check if the Script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Check if System is uptodate
apt update && apt upgrade -y

# Function to Create wireguarduser
create_wireguarduser() {
  echo "Creating User with nologin for Wireguard"
  groupadd wireguarduser
  useradd -r -M -d / -s /usr/sbin/nologin wireguarduser -g wireguarduser
}

# Function to Install and Setup Wireguard
install_wireguard() {
  echo "Checking if WireGuard is installed"
  if ! command -v wg > /dev/null 2>&1; then
    echo "WireGuard is not installed. Installing WireGuard now"
    apt install -y wireguard wireguard-tools
  else
    echo "WireGuard is already installed."
  fi
}

    #Setup for Wireguard

# Function to Install and Setup UFW
install_ufw() {
  echo "Checking if UFW is installed"
  if ! command -v ufw &> /dev/null; then
    echo "UFW is not installed. Installing UFW now"
    apt-get install -y ufw
  else
    echo "UFW is already installed."
  fi
}
configure_ufw() {
  echo "Settingup UFW (Firewall) now"
  ufw default deny incoming
  ufw default deny outgoing
  ufw allow out on wg0  # VPN
  ufw allow in on wg0 # VPN
  ufw allow 51820/udp  # WireGuard Port
  ufw allow 8080/tcp   # qBittorrent Web-UI Port
  ufw allow 6881/tcp   # qBittorrent Download
  ufw allow 6881/udp   # qBittorrent Download
  ufw allow 7878/tcp   # Radarr Web-UI Port
  ufw allow 8989/tcp   # Sonarr Web-UI Port
  ufw allow 8686/tcp   # Lidarr Web-UI Port
  ufw allow 8096/tcp   # Jellyfin Web-UI Port
  ufw allow from 192.168.1.0/24 to any
  ufw enable
}

# Function to Install Docker and Dockercompose
apt-get install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Check if Docker is proparlly installed
docker run hello-world
if [ $? -eq 0 ]; then
    echo "Docker sucessful installed."
    docker rmi hello-world
else
    echo "There is a Problem with Docker pls Check Docker installation manually."
    exit 1
fi

# Function to Create media Folders
create_media_folders() {
  echo "Creating Media folders"
  for dir in ~/media/movies ~/media/music ~/media/series ~/media/config/radarr ~/media/config/lidarr ~/media/config/sonarr ~/media/config/jellyfin ~/media/config/qbittorrent ~/media/downloads; do
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    chown -R dockeruser:dockeruser "$dir"
    chmod -R 775 "$dir"
  else
    echo "Folder $dir already existing."
    chown -R dockeruser:dockeruser "$dir"
    chmod -R 775 "$dir"
  fi
  done

# Function to Create dockeruser and get its UID and GID
create_dockeruser() {
  echo "Creating User with nologin for Docker"
  groupadd dockeruser
  useradd -r -M -d / -s /usr/sbin/nologin dockeruser -g dockeruser
  
  DOCKERUSER_UID=$(id -u dockeruser)
  DOCKERUSER_GID=$(id -g dockeruser)

  echo "dockeruser UID: $DOCKERUSER_UID, GID: $DOCKERUSER_GID"
}

# Function to Create docker-compose.yml
cat << EOF > /etc/docker/docker-compose.yml
 services:
   prowlarr:
     container_name: prowlarr
     imgae: lscr.io/linuxserver/prowlarr:latest
     environment:
       - PUID=$DOCKERUSER_UID
       - PGID=$DOCKERUSER_GID
       - TZ=Etc/UTC
     volumes:
       - /media/config/prowlarr:/config
     ports:
       - 9696:9696
     restart: unless-stopped
   lidarr:
     container_name: lidarr
     imgae: lscr.io/linuxserver/lidarr:latest
     environment:
       - PUID=$DOCKERUSER_UID
       - PGID=$DOCKERUSER_GID
       - TZ=Etc/UTC
     volumes:
       - /media/config/prowlarr:/config
       - /media/music:/music
     ports:
       - 8686:8686
     restart: unless-stopped
   radarr:
     container_name: radarr
     imgae: lscr.io/linuxserver/radarr:latest
     environment:
       - PUID=$DOCKERUSER_UID
       - PGID=$DOCKERUSER_GID
       - TZ=Etc/UTC
     volumes:
       - /media/config/radarr:/config
       - /media/movies:/movies
     ports:
       - 7878:7878
     restart: unless-stopped
   sonarr:
     container_name: sonarr
     imgae: lscr.io/linuxserver/sonarr:latest
     environment:
       - PUID=$DOCKERUSER_UID
       - PGID=$DOCKERUSER_GID
       - TZ=Etc/UTC
     volumes:
       - /media/config/sonarr:/config
     ports:
       - 8989:8989
     restart: unless-stopped
   jellyfin:
     container_name: jellyfin
     imgae: ghcr.io/jellyfin/jellyfin:latest
     environment:
       - PUID=$DOCKERUSER_UID
       - PGID=$DOCKERUSER_GID
       - TZ=Etc/UTC
     volumes:
       - /media/config/jellyfin:/config
       - /media/music:/music
       - /media/movies:/movies
       - /media/series:/series
     ports:
       - 8096:8096
     restart: unless-stopped
   qbittorrent:
     container_name: qbittorrent
     image: lscr.io/linuxserver/qbittorrent:latest
     environment:
       - PUID=$DOCKERUSER_UID
       - PGID=$DOCKERUSER_GID
       - TZ=Etc/UTC
       - WEBUI_PORT=8080
       - TORRENTING_PORT=6881
     volumes:
       - /media/config/qbittorrent:/config
       - /media/downloads:/downloads
     ports:
       - 8080:8080
       - 6881:6881
       - 6881:6881/udp
     restart: unless-stopped
EOF

# Function to Start and Stop all Containers
docker compose -f /etc/docker/docker-compose.yml up -d
sleep 30
docker compose -f /etx/docker/docker-compose.yml down

# Function to grab API from Lidarr, Radarr and Sonarr


# Function to preset and Link Prowlarr with API

