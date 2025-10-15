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

# --- Hardwareprüfung ---
MODEL=$(tr -d '\0' </proc/device-tree/model 2>/dev/null | head -n 1)

if echo "$MODEL" | grep -q "Raspberry Pi 4"; then
  echo "data: Raspberry Pi 4 erkannt – führe Systemanpassung durch..."
  echo ""
else
  echo "data: Keine Pi-4-Hardware erkannt (gefunden: '$MODEL')."
  echo "data: Dieses Add-on wird nur auf einem Raspberry Pi 4 ausgeführt."
  echo ""
  exit 0
fi
# -------------------------

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
