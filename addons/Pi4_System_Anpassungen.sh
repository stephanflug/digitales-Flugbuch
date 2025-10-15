#!/bin/bash

LOGFILE="/var/log/PI4SystemAnpassung.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

echo "data: Starte Einrichtung der Netzwerkpriorität (WLAN bevorzugt)..."
echo ""

CONF_FILE="/etc/dhcpcd.conf"
BACKUP_FILE="/etc/dhcpcd.conf.bak_$(date +%Y%m%d-%H%M%S)"

# Backup erstellen
if [ -f "$CONF_FILE" ]; then
  echo "data: Erstelle Backup von $CONF_FILE -> $BACKUP_FILE"
  sudo cp "$CONF_FILE" "$BACKUP_FILE"
fi

# Einträge hinzufügen (idempotent)
if ! grep -q "metric 100" "$CONF_FILE"; then
  echo "data: Trage WLAN/LAN Priorität in dhcpcd.conf ein..."
  sudo tee -a "$CONF_FILE" > /dev/null <<'EOF'

# WLAN bevorzugen, aber LAN als Fallback
interface wlan0
    metric 100

interface eth0
    metric 300
EOF
else
  echo "data: Eintrag bereits vorhanden, überspringe Änderung."
fi

# Dienst neu starten
echo "data: Starte dhcpcd neu..."
sudo systemctl restart dhcpcd || sudo service dhcpcd restart

echo "data: Fertig! WLAN wird jetzt bevorzugt, LAN dient als Fallback."
echo "data: Prüfe mit: ip route get 8.8.8.8"
echo ""
