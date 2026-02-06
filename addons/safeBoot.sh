#!/bin/bash
# safeBoot.sh
# Installer (CGI/SSE-friendly) for the Safe-Boot Self-Healing system.
#
# Usage (as root):
#   bash safeBoot.sh
#
# Notes:
# - Emits Server-Sent-Events headers + progress lines (works behind lighttpd/nginx CGI).
# - Installs:
#   - /usr/local/sbin/safe-boot.sh   (self-heal runner)
#   - /etc/systemd/system/safe-boot.service
#   - /etc/logrotate.d/safe-boot

set -euo pipefail

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

say() {
  echo "data: $*"
  echo ""
}

say "Starte Installation des Safe-Boot-Selbstheilungssystems..."

say "Erstelle /usr/local/sbin/safe-boot.sh..."
cat >/usr/local/sbin/safe-boot.sh <<'EOF'
#!/bin/bash
# Safe Boot Self-Healing Script (v3)
# - Creates a backup manifest when system is healthy
# - On unhealthy boot, restores critical configs
# - Adds proactive fixes for common post-power-loss issues:
#   - rebuild module dependency indexes (depmod)
#   - ensure cfg80211/brcmfmac can load (Pi WLAN)
#   - restart hostapd if enabled and WiFi AP mode is expected

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

have() { command -v "$1" >/dev/null 2>&1; }

# ---- Dienstlisten -----------------------------------------------------------
running_services() {
  systemctl list-units --type=service --state=running --no-legend 2>/dev/null \
    | awk '{print $1}' | sed 's/\.service$//' | sort -u
}

enabled_services() {
  systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null \
    | awk '{print $1}' | sed 's/\.service$//' | sort -u
}

# ---- Whitelist fÃ¼r Konfigpfade je Dienst -----------------------------------
service_paths() {
  local s="$1"
  case "$s" in
    ssh|sshd) echo -e "/etc/ssh";;
    NetworkManager|network-manager) echo -e "/etc/NetworkManager /etc/NetworkManager/system-connections";;
    dhcpcd) echo -e "/etc/dhcpcd.conf";;
    wpa_supplicant) echo -e "/etc/wpa_supplicant";;
    systemd-journald) echo -e "/etc/systemd/journald.conf";;
    avahi-daemon) echo -e "/etc/avahi";;
    lighttpd) echo -e "/etc/lighttpd";;
    nginx) echo -e "/etc/nginx";;
    docker|containerd) echo -e "/etc/docker /etc/containerd";;
    cron|crond) echo -e "/etc/cron.d /etc/crontab";;
    systemd-timesyncd|timesyncd) echo -e "/etc/systemd/timesyncd.conf";;
    systemd-logind|logind) echo -e "/etc/systemd/logind.conf";;
    rsyslog) echo -e "/etc/rsyslog.conf /etc/rsyslog.d";;
    hostapd) echo -e "/etc/hostapd /etc/default/hostapd";;
    dnsmasq) echo -e "/etc/dnsmasq.conf /etc/dnsmasq.d";;
    *) : ;;
  esac
}

cp_safe() {
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
    [ -f "$d/$unit" ] && cp_safe "$d/$unit" "$SERV_DIR/$svc/unit$(echo "$d" | sed 's#/#_#g').service" || true
    [ -d "$d/$unit.d" ] && cp_safe "$d/$unit.d" "$SERV_DIR/$svc/$(echo "$d" | sed 's#/#_#g').d" || true
  done
}

restart_from_manifest() {
  local list
  list=$(awk -F= '/^service=/{print $2}' "$MANIFEST" | sort -u)
  systemctl daemon-reload
  for s in $list; do
    systemctl restart "$s.service" 2>/dev/null || true
  done
}

# ---- Proactive fix: rebuild module dependency indexes ----------------------
# Rationale: after hard power loss, /lib/modules/*/modules.dep* can go missing.
# Symptom: hostapd/iw fail with "nl80211 not found" / "generic netlink not found"
# because modprobe cannot resolve cfg80211/brcmfmac.
fix_modules_if_needed() {
  local k="$(uname -r)"
  local modroot="/lib/modules/$k"

  # Only attempt on systems that have /lib/modules for this kernel.
  [ -d "$modroot" ] || return 0

  # If modules.dep is missing, or cfg80211 exists but cannot be modprobed, run depmod.
  local need_depmod=0
  if [ ! -e "$modroot/modules.dep" ] && [ ! -e "$modroot/modules.dep.bin" ]; then
    need_depmod=1
  fi

  if [ $need_depmod -eq 0 ] && have modprobe; then
    if [ -e "$modroot/kernel/net/wireless/cfg80211.ko" ] || [ -e "$modroot/kernel/net/wireless/cfg80211.ko.xz" ] || [ -e "$modroot/kernel/net/wireless/cfg80211.ko.zst" ]; then
      # Try a quiet modprobe check; if it fails with "not found", likely depmod needed.
      if ! modprobe -q cfg80211 2>/dev/null; then
        need_depmod=1
      fi
    fi
  fi

  if [ $need_depmod -eq 1 ] && have depmod; then
    log "Module index seems missing/broken â†’ running depmod -a"
    depmod -a || log "WARN: depmod failed"
  fi

  # Ensure WLAN modules are loaded if present
  if have modprobe; then
    modprobe -q cfg80211 2>/dev/null || true
    modprobe -q brcmfmac 2>/dev/null || true
  fi
}

# ---- Proactive fix: restore hostapd if it is enabled -----------------------
fix_hostapd_if_enabled() {
  # only if hostapd unit exists
  systemctl list-unit-files --type=service --no-pager --plain | grep -q '^hostapd\.service' || return 0

  if systemctl is-enabled -q hostapd 2>/dev/null; then
    # if ieee80211 exists, WiFi stack is present
    if [ -d /sys/class/ieee80211 ]; then
      log "hostapd enabled â†’ restarting"
      systemctl restart hostapd || true
    else
      log "hostapd enabled but /sys/class/ieee80211 missing â†’ WiFi stack not ready"
    fi
  fi
}

# ---- Gesundheitscheck mit Retry -------------------------------------------
check_ok=0
for attempt in 1 2 3; do
  FAILED=0
  for svc in dbus systemd-journald NetworkManager dhcpcd; do
    if systemctl list-unit-files --type=service --no-pager --plain | grep -q "^$svc\.service"; then
      systemctl -q is-active "$svc" || FAILED=1
    fi
  done
  [ $FAILED -eq 0 ] && { check_ok=1; break; }
  sleep 3
done

# Always try proactive fixes (they are safe even when the system is "healthy").
fix_modules_if_needed
fix_hostapd_if_enabled

if [ $check_ok -eq 1 ]; then
  # ---------------- GESUND: BACKUP & MANIFEST -------------------------------
  log "System gesund â†’ erstelle vollstÃ¤ndiges Backup & Manifest."

  rm -rf "$BACKUP_DIR"
  mkdir -p "$SERV_DIR" "$BACKUP_DIR/etc"

  : >"$MANIFEST"
  echo "timestamp=$(date -Iseconds)" >>"$MANIFEST"
  echo "kernel=$(uname -r)" >>"$MANIFEST"
  echo "rootdev=$(findmnt -no SOURCE /)" >>"$MANIFEST"

  backup_core

  mapfile -t RUN < <(running_services || true)
  mapfile -t ENA < <(enabled_services || true)
  SVCS=$(printf "%s %s " "${RUN[@]:-}" "${ENA[@]:-}" | sed '/^$/d' | sort -u)

  for s in $SVCS; do
    echo "service=$s" >>"$MANIFEST"

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
  # ---------------- DEFEKT: RESTORE ----------------------------------------
  log "System defekt erkannt â†’ Wiederherstellung aus Backup."

  while IFS= read -r line; do
    case "$line" in
      backup=core\|*)
        path="${line#backup=core|}"
        src="$BACKUP_DIR/etc$(echo "$path" | sed 's#^/etc##')"
        [ -e "$src" ] && cp -a "$src" "$path" || true
        ;;
    esac
  done < "$MANIFEST"

  while IFS= read -r line; do
    case "$line" in
      backup=*)
        entry="${line#backup=}"
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
say "safe-boot.sh erstellt und ausfÃ¼hrbar gemacht (0755)."

say "Erstelle systemd Service-Datei..."
cat >/etc/systemd/system/safe-boot.service <<'EOF'
[Unit]
Description=Safe Boot Self-Healing (Backup/Restore)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /usr/local/sbin/safe-boot.sh

[Install]
WantedBy=multi-user.target
EOF

say "Richte Logrotation fÃ¼r /var/log/safe-boot.log ein..."
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

say "Aktiviere safe-boot.service..."
systemctl daemon-reload
systemctl enable safe-boot.service

say "Installation abgeschlossen."
say "Backup-Pfad: /opt/safe-boot/backup | Manifest: /opt/safe-boot/backup/manifest.txt"
say "Log: /var/log/safe-boot.log | Safe-Flag (bei Recovery): /boot/SAFE_MODE.flag"

echo "event: done"
echo "data: ok"
echo ""
