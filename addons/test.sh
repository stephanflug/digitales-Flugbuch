#!/bin/bash

set -e

REPO="stephanflug/digitales-Flugbuch"
TOOLS_ARCHIVE="systemtools.tar"
TARGET_DIR="/opt/tools/system"

echo "Überprüfe und erstelle Verzeichnisse..."
mkdir -p "$TARGET_DIR"

# Prüfe ob jq installiert ist
if ! command -v jq >/dev/null 2>&1; then
    echo "Fehler: 'jq' ist nicht installiert. Bitte zuerst installieren."
    exit 1
fi

echo "Hole die neueste Release-URL..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)

# Prüfe ob API-Antwort leer ist
if [ -z "$LATEST_RELEASE" ]; then
    echo "Fehler: Release-Daten konnten nicht abgerufen werden."
    exit 1
fi

TOOLS_URL=$(echo "$LATEST_RELEASE" | jq -r ".assets[] | select(.name==\"$TOOLS_ARCHIVE\") | .browser_download_url")

if [ "$TOOLS_URL" != "null" ]; then
    echo "Lade $TOOLS_ARCHIVE herunter..."
    wget -O /tmp/systemtools.tar "$TOOLS_URL"
    tar -xvf /tmp/systemtools.tar -C "$TARGET_DIR"
else
    echo "Fehler: $TOOLS_ARCHIVE nicht gefunden."
    exit 1
fi

echo "Setze Berechtigungen für system_monitor.sh..."
chmod +x "$TARGET_DIR/system_monitor.sh"

echo "Richte systemd-Timer für system_monitor.sh ein..."

# systemd Service Unit schreiben
cat <<EOF > /etc/systemd/system/system_monitor.service
[Unit]
Description=System Monitor Script

[Service]
ExecStart=$TARGET_DIR/system_monitor.sh
EOF

# Timer Unit schreiben
cat <<EOF > /etc/systemd/system/system_monitor.timer
[Unit]
Description=Alle 1 Minute: System Monitor

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=system_monitor.service

[Install]
WantedBy=timers.target
EOF

# systemd neu laden und Timer aktivieren
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now system_monitor.timer

echo "system_monitor.sh wurde installiert und als Timer aktiviert."
