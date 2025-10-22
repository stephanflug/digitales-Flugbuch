#!/bin/bash
# Datei: /usr/local/bin/pi5_zero_image_migrate.sh


LOGFILE="/var/log/PI5ZeroMigrate.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

set -euo pipefail
set -x

SCRIPT_PATH="$(realpath "$0")"
say() { echo "data: $*"; echo ""; }

# --- Aufräumfunktion bei Fehler ---
cleanup() {
  rc=$?
  if [ $rc -ne 0 ]; then
    say "Fehlercode $rc – Details siehe Log: $LOGFILE"
    say "Script wird entfernt (Fehlerfall)."
    rm -f "$SCRIPT_PATH" || true
  fi
}
trap cleanup EXIT

# --- Hardwareprüfung: Nur Raspberry Pi 5 ---
MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null | head -n 1 || true)"
if ! echo "${MODEL:-unbekannt}" | grep -q "Raspberry Pi 5"; then
  say "Keine Pi-5-Hardware erkannt (gefunden: '${MODEL:-unbekannt}'). Breche ab und entferne Skript."
  exit 1
fi
say "Raspberry Pi 5 erkannt – starte automatische Zero-Image-Migration..."

# --- Paketverwaltung vorbereiten ---
export DEBIAN_FRONTEND=noninteractive
APT_FLAGS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# --- 1) Prüfen und ggf. auf Bookworm umstellen ---
OS_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
if [ "${OS_CODENAME:-}" != "bookworm" ]; then
  say "Passe APT-Quellen auf 'bookworm' an..."
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
    [ -f "$f" ] && sudo sed -i 's/\<bullseye\>/bookworm/g;s/\<oldstable\>/bookworm/g' "$f"
  done
else
  say "APT-Quellen bereits auf 'bookworm'."
fi

say "Aktualisiere Paketlisten..."
sudo apt update

# --- 2) Kernel, Bootloader, Firmware ---
say "Installiere oder aktualisiere Kernel, Bootloader und Firmware..."
sudo apt install -y $APT_FLAGS raspberrypi-kernel raspberrypi-bootloader rpi-eeprom linux-firmware ca-certificates curl || true

# --- 3) EEPROM aktualisieren ---
if command -v rpi-eeprom-update >/dev/null 2>&1; then
  say "Aktualisiere EEPROM-Firmware..."
  sudo rpi-eeprom-update -a || true
else
  say "rpi-eeprom-update nicht verfügbar (wird ggf. nachinstalliert)."
fi

# --- 4) Grafiktreiber auf KMS setzen ---
CFG=""
if [ -f /boot/firmware/config.txt ]; then
  CFG="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
  CFG="/boot/config.txt"
fi

if [ -n "$CFG" ]; then
  say "Prüfe und aktualisiere dtoverlay-Eintrag in $CFG..."
  sudo sed -i 's/^\s*dtoverlay\s*=\s*vc4-fkms-v3d\s*$/dtoverlay=vc4-kms-v3d/g' "$CFG"
  if ! grep -q 'dtoverlay=vc4-kms-v3d' "$CFG"; then
    echo "" | sudo tee -a "$CFG" >/dev/null
    echo "# Pi 5 Grafiktreiber (KMS)" | sudo tee -a "$CFG" >/dev/null
    echo "dtoverlay=vc4-kms-v3d" | sudo tee -a "$CFG" >/dev/null
  fi
else
  say "Keine config.txt gefunden – KMS-Konfiguration konnte nicht gesetzt werden."
fi

# --- 5) Netzwerk-Priorität: LAN vor WLAN ---
say "Setze Netzwerk-Priorität: LAN vor WLAN..."

if command -v nmcli >/dev/null 2>&1; then
  say "NetworkManager erkannt – setze route-metric (LAN bevorzugt)..."

  # Aktive Verbindungen den Interfaces zuordnen, sonst alle passenden
  ETH_CONNS=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2=="eth0"{print $1}')
  [ -z "$ETH_CONNS" ] && ETH_CONNS=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="ethernet"{print $1}')

  WLAN_CONNS=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2=="wlan0"{print $1}')
  [ -z "$WLAN_CONNS" ] && WLAN_CONNS=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="wifi"{print $1}')

  for C in $ETH_CONNS; do
    sudo nmcli connection modify "$C" ipv4.route-metric 100 ipv6.route-metric 100 || true
  done
  for C in $WLAN_CONNS; do
    sudo nmcli connection modify "$C" ipv4.route-metric 300 ipv6.route-metric 300 || true
  done

  # Verbindungen neu laden/aktivieren (ohne kompletten Reboot)
  for C in $ETH_CONNS $WLAN_CONNS; do
    sudo nmcli connection up "$C" || true
  done

  say "NetworkManager: Prioritäten gesetzt (LAN bevorzugt, WLAN Fallback)."

elif [ -f /etc/dhcpcd.conf ]; then
  say "dhcpcd erkannt – trage Metriken in /etc/dhcpcd.conf ein..."

  CONF_FILE="/etc/dhcpcd.conf"
  BACKUP_FILE="/etc/dhcpcd.conf.bak_$(date +%Y%m%d-%H%M%S)"
  sudo cp "$CONF_FILE" "$BACKUP_FILE" || true

  if ! grep -q "metric 100" "$CONF_FILE"; then
    sudo tee -a "$CONF_FILE" >/dev/null <<'EOF'

# LAN bevorzugen, WLAN als Fallback (automatisch hinzugefügt)
interface eth0
    metric 100

interface wlan0
    metric 300
EOF
  else
    say "Einträge bereits vorhanden – überspringe Änderung."
  fi

  if systemctl list-unit-files | grep -q '^dhcpcd\.service'; then
    sudo systemctl restart dhcpcd || sudo service dhcpcd restart || true
  fi

  say "dhcpcd: Prioritäten gesetzt (LAN bevorzugt, WLAN Fallback)."
else
  say "Weder NetworkManager noch dhcpcd erkannt – überspringe Netzwerk-Priorität."
fi


# --- 6) Initramfs & Modulcache erneuern ---
say "Erneuere Initramfs und Modul-Cache..."
if command -v update-initramfs >/dev/null 2>&1; then
  sudo update-initramfs -u || true
fi
sudo depmod -a || true

# --- 7) System-Upgrade ---
say "Führe apt full-upgrade -y aus – dies kann einige Minuten dauern..."
sudo apt $APT_FLAGS full-upgrade -y

say "Entferne nicht mehr benötigte Pakete..."
sudo apt autoremove --purge -y || true

# --- 8) Abschluss ---
if [ -f /var/run/reboot-required ]; then
  say "Migration abgeschlossen – Neustart erforderlich, wird jetzt durchgeführt."
else
  say "Migration abgeschlossen – Neustart wird durchgeführt, um Änderungen zu aktivieren."
fi

say "Speichere Log unter $LOGFILE"
sleep 2

# --- 9) Reboot ---
say "Starte System neu..."
sudo sync || true
sleep 1
sudo reboot

exit 0
