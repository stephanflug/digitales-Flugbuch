#!/bin/bash
set -eEuo pipefail

# --- Script-Pfad (für Self-Delete) ---
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

# --- Auto-Elevation (damit /var/log funktioniert) ---
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    exec sudo -E bash "$SCRIPT_PATH" "$@"
  else
    echo "FEHLER: Script benötigt Root-Rechte (für /var/log, systemd, docker)."
    echo "Bitte als root ausführen oder NOPASSWD sudo erlauben."
    exit 1
  fi
fi

LOGFILE="/var/log/nodered_addon_setup.log"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

echo "-------------------------------------------"
echo "Start Node-RED Addon Setup: $(date)"
echo "Logdatei: $LOGFILE"
echo "-------------------------------------------"

# CRLF -> LF
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
SERVICE_NAME="nodered-addon.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
PORT_HOST="1881"
PORT_CONTAINER="1880"

SUCCESS=0
BACKUP_NAME=""
BACKUP_WAS_RUNNING=0
NEW_CREATED=0

restore_backup_if_needed() {
  set +e
  if [ "$NEW_CREATED" -eq 1 ]; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  if [ -n "$BACKUP_NAME" ] && docker ps -a --format '{{.Names}}' | grep -qx "$BACKUP_NAME"; then
    echo "Rollback: stelle vorherigen Container wieder her ($BACKUP_NAME -> $CONTAINER_NAME)"
    docker rename "$BACKUP_NAME" "$CONTAINER_NAME" >/dev/null 2>&1 || true
    if [ "$BACKUP_WAS_RUNNING" -eq 1 ]; then
      docker start "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
  fi
}

self_delete() {
  set +e
  rm -f "$SCRIPT_PATH" >/dev/null 2>&1 || true
}

on_exit() {
  ec=$?
  if [ "$SUCCESS" -eq 1 ] && [ "$ec" -eq 0 ]; then
    echo "Setup erfolgreich abgeschlossen."
    return
  fi
  echo "-----------------------------------------------------------------"
  echo "Installation NICHT erfolgreich (Exit-Code: $ec)."
  echo "Rollback + Script wird gelöscht: $SCRIPT_PATH"
  echo "-----------------------------------------------------------------"
  restore_backup_if_needed
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
command -v docker >/dev/null 2>&1 || { echo "FEHLER: docker fehlt."; exit 1; }
systemctl is-active --quiet docker || { echo "FEHLER: Docker läuft nicht."; exit 1; }

# === 2. Verzeichnisse anlegen ===
mkdir -p "$DATA_DIR"
chown -R 1000:1000 "$BASE_DIR" || true
if id "$USERNAME" >/dev/null 2>&1; then
  chown -R "$USERNAME:$USERNAME" "$BASE_DIR" || true
fi

# === 3. dialout GID ===
DIALOUT_GID="$(getent group dialout | awk -F: '{print $3}')"
[ -z "$DIALOUT_GID" ] && DIALOUT_GID="20"

# === 4. USB/Serial Devices dynamisch erkennen ===
DEVICE_ARGS=()
for d in /dev/ttyUSB* /dev/ttyACM*; do
  [ -e "$d" ] && DEVICE_ARGS+=( "--device" "$d:$d" )
done

USB_BUS_MOUNT_ARGS=()
[ -d /dev/bus/usb ] && USB_BUS_MOUNT_ARGS+=( "-v" "/dev/bus/usb:/dev/bus/usb" )

# === 5. Eigenen Service/Container stoppen (damit Port 1881 frei wird bei Re-Run) ===
systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true

# Wenn Container existiert: Backup für Rollback
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    BACKUP_WAS_RUNNING=1
  fi
  BACKUP_NAME="${CONTAINER_NAME}_backup_$(date +%Y%m%d%H%M%S)"
  echo "Backup: $CONTAINER_NAME -> $BACKUP_NAME"
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rename "$CONTAINER_NAME" "$BACKUP_NAME"
fi

# === 6. Port prüfen (jetzt erst!) ===
if ss -ltnp | awk '{print $4}' | grep -qE "(:|\.)${PORT_HOST}$"; then
  echo "FEHLER: Port ${PORT_HOST} ist weiterhin belegt (nicht durch unseren Container)."
  echo "Belegung:"
  ss -ltnp | grep -E "(:|\.)${PORT_HOST}\b" || true
  exit 1
fi

# === 7. Image pull ===
echo "Pull Node-RED Image..."
docker pull nodered/node-red:latest

# === 8. Neuen Container erstellen ===
echo "Starte Container '$CONTAINER_NAME' auf Port ${PORT_HOST}..."
docker run -d \
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
NEW_CREATED=1

# === 9. systemd Service aktualisieren/überschreiben ===
echo "Aktualisiere systemd Service: $SERVICE_NAME"
cat <<EOF | tee "$SERVICE_FILE" >/dev/null
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

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

# === 10. Backup entfernen (Update erfolgreich) ===
if [ -n "$BACKUP_NAME" ] && docker ps -a --format '{{.Names}}' | grep -qx "$BACKUP_NAME"; then
  echo "Entferne Backup-Container: $BACKUP_NAME"
  docker rm -f "$BACKUP_NAME" >/dev/null 2>&1 || true
fi

IP="$(hostname -I | awk '{print $1}')"
echo "-----------------------------------------------------------------"
echo "OK: Node-RED Addon läuft"
echo "URL:        http://$IP:${PORT_HOST}"
echo "Data-Dir:   $DATA_DIR  -> /data"
echo "Container:  $CONTAINER_NAME"
echo "Service:    systemctl status $SERVICE_NAME"
echo "Logs:       docker logs -f $CONTAINER_NAME"
echo "-----------------------------------------------------------------"

SUCCESS=1
exit 0
