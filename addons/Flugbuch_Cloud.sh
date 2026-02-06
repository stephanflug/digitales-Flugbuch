#!/bin/bash
# Flugbuch_Cloud.sh
# Zweck: WireGuard-Konfig anhand der ID laden, speichern und Interface starten
# -> robust gegen APT/DPKG-Fehler (Auto-Recovery), ohne DNS-Manipulation
# Ausgabe: Server-Sent Events (SSE)
# Selbstlöschung: nur bei Fehler

FLUGBUCH_CLOUD_INSTALLER_VERSION="2.0.1"
FLUGBUCH_CLOUD_RAW_URL="https://raw.githubusercontent.com/stephanflug/digitales-Flugbuch/main/addons/Flugbuch_Cloud.sh"

# If not running as root, re-exec via sudo (installer may be launched by a web/app user).
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E bash "$0" "$@"
  fi
  echo "Content-Type: text/event-stream"; echo "Cache-Control: no-cache"; echo "Connection: keep-alive"; echo ""
  echo "data: ERROR: Dieses Script muss als root laufen (oder sudo ist erforderlich)."; echo ""
  exit 1
fi

# --- Self-update (cached installer refresh) ---
fetch_cmd=""
if command -v curl >/dev/null 2>&1; then
  fetch_cmd="curl -fsSL"
elif command -v wget >/dev/null 2>&1; then
  fetch_cmd="wget -qO-"
fi
if [ -n "$fetch_cmd" ]; then
  tmp="/tmp/Flugbuch_Cloud.sh.$$"
  if $fetch_cmd "$FLUGBUCH_CLOUD_RAW_URL" >"$tmp" 2>/dev/null; then
    new_ver=$(grep -E '^FLUGBUCH_CLOUD_INSTALLER_VERSION=' "$tmp" | head -n1 | cut -d'"' -f2)
    if [ -n "$new_ver" ] && [ "$new_ver" != "$FLUGBUCH_CLOUD_INSTALLER_VERSION" ]; then
      echo "Content-Type: text/event-stream"; echo "Cache-Control: no-cache"; echo "Connection: keep-alive"; echo ""
      echo "data: Update gefunden: $FLUGBUCH_CLOUD_INSTALLER_VERSION -> $new_ver (ersetze Installer und starte neu)"; echo ""
      install_path="$0"
      cp -f "$tmp" "$install_path" 2>/dev/null || true
      chmod +x "$install_path" 2>/dev/null || true
      rm -f "$tmp" 2>/dev/null || true
      exec bash "$install_path" "$@"
    fi
  fi
  rm -f "$tmp" 2>/dev/null || true
fi

# --- CGI / Streaming-Header ---
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

# --- Logging ---
LOGFILE="/var/log/flugbuchcloud.log"
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
# If /var/log is not writable for some reason, fall back to /tmp
if ! ( : >>"$LOGFILE" ) 2>/dev/null; then
  LOGFILE="/tmp/flugbuchcloud.log"
fi
exec > >(tee -a "$LOGFILE")
exec 2>&1

set -Eeuo pipefail
set -x

say() {
  echo "data: $*"
  echo ""
}

# SSE-Zeile
SCRIPT_PATH="$(realpath "$0")"
TMP_FILE=""

# --- Aufräumen & Selbstentfernung: nur bei Fehler löschen ---
trap ' rc=$?
  [ -n "${TMP_FILE:-}" ] && [ -f "$TMP_FILE" ] && rm -f "$TMP_FILE"
  if [ $rc -eq 0 ]; then
    say "Fertig – Script erfolgreich beendet. Datei bleibt bestehen. Log: $LOGFILE"
  else
    say "FEHLER (Exit-Code $rc) – Script wird zur Sicherheit entfernt."
    say "Siehe Log: $LOGFILE"
    sudo rm -f "$SCRIPT_PATH" || true
  fi
  exit $rc
' EXIT

say "Starte Flugbuch Cloud Funktion"

# === Konfiguration ===
ID_FILE="/opt/digitalflugbuch/data/DatenBuch/IDnummer.txt"
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/flugbuchcloud.conf"
WG_IFACE="flugbuchcloud"  # muss zum Dateinamen passen
BASE_URL="https://flugbuch.gltdienst.home64.de/Support"
USE_REWRITE=0  # 0 = fetch.php?id=<ID>, 1 = /Support/<ID>/wg0.conf
CURL_OPTS=(-4 -A "curl" -m 20 --retry 3 --retry-delay 1 -fsSL)

# ---------- Hilfsfunktionen ----------
apt_busy() {
  pgrep -f "apt|apt-get|unattended|dpkg" >/dev/null 2>&1
}

wait_for_apt_free() {
  local timeout="${1:-90}"
  local elapsed=0

  while apt_busy; do
    say "APT/DPKG läuft noch – warte... ($elapsed/${timeout}s)"
    sleep 2
    elapsed=$((elapsed+2))
    if [ $elapsed -ge $timeout ]; then
      say "WARNUNG: APT scheint zu hängen. Prüfe Locks..."
      break
    fi
  done

  if ! apt_busy; then
    for lock in /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock; do
      if sudo lsof "$lock" >/dev/null 2>&1; then
        say "Lock $lock ist belegt – APT-Prozess aktiv. Weiter warten..."
      elif [ -e "$lock" ]; then
        say "Entferne verwaisten Lock: $lock"
        sudo rm -f "$lock" || true
      fi
    done
  fi
}

# Non-interactive dpkg/apt options to avoid conffile prompts.
DPKG_OPTS=(
  "-o" "Dpkg::Options::=--force-confdef"
  "-o" "Dpkg::Options::=--force-confold"
)

repair_apt() {
  wait_for_apt_free 90

  # If dpkg is stuck on conffile prompts, force defaults/keep-old.
  say "Repariere DPKG-Konfiguration (dpkg --configure -a) (non-interactive)..."
  sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a --force-confdef --force-confold || true

  say "Repariere evtl. gebrochene Abhängigkeiten (apt-get -f install) (non-interactive)..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q "${DPKG_OPTS[@]}" -f install || true

  say "Paketlisten aktualisieren (apt-get update)..."
  sudo apt-get update || true
}

apt_install_retry() {
  local tries=3
  local i=1
  while :; do
    wait_for_apt_free 90
    say "Installiere Pakete: $* (Versuch $i/$tries)..."
    if sudo DEBIAN_FRONTEND=noninteractive apt-get -yq "${DPKG_OPTS[@]}" install "$@"; then
      return 0
    fi
    say "Installationsversuch $i fehlgeschlagen – starte Reparatur..."
    repair_apt
    i=$((i+1))
    if [ $i -gt $tries ]; then
      say "ERROR: Paketinstallation nach $tries Versuchen fehlgeschlagen."
      return 1
    fi
  done
}

curl_status() {
  # HTTP laden und Statuscode liefern
  local url="$1" out="$2"
  curl "${CURL_OPTS[@]}" -w "%{http_code}" "$url" -o "$out"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { say "Fehlt: $1"; return 1; }
}

check_kernel_wireguard() {
  # Prüfe Userspace-Tool + Kernelmodul
  if ! require_cmd wg || ! require_cmd wg-quick; then
    return 1
  fi
  if lsmod | grep -q "^wireguard"; then
    say "Kernelmodul wireguard ist geladen."
    return 0
  fi
  if modprobe wireguard 2>/dev/null; then
    say "Kernelmodul wireguard geladen."
    return 0
  fi
  # Auf Systemen ohne separates Modul (z.B. integriert) testet wg-quick beim Start.
  say "Hinweis: Konnte Modul nicht direkt laden – wg-quick testet beim Start automatisch weiter."
  return 0
}

extract_endpoint() {
  # Liest den Endpoint aus der Konfiguration
  awk -F'=' '/^\[Peer\]/{p=1} p&&$1~"Endpoint"{gsub(/[ \t]/,"",$2);print $2; exit}' "$CONF_PATH" || true
}

udp_probe() {
  # UDP-„reachability“ rudimentär testen
  local endpoint="$1"
  local host="${endpoint%:*}"
  local port="${endpoint##*:}"
  if [ -z "$host" ] || [ -z "$port" ]; then
    say "Kein Endpoint zum Prüfen gefunden."
    return 0
  fi
  if ! getent hosts "$host" >/dev/null 2>&1; then
    say "WARNUNG: DNS-Auflösung für $host fehlgeschlagen."
    return 1
  fi
  if command -v nc >/dev/null 2>&1; then
    if nc -uz -w 2 "$host" "$port"; then
      say "Endpoint $endpoint scheint per UDP erreichbar."
      return 0
    else
      say "Hinweis: UDP-Port $endpoint nicht bestätigt – kann normal sein (keine Antwort auf leere Pakete)."
      return 0
    fi
  fi
  return 0
}

# 0) APT/DPKG Zustand vorab reparieren (falls nötig)
repair_apt

# 1) Pakete – IMMER versuchen zu installieren/aktualisieren
say "Installiere/aktualisiere erforderliche Pakete..."
apt_install_retry wireguard wireguard-tools curl ca-certificates

# 1a) Kernel/Tools prüfen
check_kernel_wireguard || true

# 1b) Interface/Dateiname konsistent?
conf_base="$(basename "$CONF_PATH" .conf)"
if [[ "$conf_base" != "$WG_IFACE" ]]; then
  say "Fehler: CONF_PATH-Name ($conf_base) passt nicht zu WG_IFACE ($WG_IFACE)."
  exit 1
fi

# 2) ID aus Datei lesen (flexibel: 'ID: <…>' ODER nur die ID)
if [[ ! -f "$ID_FILE" ]]; then
  say "Fehler: ID-Datei nicht gefunden ($ID_FILE)"
  exit 1
fi

ID="$(awk -F': ' '/^ID: /{print $2}' "$ID_FILE" | tr -d '\r' | xargs)"
if [[ -z "$ID" ]]; then
  ID="$(head -n1 "$ID_FILE" | tr -d '\r' | xargs)"
fi
if [[ -z "$ID" ]]; then
  say "Fehler: Keine gültige ID in $ID_FILE gefunden."
  exit 1
fi
say "Gefundene ID: $ID"

# 3) URL zusammensetzen
if [[ "$USE_REWRITE" -eq 1 ]]; then
  CONF_URL="${BASE_URL}/${ID}/wg0.conf"
else
  CONF_URL="${BASE_URL}/fetch.php?id=${ID}"
fi
say "Hole Konfiguration von: ${CONF_URL}"
TMP_FILE="$(mktemp)"

# 3a) Robuster Download mit Statusausgabe
HTTP_STATUS="$(curl_status "${CONF_URL}" "${TMP_FILE}" || true)"
if [[ "$HTTP_STATUS" != "200" ]]; then
  rm -f "${TMP_FILE}"
  say "Fehler: Download fehlgeschlagen (HTTP ${HTTP_STATUS})."
  say "Hinweis: Prüfe DNS/Internet oder Erreichbarkeit des Servers."
  exit 1
fi

# 4) Konfig validieren
if ! grep -q '^\[Interface\]' "${TMP_FILE}"; then
  rm -f "${TMP_FILE}"
  say "Fehler: Keine gültige WireGuard-Konfiguration erkannt."
  exit 1
fi

# 5) Datei speichern & Rechte setzen
sudo mkdir -p "$(dirname "$CONF_PATH")"
sudo mv "${TMP_FILE}" "${CONF_PATH}"
TMP_FILE=""
sudo chown www-data:www-data "${CONF_PATH}"
sudo chmod 666 "${CONF_PATH}"
say "Konfiguration gespeichert unter ${CONF_PATH} (Rechte 666, Eigentümer www-data)."

# 5a) Warnung bei Default-Route in AllowedIPs
if grep -Eiq '^[[:space:]]*AllowedIPs[[:space:]]*=[[:space:]]*(.*0\.0\.0\.0/0|::/0)' "$CONF_PATH"; then
  say "WARNUNG: AllowedIPs enthalten Default-Route (0.0.0.0/0 oder ::/0). Für reines Support-VPN besser serverseitig einschränken."
fi

# 6) Verbindung aktivieren
say "Starte WireGuard über ${CONF_PATH}..."
sudo chmod 600 "${CONF_PATH}"

# Falls Interface bereits läuft: sauber stoppen
if sudo wg show "${WG_IFACE}" >/dev/null 2>&1; then
  say "Interface ${WG_IFACE} läuft – stoppe es zuerst..."
  sudo wg-quick down "${CONF_PATH}" || true
fi

# Start (mit zweitem Versuch nach kurzer Reparatur falls nötig)
if ! sudo wg-quick up "${CONF_PATH}"; then
  ERR=$?
  say "wg-quick up fehlgeschlagen (Code ${ERR}). Versuche kurze Reparatur..."
  sudo systemctl daemon-reload || true
  sleep 2
  if ! sudo wg-quick up "${CONF_PATH}"; then
    ERR=$?
    sudo chmod 666 "${CONF_PATH}"
    say "Fehler: wg-quick up erneut fehlgeschlagen (Code ${ERR})."
    journalctl -u "wg-quick@${WG_IFACE}" --no-pager -n 50 2>/dev/null | sed 's/^/data: /'
    exit $ERR
  fi
fi

# Rechte zurück auf 666 (für Web-UI)
sudo chmod 666 "${CONF_PATH}"

# 7) Systemd-Autostart einrichten
if command -v systemctl >/dev/null 2>&1; then
  say "Richte systemd-Autostart für ${WG_IFACE} ein..."
  sudo mkdir -p /etc/wireguard
  sudo cp "${CONF_PATH}" "/etc/wireguard/${WG_IFACE}.conf"
  sudo chown root:root "/etc/wireguard/${WG_IFACE}.conf"
  sudo chmod 600 "/etc/wireguard/${WG_IFACE}.conf"
  if sudo systemctl enable "wg-quick@${WG_IFACE}.service"; then
    say "systemd-Service wg-quick@${WG_IFACE}.service für Autostart aktiviert."
  else
    say "Hinweis: Konnte wg-quick@${WG_IFACE}.service nicht aktivieren. Prüfen Sie sudo-Rechte / Journal."
  fi
else
  say "systemd nicht verfügbar – Autostart über systemd nicht möglich."
fi

# 8) Status ausgeben
WG_STATUS="$(sudo wg show "${WG_IFACE}" 2>&1 || true)"
say "WireGuard-Status (${WG_IFACE}):"
echo "data: --- STATUS BEGIN ---"; echo ""
# multi-line SSE
while IFS= read -r ln; do echo "data: $ln"; echo ""; done <<< "$WG_STATUS"
echo "data: --- STATUS END ---"; echo ""

# 9) Endpoint-Erreichbarkeit prüfen
ENDPOINT="$(extract_endpoint)"
if [ -n "$ENDPOINT" ]; then
  say "Prüfe Endpoint-Erreichbarkeit: ${ENDPOINT}"
  udp_probe "$ENDPOINT" || true
else
  say "Hinweis: Kein Endpoint in der Konfiguration gefunden (Server-seitige Konfig prüfen)."
fi

say "Fertig! Flugbuch Cloud Verbindung erfolgreich hergestellt."
