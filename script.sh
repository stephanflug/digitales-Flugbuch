#!/bin/bash

# Verzeichnisse erstellen und Berechtigungen setzen
echo "Erstelle Verzeichnisstruktur..."
mkdir -p /opt/digitalflugbuch/data

# Berechtigungen setzen
echo "Setze Berechtigungen für /opt/digitalflugbuch/data..."
sudo chown -R 1000:1000 /opt/digitalflugbuch/data

# Laden und Entpacken des Ordners data.tar
echo "Lade und entpacke data.tar..."
if wget -O /tmp/data.tar https://raw.githubusercontent.com/stephanflug/digitales-Flugbuch/main/data.tar; then
    tar -xvf /tmp/data.tar -C /opt/digitalflugbuch/data
    echo "Entpacken abgeschlossen."
else
    echo "Fehler beim Herunterladen von data.tar."
    exit 1
fi

# Docker-Container starten
echo "Starte Docker-Container..."
docker run -d --name digitalflugbuch --privileged \
    -p 1880:1880 -p 1883:1883 --restart unless-stopped \
    --device /dev/gpiomem --device /dev/spidev0.0 --device /dev/spidev0.1 \
    -v /opt/digitalflugbuch/data:/data \
    -v /opt/digitalflugbuch/data/mqtt:/data/mqtt \
    -v /opt/digitalflugbuch/data/nodered:/data/nodered \
    -v /opt/digitalflugbuch/data/python3:/data/python3 \
    stephanflug/iotsw:V1

# Server mit Docker Compose starten
echo "Starte den Server mit Docker Compose..."
docker compose up -d

echo "Setup abgeschlossen."
