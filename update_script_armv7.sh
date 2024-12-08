#!/bin/bash

# Docker stopen
echo "Docker Images wird gestop"
docker stop $(docker ps -q)

# Überprüfen und Konvertieren von Windows-Zeilenenden in Unix-Zeilenenden
if file "$0" | grep -q "with CRLF line terminators"; then
    echo "Konvertiere Windows-Zeilenenden in Unix-Zeilenenden..."
    sed -i 's/\r$//' "$0"
fi

# Abhängigkeiten installieren, falls nicht vorhanden
echo "Überprüfe, ob jq installiert ist..."
if ! command -v jq &>/dev/null; then
    echo "jq nicht gefunden. Installiere jq..."
    sudo apt-get update
    sudo apt-get install -y jq
fi

# GitHub-Repository und Release-Datei
REPO="stephanflug/digitales-Flugbuch"
ASSET_NAME="data.tar"
COMPOSE_FILE="compose.yaml"

# Backup erstellen
echo "Erstelle Backup"
sudo tar -cvf /opt/digitalflugbuch/DatenBuch_backup.tar /opt/digitalflugbuch/data/DatenBuch


# Die neueste Release-Version abrufen
echo "Hole die neueste Release-URL..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)

# Die Download-URL für das Asset extrahieren
ASSET_URL=$(echo $LATEST_RELEASE | jq -r ".assets[] | select(.name==\"$ASSET_NAME\") | .browser_download_url")

if [ "$ASSET_URL" != "null" ]; then
    # Datei herunterladen
    echo "Lade die neueste Datei herunter..."
    wget -O /tmp/data.tar $ASSET_URL

    # Datei entpacken
    echo "Entpacke die Datei..."
    tar -xvf /tmp/data.tar -C /opt/digitalflugbuch/
    echo "Entpacken abgeschlossen."
else
    echo "Fehler: Die Datei $ASSET_NAME konnte nicht gefunden werden."
    exit 1
fi

# Die compose.yaml-Datei herunterladen
echo "Lade die compose.yaml-Datei herunter..."
curl -L -o /opt/digitalflugbuch/$COMPOSE_FILE https://raw.githubusercontent.com/$REPO/main/$COMPOSE_FILE

# Verzeichniss komplett löschen
sudo rm -rf /opt/digitalflugbuch/data/DatenBuch

# Backup wieder zurückspielen
sudo tar -xvf /opt/digitalflugbuch/DatenBuch_backup.tar -C /opt/digitalflugbuch/data/


# Berechtigungen setzen
echo "Setze Berechtigungen für /opt/digitalflugbuch/data..."
sudo chown -R 1000:1000 /opt/digitalflugbuch/data



# Docker-Container starten
echo "Starte Docker-Container..."
docker run -d --name digitalflugbuch --privileged \
    -p 1880:1880 -p 1883:1883 --restart unless-stopped \
    --device /dev/gpiomem --device /dev/spidev0.0 --device /dev/spidev0.1 \
    -v /opt/digitalflugbuch/data:/data \
    -v /opt/digitalflugbuch/data/mqtt:/data/mqtt \
    -v /opt/digitalflugbuch/data/nodered:/data/nodered \
    -v /opt/digitalflugbuch/data/python3:/data/python3 \
    stephanflug/iotsw:armv7V1


# Server mit Docker Compose starten
#echo "Starte den Server mit Docker Compose..."
#docker compose -f /opt/digitalflugbuch/$COMPOSE_FILE up -d

echo "Setup abgeschlossen."
