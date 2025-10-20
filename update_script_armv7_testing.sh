#!/bin/bash

LOGFILE1="/var/log/digitalflugbuch_update_testing.log"
LOGFILE2="/var/www/html/log/digitalflugbuch_update.log"

# Log-Verzeichnisse anlegen
mkdir -p "$(dirname "$LOGFILE2")"
touch "$LOGFILE2"
chown www-data:www-data "$LOGFILE2"
chmod 644 "$LOGFILE2"

# Log-Ausgabe doppelt
exec > >(tee -a "$LOGFILE1" | tee -a "$LOGFILE2") 2>&1

echo "-------------------------------------------"
echo "Start des TESTING-Updates: $(date)"
echo "Logdateien: $LOGFILE1 & $LOGFILE2"
echo "-------------------------------------------"

# Docker stoppen
echo "Docker-Container werden gestoppt..."
RUNNING_CONTAINERS=$(docker ps -q)
if [ -n "$RUNNING_CONTAINERS" ]; then
    docker stop $RUNNING_CONTAINERS || {
        echo "Fehler: Docker-Container konnten nicht gestoppt werden."
        exit 1
    }
else
    echo "Keine laufenden Docker-Container gefunden."
fi

# CRLF korrigieren
if file "$0" | grep -q "with CRLF line terminators"; then
    echo "Konvertiere Windows-Zeilenenden in Unix-Zeilenenden..."
    sed -i 's/\r$//' "$0"
fi

# jq prüfen
if ! command -v jq &>/dev/null; then
    echo "jq nicht gefunden. Installiere..."
    sudo apt-get update && sudo apt-get install -y jq || {
        echo "Fehler: jq konnte nicht installiert werden."
        exit 1
    }
fi

# Shell In A Box prüfen/installieren
if ! command -v shellinaboxd &>/dev/null; then
    echo "Shell In A Box wird installiert..."
    sudo apt-get update && sudo apt-get install -y shellinabox
    sudo systemctl enable shellinabox
    sudo systemctl start shellinabox
else
    echo "Shell In A Box ist bereits installiert."
    sudo systemctl enable shellinabox
    sudo systemctl start shellinabox
fi

# --- GitHub-Konfiguration ---
REPO="stephanflug/digitales-Flugbuch"
ASSET_NAME="data.tar"
TOOLS_ARCHIVE="systemtools.tar"
COMPOSE_FILE="compose.yaml"
HOST_ARCHIVE="host.tar"

# Backup erstellen
echo "Erstelle Backup der Daten..."
sudo tar -cvf /opt/digitalflugbuch/DatenBuch_backup.tar /opt/digitalflugbuch/data/DatenBuch || {
    echo "Fehler: Backup fehlgeschlagen."
    exit 1
}

# === WICHTIG: nur Pre-Releases laden ===
echo "Suche neuestes Pre-Release (Testing)..."
RELEASES_JSON="$(curl -s https://api.github.com/repos/$REPO/releases)"
SELECTED_RELEASE="$(echo "$RELEASES_JSON" | jq -c 'map(select(.draft==false and .prerelease==true)) | sort_by(.created_at) | last')"

if [ -z "$SELECTED_RELEASE" ] || [ "$SELECTED_RELEASE" = "null" ]; then
    echo "Keine gültige Test-Release gefunden."
    exit 1
fi

TAG_NAME="$(echo "$SELECTED_RELEASE" | jq -r '.tag_name')"
PUBLISHED_AT="$(echo "$SELECTED_RELEASE" | jq -r '.published_at')"
echo "Gefundene TEST-Release: $TAG_NAME ($PUBLISHED_AT)"

# Helper: Asset-Link extrahieren
asset_url() {
    echo "$SELECTED_RELEASE" | jq -r --arg NAME "$1" '.assets[] | select(.name==$NAME) | .browser_download_url'
}

# === data.tar ===
ASSET_URL="$(asset_url "$ASSET_NAME")"
if [ -n "$ASSET_URL" ] && [ "$ASSET_URL" != "null" ]; then
    echo "Lade $ASSET_NAME herunter..."
    wget -O /tmp/data.tar "$ASSET_URL" || exit 1
    echo "Entpacke $ASSET_NAME..."
    tar -xvf /tmp/data.tar -C /opt/digitalflugbuch/ || exit 1
else
    echo "Fehler: $ASSET_NAME nicht gefunden."
    exit 1
fi

# === systemtools.tar ===
TOOLS_URL="$(asset_url "$TOOLS_ARCHIVE")"
if [ -n "$TOOLS_URL" ] && [ "$TOOLS_URL" != "null" ]; then
    echo "Lade $TOOLS_ARCHIVE herunter..."
    wget -O /tmp/systemtools.tar "$TOOLS_URL" || exit 1
    echo "Entpacke $TOOLS_ARCHIVE..."
    sudo mkdir -p /opt/tools/system/
    sudo tar -xvf /tmp/systemtools.tar -C /opt/tools/system/ || exit 1
    sudo chmod -R 777 /opt/tools/system/
else
    echo "Hinweis: $TOOLS_ARCHIVE wurde im Release nicht gefunden."
fi

# === host.tar ===
HOST_URL="$(asset_url "$HOST_ARCHIVE")"
if [ -n "$HOST_URL" ] && [ "$HOST_URL" != "null" ]; then
    echo "Lade $HOST_ARCHIVE herunter..."
    wget -O /tmp/host.tar "$HOST_URL" && \
    mkdir -p /tmp/host_temp && \
    tar -xvf /tmp/host.tar -C /tmp/host_temp && \
    sudo cp -rf /tmp/host_temp/html/* /var/www/html/ 2>/dev/null || true
    sudo cp -rf /tmp/host_temp/cgi-bin/* /usr/lib/cgi-bin/ 2>/dev/null || true
    sudo chmod -R 0777 /var/www/html/
    sudo chmod -R 0777 /usr/lib/cgi-bin/
else
    echo "Hinweis: $HOST_ARCHIVE wurde im Release nicht gefunden."
fi

# compose.yaml laden
curl -L -o /opt/digitalflugbuch/$COMPOSE_FILE https://raw.githubusercontent.com/$REPO/main/$COMPOSE_FILE || {
    echo "Fehler: compose.yaml konnte nicht geladen werden."
    exit 1
}

# Datenverzeichnis erneuern
sudo rm -rf /opt/digitalflugbuch/data/DatenBuch
sudo mkdir -p /opt/digitalflugbuch/data/DatenBuch
sudo tar -xvf /opt/digitalflugbuch/DatenBuch_backup.tar -C /
sudo chown -R 1000:1000 /opt/digitalflugbuch/data

# systemd neu laden
sudo systemctl daemon-reload
sudo systemctl restart system_monitor.timer

# Docker wieder starten
docker start $(docker ps -a -q)

echo "-------------------------------------------"
echo "TESTING-Update abgeschlossen: $(date)"
echo "Release: $TAG_NAME ($PUBLISHED_AT)"
echo "Shell In A Box: http://<IP>:4200"
echo "Log: $LOGFILE1"
echo "-------------------------------------------"
