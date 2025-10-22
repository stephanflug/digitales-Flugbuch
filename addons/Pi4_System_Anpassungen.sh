#!/bin/bash

LOGFILE="/var/log/PI4SystemAnpassung.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

set -x

SCRIPT_PATH="$(realpath "$0")"

# --- Hardwareprüfung ---
MODEL=$(tr -d '\0' </proc/device-tree/model 2>/dev/null | head -n 1)

if ! echo "$MODEL" | grep -q "Raspberry Pi 4"; then
  echo "data: Keine Pi-4-Hardware erkannt (gefunden: '$MODEL')."
  echo "data: Dieses Add-on wird nur auf einem Raspberry Pi 4 ausgeführt."
  echo "data: Script wird nun entfernt..."
  rm -f "$SCRIPT_PATH"
  exit 1
fi
# -------------------------

echo "data: Raspberry Pi 4 erkannt – führe Systemanpassung durch..."
echo "data: Starte Einrichtung der Netzwerkpriorität (LAN bevorzugt)..."
echo ""

CONF_FILE="/etc/dhcpcd.conf"
BACKUP_FILE="/etc/dhcpcd.conf.bak_$(date +%Y%m%d-%H%M%S)"

# Datei anlegen, falls sie fehlt
if [ ! -f "$CONF_FILE" ]; then
  echo "data: $CONF_FILE existiert nicht – lege Datei an."
  echo "# dhcpcd.conf (erstellt von Skript)" | sudo tee "$CONF_FILE" >/dev/null
fi

# Backup erstellen
echo "data: Erstelle Backup von $CONF_FILE -> $BACKUP_FILE"
if ! sudo cp "$CONF_FILE" "$BACKUP_FILE"; then
  echo "data: Fehler beim Erstellen des Backups – Script wird gelöscht..."
  rm -f "$SCRIPT_PATH"
  exit 1
fi

# Vorherigen Auto-Block entfernen (idempotent)
sudo sed -i '/^# BEGIN auto-metric$/,/^# END auto-metric$/d' "$CONF_FILE"

# Einträge hinzufügen
echo "data: Trage LAN/WLAN-Priorität in dhcpcd.conf ein (LAN zuerst)..."
if ! sudo tee -a "$CONF_FILE" > /dev/null <<'EOF'

# BEGIN auto-metric
# LAN bevorzugen, WLAN als Fallback (automatisch hinzugefügt)
interface eth0
    metric 100

interface wlan0
    metric 300
# END auto-metric
EOF
then
  echo "data: Fehler beim Schreiben der Konfiguration – Script wird gelöscht..."
  rm -f "$SCRIPT_PATH"
  exit 1
fi

# Dienst neu starten
echo "data: Starte dhcpcd neu..."
if ! sudo systemctl restart dhcpcd 2>/dev/null; then
  if ! sudo service dhcpcd restart; then
    echo "data: Fehler beim Neustart von dhcpcd – Script wird gelöscht..."
    rm -f "$SCRIPT_PATH"
    exit 1
  fi
fi

echo "data: Fertig! LAN wird jetzt bevorzugt, WLAN dient als Fallback."
echo "data: Prüfe z.B. mit: ip route get 8.8.8.8"
exit 0
