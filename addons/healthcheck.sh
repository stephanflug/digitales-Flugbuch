#!/bin/bash
# All-in-one Systemcheck (SSE/CGI + Log)
# - Führt sich selbst als root aus (auto-sudo)
# - Sendet Live-Ausgabe via Server-Sent Events (SSE)
# - Schreibt parallel in /var/log/systemcheck.log
# - Löscht beim Start das alte Log
# - Löscht sich nach Abschluss selbst (Log bleibt erhalten)

set -euo pipefail

# --------------------------- Root-Auto-Check ---------------------------
if [ "$EUID" -ne 0 ]; then
  # Wenn unter CGI: QUERY_STRING übergeben
  if [ -n "${QUERY_STRING-}" ]; then
    export QUERY_STRING
  fi
  # Neu starten mit sudo, falls verfügbar
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E bash "$0" "$@"
  else
    echo "Content-Type: text/plain"
    echo
    echo "Fehler: Dieses Script muss als root ausgeführt werden, sudo ist nicht verfügbar."
    exit 1
  fi
fi

# --------------------------- SSE/CGI Header ---------------------------
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

say(){ echo "data: $*"; echo ""; }
section(){ echo; echo "=================================================================="; echo "== $1"; echo "=================================================================="; }
have(){ command -v "$1" >/dev/null 2>&1; }

# --------------------------- Modus bestimmen --------------------------
FULL=0
[[ "${1:-}" == "--full" ]] && FULL=1
if [ "${QUERY_STRING-}" != "" ] && echo "$QUERY_STRING" | grep -qE '(^|&)full=1(&|$)'; then
  FULL=1
fi

# --------------------------- Log vorbereiten --------------------------
LOG="/var/log/systemcheck.log"
rm -f "$LOG" 2>/dev/null || true
touch "$LOG"
chmod 640 "$LOG"

# Alle Ausgaben -> Log + SSE streamen
exec > >(stdbuf -i0 -oL -eL tee -a "$LOG" >(while IFS= read -r line; do echo "data: $line"; echo ""; done) >/dev/null) 2>&1

# --------------------------- Startbanner ------------------------------
section "Systemcheck gestartet"
echo "Zeit: $(date -R)"
echo "Modus: $([ $FULL -eq 1 ] && echo 'VOLL' || echo 'SCHNELL')"
echo "Log-Datei: $LOG"

# --------------------------- Kurzmetriken -----------------------------
section "Kurzmetriken"
CPU_IDLE="$(top -bn1 | grep 'Cpu(s)' | sed -n 's/.*, *\([0-9.]*\)%* id.*/\1/p' || true)"
[ -z "$CPU_IDLE" ] && CPU_IDLE=0
CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", 100 - $CPU_IDLE}")
echo "CPU-Auslastung:  ${CPU_USAGE}%"

if free -m >/dev/null 2>&1; then
  RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
  RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
  RAM_FREE=$(free -m | awk '/Mem:/ {print $4}')
  echo "RAM:             used ${RAM_USED} MiB / total ${RAM_TOTAL} MiB (free ${RAM_FREE} MiB)"
fi

DISK_USED=$(df -h / | awk 'NR==2 {print $5}')
echo "Disk /:          ${DISK_USED:-N/A} genutzt"

if have vcgencmd; then
  echo "Temperatur:      $(vcgencmd measure_temp 2>/dev/null | sed 's/temp=//')"
else
  if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
    printf "Temperatur:      %.1f'C\n" "$(awk '{print $1/1000}' /sys/class/thermal/thermal_zone0/temp)"
  else
    echo "Temperatur:      N/A"
  fi
fi

# --------------------------- Boot & Systemd ---------------------------
section "Boot & Systemd"
echo "Fehlgeschlagene Dienste:"
systemctl --failed || true

echo
echo "Start-Dauer (Top-20):"
systemd-analyze blame 2>/dev/null | head -n 20 || echo "systemd-analyze nicht verfügbar."

echo
echo "Aktive Timer (Top-15):"
systemctl list-timers --all --no-pager 2>/dev/null | sed -n '1,20p' || true

# --------------------------- Journal / OOM ----------------------------
section "Journal (seit letztem Boot)"
ERRS=$(journalctl -p err -b --no-pager | wc -l || echo 0)
WARNS=$(journalctl -p warning -b --no-pager | wc -l || echo 0)
echo "Fehler (err):    ${ERRS}"
echo "Warnungen:       ${WARNS}"
echo
echo "--- Letzte 200 Warnungen/Fehler ---"
journalctl -b -p warning --no-pager -n 200 || true

echo
echo "OOM-/Speicher-Killer:"
dmesg -T | grep -Ei 'Out of memory|oom-killer' || echo "Keine OOM-Einträge gefunden."

# --------------------------- Kernel / dmesg ---------------------------
section "Kernel-Meldungen (dmesg: error/warn)"
if dmesg --level=err,warn >/dev/null 2>&1; then
  dmesg -T --level=err,warn || dmesg --level=err,warn
else
  dmesg -T | grep -Ei 'error|warn|fail|under-volt|mmc|i/o error' || true
fi

# ---------------------- Temperatur & Throttling ----------------------
section "Temperatur & Throttling"
if have vcgencmd; then
  echo "CPU-Temp:        $(vcgencmd measure_temp 2>/dev/null | sed 's/temp=//')"
  echo "ARM/GPU Memory:  $(vcgencmd get_mem arm 2>/dev/null) / $(vcgencmd get_mem gpu 2>/dev/null)"
  RAW=$(vcgencmd get_throttled 2>/dev/null | awk -F= '{print $2}')
  if [[ "${RAW:-}" =~ ^0x ]]; then
    VAL=$((16#${RAW#0x}))
    printf "get_throttled:   0x%X\n" "$VAL"
    for bit in 0 1 2 3 16 17 18 19; do
      if [ $(( (VAL >> bit) & 1 )) -eq 1 ]; then
        case $bit in
          0)  echo "→ Unterspannung (JETZT)";;
          1)  echo "→ CPU gedrosselt (JETZT)";;
          2)  echo "→ ARM-Frequenz begrenzt (JETZT)";;
          3)  echo "→ Soft-Temperaturlimit (JETZT)";;
          16) echo "→ Unterspannung SEIT BOOT";;
          17) echo "→ Drosselung SEIT BOOT";;
          18) echo "→ ARM-Frequenzbegrenzung SEIT BOOT";;
          19) echo "→ Soft-Temperaturlimit SEIT BOOT";;
        esac
      fi
    done
  else
    echo "get_throttled:   ${RAW:-N/A}"
  fi
else
  echo "vcgencmd nicht verfügbar."
fi

# ------------------------------ Ressourcen ---------------------------
section "Ressourcen"
echo "Speicher (free -h):"
free -h || true
echo
echo "CPU/IO (vmstat 1 3):"
vmstat 1 3 2>/dev/null || echo "vmstat nicht verfügbar"
echo
echo "Top CPU:"
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 10
echo
echo "Top RAM:"
ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 10
echo
echo "Swap/ZRAM:"
swapon --show || echo "Keine Swap-Devices aktiv."

# ----------------------- Dateisysteme & Speicher ----------------------
section "Dateisysteme & Speicher"
echo "Root-Mount (RW/RO?):"
grep ' / ' /proc/mounts || true
echo
echo "Platzbelegung (df -h):"
df -h || true
echo
echo "Inodes (df -i):"
df -i || true
echo
echo "SD-/I/O-Fehler (dmesg):"
dmesg -T | grep -Ei 'mmc|sdhci|i/o error|crc error' || echo "Keine offensichtlichen SD/I/O-Fehler gefunden."
echo
echo "Hinweis: fsck Root nur OFFLINE."
rootdev="$(findmnt -n -o SOURCE / 2>/dev/null || echo /dev/mmcblk0p2)"
echo "Beispiel (OFFLINE!): sudo fsck -f $rootdev"

# ------------------------------ Netzwerk ------------------------------
section "Netzwerk"
echo "IP-Adressen:"
ip -4 a || true
echo
echo "Routing:"
ip r || true
echo
echo "DNS:"
if have resolvectl; then
  resolvectl status 2>/dev/null | sed -n '1,120p' || true
else
  cat /etc/resolv.conf 2>/dev/null || true
fi
echo
echo "Konnektivität:"
timeout 5 ping -c 2 1.1.1.1 >/dev/null 2>&1 && echo "Ping 1.1.1.1: OK" || echo "Ping 1.1.1.1: FEHLER"
timeout 5 ping -c 2 google.com >/dev/null 2>&1 && echo "Ping google.com (DNS): OK" || echo "Ping google.com (DNS): FEHLER"

# ------------------------------- Zeit/NTP -----------------------------
section "Zeit & NTP"
if have timedatectl; then timedatectl; fi
if systemctl status systemd-timesyncd >/dev/null 2>&1; then
  echo
  echo "systemd-timesyncd Status:"
  systemctl status systemd-timesyncd --no-pager -n 0 || true
fi

# -------------------------- Firewall / Sicherheit ---------------------
section "Firewall/Sicherheit"
if have ufw; then ufw status verbose || true; else echo "UFW nicht installiert."; fi
if have nft; then echo; echo "nftables (Kurz):"; nft list ruleset 2>/dev/null | sed -n '1,120p' || true; fi
if have iptables; then echo; echo "iptables (Kurz):"; iptables -S 2>/dev/null | sed -n '1,120p' || true; fi

# ------------------------------ Dienste ------------------------------
section "Dienste (Docker, WireGuard, SSH)"
if systemctl is-enabled docker >/dev/null 2>&1 || systemctl is-active docker >/dev/null 2>&1; then
  echo "Docker: $(systemctl is-active docker 2>/dev/null || echo unknown)"
  if have docker; then docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}' 2>/dev/null || true; fi
else
  echo "Docker nicht installiert/aktiv."
fi

# ---------------------- Bootloader / EEPROM (Pi4) ---------------------
section "Bootloader & EEPROM (Pi 4)"
if have rpi-eeprom-update; then rpi-eeprom-update || true; fi
if have vcgencmd; then echo "Bootloader-Version:"; vcgencmd bootloader_version 2>/dev/null || true; fi

# --------------------------- Pakete / Updates -------------------------
section "Pakete & Updates"
if have dpkg; then echo "dpkg Audit:"; dpkg --audit || echo "Keine Inkonsistenzen erkannt."; fi
if have apt-get; then
  echo
  echo "Anzahl verfügbarer Upgrades (simuliert):"
  apt-get -s upgrade 2>/dev/null | grep -E '^[0-9]+ upgraded' || echo "Upgrade-Simulation nicht möglich."
fi

# ----------------------------- Zusammenfassung ------------------------
section "Zusammenfassung"
echo "Journal: ${ERRS} Fehler, ${WARNS} Warnungen seit Boot."
echo
echo "Report gespeichert unter: $LOG"
echo "Modus: $([ $FULL -eq 1 ] && echo 'VOLL' || echo 'SCHNELL')"
echo "Skript wird nun gelöscht (Log bleibt erhalten)."

# --------------------------- Selbstlöschung ---------------------------
SCRIPT_PATH="$(realpath "$0")"
rm -f "$SCRIPT_PATH" 2>/dev/null || true

echo "data: Script wurde gelöscht – Log bleibt erhalten unter: $LOG"
echo ""
exit 0
