#!/bin/bash

# Anwendungen (Docker-Container) ordnungsgemäß stoppen
stop_applications() {
    echo "Stoppe alle laufenden Docker-Container..."
    sudo -u dockeruser docker stop $(sudo -u dockeruser docker ps -q)
    sudo -u wireguarduser systemctl stop wg-quick@wg0.service
}

# Server herunterfahren
shutdown_server() {
    echo "Server wird heruntergefahren..."
    sudo shutdown -h now
}

# Funktionen ausführen
stop_applications
shutdown_server
