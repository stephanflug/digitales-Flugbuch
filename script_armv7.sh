#!/bin/bash

# Logfile definieren
LOGFILE="/var/log/digitalflugbuch_setup.log"

# Ausgabe und Fehlerausgabe in die Logdatei umleiten
exec > >(tee -a "$LOGFILE") 2>&1

echo "-------------------------------------------"
echo "Start des Setups: $(date)"
echo "Logdatei: $LOGFILE"
echo "-------------------------------------------"

# Überprüfen und Konvertieren von Windows-Zeilenenden in Unix-Zeilenenden
if file "$0" | grep -q "with CRLF line terminators"; then
    echo "Konvertiere Windows-Zeilenenden in Unix-Zeilenenden..."
    sed -i 's/\r$//' "$0"
fi

# Abhängigkeiten installieren, falls nicht vorhanden
echo "Überprüfe, ob jq installiert ist..."
if ! command -v jq &>/dev/null; then
    echo "jq nicht gefunden. Installiere jq..."
    sudo apt-get update && sudo apt-get install -y jq
    if [ $? -ne 0 ]; then
        echo "Fehler: jq konnte nicht installiert werden."
        exit 1
    fi
fi

# Abhängigkeiten für Shell In A Box
echo "Installiere Shell In A Box..."
if ! command -v shellinaboxd &>/dev/null; then
    sudo apt-get install -y shellinabox
    if [ $? -ne 0 ]; then
        echo "Fehler: Shell In A Box konnte nicht installiert werden."
        exit 1
    fi
fi

# Konfiguration für Shell In A Box
echo "Konfiguriere Shell In A Box..."
SHELLINABOX_CONFIG="/etc/default/shellinabox"
if [ -f "$SHELLINABOX_CONFIG" ]; then
    sudo sed -i 's/^#SHELLINABOX_PORT=.*/SHELLINABOX_PORT=4200/' "$SHELLINABOX_CONFIG"
    sudo sed -i 's/^#SHELLINABOX_ARGS=.*/SHELLINABOX_ARGS="--disable-ssl"/' "$SHELLINABOX_CONFIG"
    sudo systemctl restart shellinabox
    if [ $? -ne 0 ]; then
        echo "Fehler: Shell In A Box konnte nicht gestartet werden."
        exit 1
    fi
else
    echo "Fehler: Konfigurationsdatei für Shell In A Box nicht gefunden."
    exit 1
fi

echo "Shell In A Box wurde erfolgreich installiert und läuft unter: https://<IP-Adresse>:4200"

# GitHub-Repository und Release-Datei
REPO="stephanflug/digitales-Flugbuch"
ASSET_NAME="data.tar"
COMPOSE_FILE="compose.yaml"

# Verzeichnisse erstellen, falls nicht vorhanden
echo "Überprüfe und erstelle Verzeichnisse..."
mkdir -p /opt/digitalflugbuch/data/DatenBuch
if [ $? -ne 0 ]; then
    echo "Fehler: Das Verzeichnis /opt/digitalflugbuch/data/DatenBuch konnte nicht erstellt werden."
    exit 1
fi

# Die neueste Release-Version abrufen
echo "Hole die neueste Release-URL..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)
if [ -z "$LATEST_RELEASE" ]; then
    echo "Fehler: Release-Daten konnten nicht abgerufen werden."
    exit 1
fi

# Die Download-URL für das Asset extrahieren
ASSET_URL=$(echo $LATEST_RELEASE | jq -r ".assets[] | select(.name==\"$ASSET_NAME\") | .browser_download_url")
if [ "$ASSET_URL" != "null" ]; then
    # Datei herunterladen
    echo "Lade die neueste Datei herunter..."
    wget -O /tmp/data.tar $ASSET_URL
    if [ $? -ne 0 ]; then
        echo "Fehler: Datei konnte nicht heruntergeladen werden."
        exit 1
    fi

    # Datei entpacken
    echo "Entpacke die Datei..."
    tar -xvf /tmp/data.tar -C /opt/digitalflugbuch/
    if [ $? -ne 0 ]; then
        echo "Fehler: Datei konnte nicht entpackt werden."
        exit 1
    fi
    echo "Entpacken abgeschlossen."
else
    echo "Fehler: Die Datei $ASSET_NAME konnte nicht gefunden werden."
    exit 1
fi

# Die compose.yaml-Datei herunterladen
echo "Lade die compose.yaml-Datei herunter..."
curl -L -o /opt/digitalflugbuch/$COMPOSE_FILE https://raw.githubusercontent.com/$REPO/main/$COMPOSE_FILE
if [ $? -ne 0 ]; then
    echo "Fehler: compose.yaml konnte nicht heruntergeladen werden."
    exit 1
fi

# Berechtigungen setzen
echo "Setze Berechtigungen für /opt/digitalflugbuch/data..."
sudo chown -R 1000:1000 /opt/digitalflugbuch/data
if [ $? -ne 0 ]; then
    echo "Fehler: Berechtigungen konnten nicht gesetzt werden."
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
    stephanflug/iotsw:armv7V1

if [ $? -ne 0 ]; then
    echo "Fehler: Docker-Container konnte nicht gestartet werden."
    exit 1
fi

echo "Setup abgeschlossen. Überprüfen Sie die Logdatei unter $LOGFILE"
