#!/bin/bash

LOGFILE="/var/log/PI3SystemAnpassung.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

SCRIPT_PATH="$(realpath "$0")"

# --- Hardwareprüfung ---
MODEL=$(tr -d '\0' </proc/device-tree/model 2>/dev/null | head -n 1)

if echo "$MODEL" | grep -Eq "Raspberry Pi 3"; then
  echo "data: Raspberry Pi 3 erkannt – führe Systemanpassung durch..."
  echo ""
else
  echo "data: Keine Pi-3-Hardware erkannt (gefunden: '$MODEL')."
  echo "data: Dieses Add-on wird nur auf einem Raspberry Pi 3 oder 3+ ausgeführt."
  echo "data: Script wird nun entfernt..."
  rm -f "$SCRIPT_PATH"
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
  if ! sudo cp "$CONF_FILE" "$BACKUP_FILE"; then
    echo "data: Fehler beim Erstellen des Backups – Script wird gelöscht..."
    rm -f "$SCRIPT_PATH"
    exit 1
  fi
fi

# Einträge hinzufügen (idempotent)
if ! grep -q "metric 100" "$CONF_FILE"; then
  echo "data: Trage WLAN/LAN Priorität in dhcpcd.conf ein..."
  if ! sudo tee -a "$CONF_FILE" > /dev/null <<'EOF'

# WLAN bevorzugen, aber LAN als Fallback
interface wlan0
    metric 100

interface eth0
    metric 300
EOF
  then
    echo "data: Fehler beim Schreiben der Konfiguration – Script wird gelöscht..."
    rm -f "$SCRIPT_PATH"
    exit 1
  fi
else
  echo "data: Eintrag bereits vorhanden, überspringe Änderung."
fi

# Dienst neu starten
echo "data: Starte dhcpcd neu..."
if ! sudo systemctl restart dhcpcd || ! sudo service dhcpcd restart; then
  echo "data: Fehler beim Neustart von dhcpcd – Script wird gelöscht..."
  rm -f "$SCRIPT_PATH"
  exit 1
fi

echo "data: Fertig! WLAN wird jetzt bevorzugt, LAN dient als Fallback."
echo "data: Prüfe mit: ip route get 8.8.8.8"
echo ""

# Erfolgreich abgeschlossen → Script löschen
echo "data: Ausführung erfolgreich – Script wird nun entfernt..."
rm -f "$SCRIPT_PATH"

exit 0
