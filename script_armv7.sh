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

echo "Installiere Shell In A Box..."
if ! command -v shellinaboxd &>/dev/null; then
    sudo apt-get install -y shellinabox
    if [ $? -ne 0 ]; then
        echo "Fehler: Shell In A Box konnte nicht installiert werden."
        exit 1
    fi
fi

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

REPO="stephanflug/digitales-Flugbuch"
ASSET_NAME="data.tar"
TOOLS_ARCHIVE="systemtools.tar"
COMPOSE_FILE="compose.yaml"

echo "Überprüfe und erstelle Verzeichnisse..."
mkdir -p /opt/digitalflugbuch/data/DatenBuch
mkdir -p /opt/tools/system/

echo "Hole die neueste Release-URL..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)
if [ -z "$LATEST_RELEASE" ]; then
    echo "Fehler: Release-Daten konnten nicht abgerufen werden."
    exit 1
fi

# Download und Entpacken von data.tar
ASSET_URL=$(echo $LATEST_RELEASE | jq -r ".assets[] | select(.name==\"$ASSET_NAME\") | .browser_download_url")
if [ "$ASSET_URL" != "null" ]; then
    echo "Lade $ASSET_NAME herunter..."
    wget -O /tmp/data.tar $ASSET_URL
    tar -xvf /tmp/data.tar -C /opt/digitalflugbuch/
else
    echo "Fehler: $ASSET_NAME nicht gefunden."
    exit 1
fi

# Download und Entpacken von systemtools.tar
TOOLS_URL=$(echo $LATEST_RELEASE | jq -r ".assets[] | select(.name==\"$TOOLS_ARCHIVE\") | .browser_download_url")
if [ "$TOOLS_URL" != "null" ]; then
    echo "Lade $TOOLS_ARCHIVE herunter..."
    wget -O /tmp/systemtools.tar $TOOLS_URL
    tar -xvf /tmp/systemtools.tar -C /opt/tools/system/
else
    echo "Fehler: $TOOLS_ARCHIVE nicht gefunden."
    exit 1
fi

echo "Lade die compose.yaml-Datei herunter..."
curl -L -o /opt/digitalflugbuch/$COMPOSE_FILE https://raw.githubusercontent.com/$REPO/main/$COMPOSE_FILE

echo "Setze Berechtigungen..."
sudo chown -R 1000:1000 /opt/digitalflugbuch/data

echo "Starte Docker-Container..."
docker run -d --name digitalflugbuch --privileged \
    -p 1880:1880 -p 1883:1883 --restart unless-stopped \
    --device /dev/gpiomem --device /dev/spidev0.0 --device /dev/spidev0.1 \
    -v /opt/digitalflugbuch/data:/data \
    -v /opt/digitalflugbuch/data/mqtt:/data/mqtt \
    -v /opt/digitalflugbuch/data/nodered:/data/nodered \
    -v /opt/digitalflugbuch/data/python3:/data/python3 \
    stephanflug/iotsw:armv7V1

# Systemd-Timer einrichten für system_monitor.sh
echo "Richte systemd-Timer für system_monitor.sh ein..."
cat <<EOF | sudo tee /etc/systemd/system/system_monitor.service
[Unit]
Description=System Monitor Script

[Service]
ExecStart=/opt/tools/system/system_monitor.sh
EOF

cat <<EOF | sudo tee /etc/systemd/system/system_monitor.timer
[Unit]
Description=Alle 1 Minute: System Monitor

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=system_monitor.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now system_monitor.timer

echo "Setup abgeschlossen. Überprüfen Sie die Logdatei unter $LOGFILE"
