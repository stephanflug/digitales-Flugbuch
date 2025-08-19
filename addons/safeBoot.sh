#!/bin/bash

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

say() { echo "data: $*"; echo ""; }

say "Starte Installation des Safe-Boot-Selbstheilungssystems..."

# --- 1) Hauptskript schreiben -------------------------------------------------
say "Erstelle /usr/local/sbin/safe-boot.sh..."
cat >/usr/local/sbin/safe-boot.sh <<'EOF'

#!/bin/bash
# Safe Boot Self-Healing Script (v2) – schreibt IMMER ein vollständiges Manifest

set -euo pipefail

BACKUP_DIR="/opt/safe-boot/backup"
SERV_DIR="$BACKUP_DIR/services"
MANIFEST="$BACKUP_DIR/manifest.txt"
FLAG_FILE="/boot/SAFE_MODE.flag"
LOG_FILE="/var/log/safe-boot.log"

mkdir -p "$SERV_DIR" "$BACKUP_DIR/etc"
touch "$LOG_FILE" "$MANIFEST"

log() {
  MSG="[$(date +%F_%T)] $*"
  echo "$MSG" | tee -a "$LOG_FILE"
}

# ---- Dienstlisten -------------------------------------------------------------
running_services() {
  systemctl list-units --type=service --state=running --no-legend 2>/dev/null \
    | awk '{print $1}' | sed 's/\.service$//' | sort -u
}
enabled_services() {
  systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null \
    | awk '{print $1}' | sed 's/\.service$//' | sort -u
}

# ---- Whitelist für Konfigpfade je Dienst -------------------------------------
service_paths() {
  local s="$1"
  case "$s" in
    ssh|sshd)                        echo -e "/etc/ssh";;
    NetworkManager|network-manager)  echo -e "/etc/NetworkManager\n/etc/NetworkManager/system-connections";;
    dhcpcd)                          echo -e "/etc/dhcpcd.conf";;
    wpa_supplicant)                  echo -e "/etc/wpa_supplicant";;
    systemd-journald)                echo -e "/etc/systemd/journald.conf";;
    avahi-daemon)                    echo -e "/etc/avahi";;
    lighttpd)                        echo -e "/etc/lighttpd";;
    nginx)                           echo -e "/etc/nginx";;
    docker|containerd)               echo -e "/etc/docker\n/etc/containerd";;
    cron|crond)                      echo -e "/etc/cron.d\n/etc/crontab";;
    systemd-timesyncd|timesyncd)     echo -e "/etc/systemd/timesyncd.conf";;
    systemd-logind|logind)           echo -e "/etc/systemd/logind.conf";;
    rsyslog)                         echo -e "/etc/rsyslog.conf\n/etc/rsyslog.d";;
    *)                               : ;;
  esac
}

cp_safe() { # kopiert Datei/Verzeichnis, falls vorhanden
  local src="$1" dst="$2"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
    return 0
  fi
  return 1
}

backup_core() {
  local core_paths=(
    "/etc/fstab"
    "/etc/default/zramswap"
    "/etc/systemd/journald.conf"
    "/etc/network/interfaces"
    "/etc/hostname"
    "/etc/hosts"
  )
  for p in "${core_paths[@]}"; do
    if cp_safe "$p" "$BACKUP_DIR/etc$(echo "$p" | sed 's#^/etc##')"; then
      echo "backup=core|$p" >>"$MANIFEST"
    fi
  done
}

backup_unit_files() {
  local svc="$1" unit="$svc.service"
  mkdir -p "$SERV_DIR/$svc"
  for d in /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system; do
    [ -f "$d/$unit" ] && cp_safe "$d/$unit" "$SERV_DIR/$svc/unit$(echo "$d" | sed 's#/#_#g').service"
    [ -d "$d/$unit.d" ] && cp_safe "$d/$unit.d" "$SERV_DIR/$svc/$(echo "$d" | sed 's#/#_#g').d"
  done
}

restart_from_manifest() {
  local list; list=$(awk -F= '/^service=/{print $2}' "$MANIFEST" | sort -u)
  systemctl daemon-reload
  for s in $list; do
    systemctl restart "$s.service" 2>/dev/null || true
  done
}

# ---- Gesundheitscheck Basisdienste -------------------------------------------
FAILED=0
for svc in dbus systemd-journald NetworkManager dhcpcd; do
  if systemctl list-unit-files | grep -q "^$svc\.service"; then
    systemctl -q is-active "$svc" || FAILED=1
  fi
done

if [ $FAILED -eq 0 ]; then
  # ---------------- GESUND: BACKUP & MANIFEST ---------------------------------
  log "System gesund → erstelle vollständiges Backup & Manifest."
  : >"$MANIFEST"
  echo "timestamp=$(date -Iseconds)"        >>"$MANIFEST"
  echo "kernel=$(uname -r)"                 >>"$MANIFEST"
  echo "rootdev=$(findmnt -no SOURCE /)"    >>"$MANIFEST"

  # Core-Dateien sichern + IMMER ins Manifest schreiben (falls vorhanden)
  backup_core

  # Dienste sammeln (laufend ∪ aktiviert)
  mapfile -t RUN < <(running_services || true)
  mapfile -t ENA < <(enabled_services || true)
  SVCS=$(printf "%s\n%s\n" "${RUN[@]:-}" "${ENA[@]:-}" | sed '/^$/d' | sort -u)

  for s in $SVCS; do
    echo "service=$s" >>"$MANIFEST"   # IMMER ins Manifest
    # bekannte Konfigurationen sichern
    mapfile -t PATHS < <(service_paths "$s" || true)
    for p in "${PATHS[@]:-}"; do
      [ -z "$p" ] && continue
      for real in $p; do
        if cp_safe "$real" "$SERV_DIR/$s/config$(echo "$real" | sed 's#/#_#g')"; then
          echo "backup=$s|$real" >>"$MANIFEST"
        fi
      done
    done
    backup_unit_files "$s" >/dev/null 2>&1 || true
  done

  rm -f "$FLAG_FILE"
  log "Backup abgeschlossen. Manifest: $MANIFEST"

else
  # ---------------- DEFEKT: RESTORE -------------------------------------------
  log "System defekt erkannt → Wiederherstellung aus Backup."
  # Core wiederherstellen
  while IFS= read -r line; do
    case "$line" in
      backup=core\|*)
        path="${line#backup=core|}"
        src="$BACKUP_DIR/etc$(echo "$path" | sed 's#^/etc##')"
        [ -e "$src" ] && cp -a "$src" "$path" || true
        ;;
    esac
  done < "$MANIFEST"

  # Service-Konfigs wiederherstellen
  while IFS= read -r line; do
    case "$line" in
      backup=*)
        entry="${line#backup=}"          # svc|/etc/pfad
        svc="${entry%%|*}"
        path="${entry#*|}"
        [ "$svc" = "core" ] && continue
        src="$SERV_DIR/$svc/config$(echo "$path" | sed 's#/#_#g')"
        [ -e "$src" ] && cp -a "$src" "$path" || true
        ;;
    esac
  done < "$MANIFEST"

  restart_from_manifest
  echo "SAFE MODE AKTIV am $(date)" | tee -a "$LOG_FILE" > "$FLAG_FILE"
  log "Wiederherstellung abgeschlossen. Details: $LOG_FILE | Flag: $FLAG_FILE"
fi

EOF

chmod 0755 /usr/local/sbin/safe-boot.sh
say "safe-boot.sh erstellt und ausführbar gemacht (0755)."

# --- 2) systemd-Unit anlegen --------------------------------------------------
say "Erstelle systemd Service-Datei..."
cat >/etc/systemd/system/safe-boot.service <<'EOF'
[Unit]
Description=Safe Boot Self-Healing (Backup/Restore)
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash /usr/local/sbin/safe-boot.sh

[Install]
WantedBy=multi-user.target
EOF

# --- 3) Logrotate für /var/log/safe-boot.log ---------------------------------
say "Richte Logrotation für /var/log/safe-boot.log ein..."
cat >/etc/logrotate.d/safe-boot <<'EOF'
/var/log/safe-boot.log {
    size 1M
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

# --- 4) Service aktivieren ----------------------------------------------------
say "Aktiviere safe-boot.service..."
systemctl daemon-reload
systemctl enable safe-boot.service

say "Installation abgeschlossen."
say "Backup-Pfad: /opt/safe-boot/backup  | Manifest: /opt/safe-boot/backup/manifest.txt"
say "Log: /var/log/safe-boot.log  | Safe-Flag (bei Recovery): /boot/SAFE_MODE.flag"
echo "event: done"
echo "data: ok"
echo ""
