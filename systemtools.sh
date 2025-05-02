# Definitionen
REPO="stephanflug/digitales-Flugbuch"
TOOLS_ARCHIVE="systemtools.tar"

echo "Überprüfe und erstelle Verzeichnisse..."
mkdir -p /opt/tools/system/

# Hole die neueste Release-URL
echo "Hole die neueste Release-URL..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)
if [ -z "$LATEST_RELEASE" ]; then
    echo "Fehler: Release-Daten konnten nicht abgerufen werden."
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

# systemd-Timer einrichten für system_monitor.sh
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

echo "system_monitor.sh wurde installiert und als Timer aktiviert."
