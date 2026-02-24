#!/bin/bash
set -eEuo pipefail

LOGFILE="/var/log/nodered_addon_setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "-------------------------------------------"
echo "Start Node-RED Addon Setup: $(date)"
echo "Logdatei: $LOGFILE"
echo "-------------------------------------------"

# CRLF -> LF (wie bei deinem Setup, aber nur wenn 'file' existiert)
if command -v file >/dev/null 2>&1; then
  if file "$0" | grep -q "with CRLF line terminators"; then
    echo "Konvertiere Windows-Zeilenenden (CRLF) in Unix (LF)..."
    sed -i 's/\r$//' "$0"
  fi
fi

USERNAME="flugbuch"
BASE_DIR="/opt/addons/NodeRed"
DATA_DIR="$BASE_DIR/data"
CONTAINER_NAME="nodered_addon"
SERVICE_FILE="/etc/systemd/system/nodered-addon.service"
PORT_HOST="1881"
PORT_CONTAINER="1880"

# Script-Pfad für Selbstlöschung (nur dieses Script)
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

SUCCESS=0

cleanup_on_failure() {
  set +e
  echo "Cleanup (bei Fehler)..."

  # Service entfernen, falls angelegt
  if [ -f "$SERVICE_FILE" ]; then
    sudo systemctl disable --now nodered-addon.service >/dev/null 2>&1 || true
    sudo rm -f "$SERVICE_FILE" >/dev/null 2>&1 || true
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  # Container stoppen/entfernen, falls erstellt
  if sudo docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    sudo docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
}

self_delete() {
  set +e
  rm -f "$SCRIPT_PATH" >/dev/null 2>&1 || sudo rm -f "$SCRIPT_PATH" >/dev/null 2>&1 || true
}

on_exit() {
  ec=$?
  if [ "$SUCCESS" -eq 1 ] && [ "$ec" -eq 0 ]; then
    echo "Setup erfolgreich abgeschlossen."
    return
  fi

  echo "-----------------------------------------------------------------"
  echo "Installation NICHT erfolgreich (Exit-Code: $ec)."
  echo "Script wird gelöscht: $SCRIPT_PATH"
  echo "-----------------------------------------------------------------"

  cleanup_on_failure
  self_delete
}
trap on_exit EXIT

# === 0. Nur Raspberry Pi 3–5 erlauben ===
MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
echo "Hardware: ${MODEL:-unbekannt}"
if ! echo "$MODEL" | grep -Eq 'Raspberry Pi (3|4|5)'; then
  echo "FEHLER: Nicht unterstützte Hardware: $MODEL"
  echo "Dieses Setup ist nur für Raspberry Pi 3, 4 oder 5 erlaubt."
  exit 1
fi

# === 1. Docker prüfen ===
if ! command -v docker >/dev/null 2>&1; then
  echo "FEHLER: docker ist nicht installiert oder nicht im PATH."
  exit 1
fi
if ! sudo systemctl is-active --quiet docker; then
  echo "FEHLER: Docker Service läuft nicht. Starte mit: sudo systemctl start docker"
  exit 1
fi

# === 2. Port prüfen (kein Konflikt zu deinem 1880 Setup) ===
if sudo ss -ltn | awk '{print $4}' | grep -qE "(:|\.)${PORT_HOST}$"; then
  echo "FEHLER: Port ${PORT_HOST} ist bereits belegt."
  exit 1
fi

# === 3. Verzeichnisse anlegen (unter /opt/addons/NodeRed) ===
sudo mkdir -p "$DATA_DIR"

# Rechte: Node-RED Image nutzt i.d.R. UID 1000
sudo chown -R 1000:1000 "$BASE_DIR" || true
if id "$USERNAME" >/dev/null 2>&1; then
  sudo chown -R "$USERNAME:$USERNAME" "$BASE_DIR" || true
fi

# === 4. USB/Serial Devices dynamisch erkennen (falls schon eingesteckt) ===
DEVICE_ARGS=()
for d in /dev/ttyUSB* /dev/ttyACM*; do
  if [ -e "$d" ]; then
    DEVICE_ARGS+=( "--device" "$d:$d" )
  fi
done

# Optional: "echtes" USB (libusb/HID) – auf Pi vorhanden
# (mit --privileged meist nicht nötig, schadet aber i.d.R. nicht)
USB_BUS_MOUNT_ARGS=()
if [ -d /dev/bus/usb ]; then
  USB_BUS_MOUNT_ARGS+=( "-v" "/dev/bus/usb:/dev/bus/usb" )
fi

# dialout GID (für /dev/ttyUSB*, /dev/ttyACM*)
DIALOUT_GID="$(getent group dialout | awk -F: '{print $3}')"
[ -z "$DIALOUT_GID" ] && DIALOUT_GID="20"

# === 5. Bestehenden Addon-Container (nur unserer) ersetzen ===
if sudo docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "Vorhandener Container '$CONTAINER_NAME' wird ersetzt..."
  sudo docker rm -f "$CONTAINER_NAME"
fi

# === 6. Image holen ===
echo "Pull Node-RED Image..."
sudo docker pull nodered/node-red:latest

# === 7. Container starten (USB Zugriff über --privileged) ===
# Hinweis: --privileged = verlässlichster USB Zugriff ohne ständiges Nachpflegen der Devices
echo "Starte Container '$CONTAINER_NAME' auf Port ${PORT_HOST}..."
sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --privileged \
  --group-add "$DIALOUT_GID" \
  -p "${PORT_HOST}:${PORT_CONTAINER}" \
  -e TZ="Europe/Vienna" \
  -v "$DATA_DIR:/data" \
  "${USB_BUS_MOUNT_ARGS[@]}" \
  "${DEVICE_ARGS[@]}" \
  nodered/node-red:latest

# === 8. systemd Service (eigener Name, kein Konflikt) ===
echo "Erstelle systemd Service: nodered-addon.service"
cat <<EOF | sudo tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=Node-RED Addon (Docker) on port ${PORT_HOST}
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start ${CONTAINER_NAME}
ExecStop=/usr/bin/docker stop ${CONTAINER_NAME}
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now nodered-addon.service

# === 9. Ergebnis ===
IP="$(hostname -I | awk '{print $1}')"
echo "-----------------------------------------------------------------"
echo "OK: Node-RED Addon läuft"
echo "URL:        http://$IP:${PORT_HOST}"
echo "Data-Dir:   $DATA_DIR  -> /data"
echo "Container:  $CONTAINER_NAME"
echo "Service:    sudo systemctl status nodered-addon.service"
echo "Logs:       sudo docker logs -f $CONTAINER_NAME"
echo "-----------------------------------------------------------------"

SUCCESS=1
exit 0
