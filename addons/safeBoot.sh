#!/bin/bash

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

say() { echo "data: $*"; echo ""; }

say "Starte Installation des Safe-Boot-Selbstheilungssystems..."

# --- 1. Hauptskript schreiben ---
say "Erstelle /usr/local/sbin/safe-boot.sh..."
cat >/usr/local/sbin/safe-boot.sh <<'EOF'
#!/bin/bash
# Safe Boot Self-Healing Script

BACKUP_DIR="/opt/safe-boot/backup"
FLAG_FILE="/boot/SAFE_MODE.flag"
LOG_FILE="/var/log/safe-boot.log"

mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

log() {
  MSG="[$(date +%F_%T)] $*"
  echo "$MSG" | tee -a "$LOG_FILE"
}

FAILED=0
for svc in dbus systemd-journald NetworkManager; do
    if ! systemctl -q is-active "$svc"; then
        FAILED=1
    fi
done

if [ $FAILED -eq 0 ]; then
    log "System gesund → sichere aktuelle Konfig."
    cp -f /etc/fstab "$BACKUP_DIR/fstab"
    cp -f /etc/default/zramswap "$BACKUP_DIR/zramswap" 2>/dev/null || true
    cp -f /etc/systemd/journald.conf "$BACKUP_DIR/journald.conf" 2>/dev/null || true
    cp -f /etc/network/interfaces "$BACKUP_DIR/interfaces" 2>/dev/null || true
    rm -f "$FLAG_FILE"
else
    log "System defekt → spiele gesicherte Defaults zurück."
    for file in fstab zramswap journald.conf interfaces; do
        if [ -f "$BACKUP_DIR/$file" ]; then
            case "$file" in
                fstab) cp -f "$BACKUP_DIR/$file" /etc/fstab ;;
                zramswap) cp -f "$BACKUP_DIR/$file" /etc/default/zramswap ;;
                journald.conf) cp -f "$BACKUP_DIR/$file" /etc/systemd/journald.conf ;;
                interfaces) cp -f "$BACKUP_DIR/$file" /etc/network/interfaces ;;
            esac
        fi
    done
    echo "SAFE MODE AKTIV am $(date)" | tee -a "$LOG_FILE" > "$FLAG_FILE"
    systemctl restart dbus systemd-journald NetworkManager || true
fi
EOF

chmod +x /usr/local/sbin/safe-boot.sh
say "safe-boot.sh erstellt und ausführbar gemacht."

# --- 2. systemd Unit anlegen ---
say "Erstelle systemd Service-Datei..."
cat >/etc/systemd/system/safe-boot.service <<'EOF'
[Unit]
Description=Safe Boot Self-Healing
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/safe-boot.sh

[Install]
WantedBy=multi-user.target
EOF

# --- 3. Service aktivieren ---
say "Aktiviere safe-boot.service..."
systemctl daemon-reload
systemctl enable safe-boot.service

say "Installation abgeschlossen."
say "Logdatei unter /var/log/safe-boot.log verfügbar."
echo "event: done"
echo "data: ok"
echo ""
