#!/bin/bash
set -eEuo pipefail

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

# --- Auto-Elevation ---
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    exec sudo -E bash "$SCRIPT_PATH" "$@"
  else
    echo "FEHLER: Script benötigt Root-Rechte (sudo ohne Passwort oder als root ausführen)."
    exit 1
  fi
fi

LOGFILE="/var/log/nodered_addon_setup.log"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

echo "-------------------------------------------"
echo "Start Node-RED Addon Update: $(date)"
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
SERVICE_WRITTEN=0
NEW_CREATED=0

# Backup-Mappings: "backup_name|orig_name|was_running"
BACKUPS=()

self_delete() {
  set +e
  rm -f "$SCRIPT_PATH" >/dev/null 2>&1 || true
}

restore_backups() {
  set +e

  if [ "$SERVICE_WRITTEN" -eq 1 ]; then
    systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  if [ "$NEW_CREATED" -eq 1 ]; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi

  for entry in "${BACKUPS[@]}"; do
    IFS='|' read -r bkp orig was_running <<<"$entry"
    if docker ps -a --format '{{.Names}}' | grep -qx "$bkp"; then
      echo "Rollback: $bkp -> $orig"
      docker rename "$bkp" "$orig" >/dev/null 2>&1 || true
      if [ "$was_running" = "1" ]; then
        docker start "$orig" >/dev/null 2>&1 || true
      fi
    fi
  done
}

on_exit() {
  ec=$?
  if [ "$SUCCESS" -eq 1 ] && [ "$ec" -eq 0 ]; then
    echo "Update erfolgreich abgeschlossen."
    return
  fi
  echo "-----------------------------------------------------------------"
  echo "Update NICHT erfolgreich (Exit-Code: $ec)."
  echo "Rollback + Script wird gelöscht: $SCRIPT_PATH"
  echo "-----------------------------------------------------------------"
  restore_backups
  self_delete
}
trap on_exit EXIT

# --- Pi 3–5 only ---
MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
echo "Hardware: ${MODEL:-unbekannt}"
if ! echo "$MODEL" | grep -Eq 'Raspberry Pi (3|4|5)'; then
  echo "FEHLER: Nicht unterstützte Hardware: $MODEL"
  exit 1
fi

# --- Docker ok? ---
command -v docker >/dev/null 2>&1 || { echo "FEHLER: docker fehlt."; exit 1; }
systemctl is-active --quiet docker || { echo "FEHLER: Docker läuft nicht."; exit 1; }

# --- dirs ---
mkdir -p "$DATA_DIR"
chown -R 1000:1000 "$BASE_DIR" || true
if id "$USERNAME" >/dev/null 2>&1; then
  chown -R "$USERNAME:$USERNAME" "$BASE_DIR" || true
fi

# --- USB/Serial ---
DIALOUT_GID="$(getent group dialout | awk -F: '{print $3}')"
[ -z "$DIALOUT_GID" ] && DIALOUT_GID="20"

DEVICE_ARGS=()
for d in /dev/ttyUSB* /dev/ttyACM*; do
  [ -e "$d" ] && DEVICE_ARGS+=( "--device" "$d:$d" )
done

USB_BUS_MOUNT_ARGS=()
[ -d /dev/bus/usb ] && USB_BUS_MOUNT_ARGS+=( "-v" "/dev/bus/usb:/dev/bus/usb" )

# =====================================================================
# STOP -> PULL -> RECREATE -> START
# =====================================================================

echo "Stoppe Addon-Service (falls vorhanden)..."
systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true

echo "Suche laufenden Container auf Port ${PORT_HOST}..."
mapfile -t PUBLISHED < <(docker ps --filter "publish=${PORT_HOST}" --format '{{.ID}} {{.Names}} {{.Image}}')

if [ "${#PUBLISHED[@]}" -gt 0 ]; then
  for line in "${PUBLISHED[@]}"; do
    cid="$(awk '{print $1}' <<<"$line")"
    cname="$(awk '{print $2}' <<<"$line")"
    cimg="$(awk '{print $3}' <<<"$line")"

    # zusätzlich: Label prüfen
    label="$(docker inspect -f '{{ index .Config.Labels "flugbuch.addon" }}' "$cid" 2>/dev/null || true)"

    # Sicherheitscheck: nur Node-RED oder unser Label automatisch stoppen
    if [[ "$cimg" != nodered/node-red* && "$label" != "nodered" ]]; then
      echo "FEHLER: Port ${PORT_HOST} wird von NICHT-Node-RED Container belegt:"
      echo "  $line"
      echo "Abbruch (zur Sicherheit)."
      exit 1
    fi

    was_running="0"
    if docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null | grep -q true; then
      was_running="1"
    fi

    bkp="${cname}_backup_$(date +%Y%m%d%H%M%S)"
    echo "Stop + Backup: $cname ($cimg) -> $bkp"
    docker stop "$cid" >/dev/null 2>&1 || true
    docker rename "$cname" "$bkp"
    BACKUPS+=( "${bkp}|${cname}|${was_running}" )
  done
fi

# Wenn unser Standard-Container existiert (gestoppt), auch backupen (falls nicht schon passiert)
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    bkp="${CONTAINER_NAME}_backup_$(date +%Y%m%d%H%M%S)"
    echo "Backup (stopped): $CONTAINER_NAME -> $bkp"
    docker rename "$CONTAINER_NAME" "$bkp"
    BACKUPS+=( "${bkp}|${CONTAINER_NAME}|0" )
  fi
fi

# Warten bis Port wirklich frei ist
for i in {1..30}; do
  if ! ss -ltnp | awk '{print $4}' | grep -qE "(:|\.)${PORT_HOST}$"; then
    break
  fi
  sleep 0.2
done

if ss -ltnp | awk '{print $4}' | grep -qE "(:|\.)${PORT_HOST}$"; then
  echo "FEHLER: Port ${PORT_HOST} ist weiterhin belegt."
  ss -ltnp | grep -E "(:|\.)${PORT_HOST}\b" || true
  exit 1
fi

echo "Update: docker pull nodered/node-red:latest"
docker pull nodered/node-red:latest

echo "Erstelle neuen Container '$CONTAINER_NAME' auf Port ${PORT_HOST}..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --label "flugbuch.addon=nodered" \
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

echo "Schreibe/aktualisiere systemd Service: $SERVICE_NAME"
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
SERVICE_WRITTEN=1

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

# Backups entfernen nach Erfolg
for entry in "${BACKUPS[@]}"; do
  IFS='|' read -r bkp orig was_running <<<"$entry"
  if docker ps -a --format '{{.Names}}' | grep -qx "$bkp"; then
    echo "Entferne Backup-Container: $bkp"
    docker rm -f "$bkp" >/dev/null 2>&1 || true
  fi
done

IP="$(hostname -I | awk '{print $1}')"
echo "-----------------------------------------------------------------"
echo "OK: Node-RED Addon läuft (updated)"
echo "URL:        http://$IP:${PORT_HOST}"
echo "Data-Dir:   $DATA_DIR  -> /data"
echo "Container:  $CONTAINER_NAME"
echo "Service:    systemctl status $SERVICE_NAME"
echo "Logs:       docker logs -f $CONTAINER_NAME"
echo "-----------------------------------------------------------------"

SUCCESS=1
exit 0
