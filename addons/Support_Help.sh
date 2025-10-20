#!/bin/bash
# Datei: /opt/addons/Support_Help.sh
# Zweck: WireGuard-Konfig anhand der ID laden, speichern und Interface starten
#        -> robust gegen APT/DPKG-Fehler (Auto-Recovery), ohne DNS-Manipulation
# Ausgabe: Server-Sent Events (SSE); Selbstlöschung nur bei nicht Erfolg

# --- CGI / Streaming-Header ---
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

# --- Logging ---
LOGFILE="/var/log/support_help.log"
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
exec > >(tee -a "$LOGFILE")
exec 2>&1

set -Eeuo pipefail
set -x

say() { echo "data: $*"; echo ""; }

SCRIPT_PATH="$(realpath "$0")"
TMP_FILE=""

# --- Aufräumen & Selbstentfernung: nur bei Fehler löschen ---
trap '
  rc=$?
  [ -n "${TMP_FILE:-}" ] && [ -f "$TMP_FILE" ] && rm -f "$TMP_FILE"
  if [ $rc -eq 0 ]; then
    say "Fertig – Script erfolgreich beendet. Datei bleibt bestehen. Log: $LOGFILE"
  else
    say "FEHLER (Exit-Code $rc) – Script wird zur Sicherheit entfernt."
    say "Siehe Log: $LOGFILE"
    rm -f "$SCRIPT_PATH" || true
  fi
  exit $rc
' EXIT

say "Starte Support Help Funktion"

# === Konfiguration ===
ID_FILE="/opt/digitalflugbuch/data/DatenBuch/IDnummer.txt"
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0support.conf"
WG_IFACE="wg0support"   # muss dem Interface-Namen in der wg0.conf entsprechen
BASE_URL="https://flugbuch.gltdienst.home64.de/Support"
USE_REWRITE=0    # 0 = fetch.php?id=<ID>, 1 = /Support/<ID>/wg0.conf
# ======================

# ---------- Hilfsfunktionen ----------
# Prüfe ob apt/dpkg Prozesse laufen
apt_busy() {
  pgrep -f "apt|apt-get|unattended|dpkg" >/dev/null 2>&1
}

# Warte bis Locks frei sind (mit Timeout)
wait_for_apt_free() {
  local timeout="${1:-60}"
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

  # Wenn keine Prozesse laufen, aber Locks existieren -> entfernen
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

# Repariere DPKG/APT Zustand robust
repair_apt() {
  wait_for_apt_free 60

  say "Repariere DPKG-Konfiguration (dpkg --configure -a)..."
  sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a || true

  say "Repariere evtl. gebrochene Abhängigkeiten (apt-get -f install)..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q -f install || true

  say "Paketlisten aktualisieren (apt-get update)..."
  sudo apt-get update || true
}

# Installiere Paketliste mit Retries
apt_install_retry() {
  local pkgs=("$@")
  local tries=3
  local i=1
  while :; do
    wait_for_apt_free 60
    say "Installiere Pakete: ${pkgs[*]} (Versuch $i/$tries)..."
    if sudo DEBIAN_FRONTEND=noninteractive apt-get -yq install "${pkgs[@]}"; then
      return 0
    fi
    say "Installationsversuch $i fehlgeschlagen – versuche Reparatur..."
    repair_apt
    i=$((i+1))
    if [ $i -gt $tries ]; then
      say "ERROR: Paketinstallation nach $tries Versuchen fehlgeschlagen."
      return 1
    fi
  done
}

# HTTP abrufen mit Statuscode-Ausgabe
curl_fetch() {
  local url="$1" out="$2"
  curl -4 -A "curl" -m 20 --retry 3 --retry-delay 1 -w "%{http_code}" -fsSL "$url" -o "$out"
}
# ------------------------------------

# 0) APT/DPKG Zustand vorab reparieren (falls nötig)
repair_apt

# 1) Pakete sicherstellen (ohne DNS-Manipulation)
say "Installiere erforderliche Pakete..."
apt_install_retry wireguard curl ca-certificates

# 2) ID aus Datei lesen
if [[ ! -f "$ID_FILE" ]]; then
  say "Fehler: ID-Datei nicht gefunden ($ID_FILE)"
  exit 1
fi

ID=$(grep -E '^ID:' "$ID_FILE" | awk -F': ' '{print $2}' | tr -d "\r" | xargs || true)
if [[ -z "${ID:-}" ]]; then
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

TMP_FILE=$(mktemp)

# 3a) Robuster Download
HTTP_STATUS="$(curl_fetch "${CONF_URL}" "${TMP_FILE}" || true)"
if [[ "$HTTP_STATUS" != "200" ]]; then
  rm -f "${TMP_FILE}"
  say "Fehler: Download fehlgeschlagen (HTTP ${HTTP_STATUS})."
  say "Hinweis: Prüfe DNS/Internet oder Erreichbarkeit des Servers."
  exit 1
fi

# 4) Prüfen, ob gültige WireGuard-Konfig
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

# 6) Verbindung aktivieren
say "Starte WireGuard über ${CONF_PATH}..."
sudo chmod 600 "${CONF_PATH}"

# Falls Interface bereits läuft: zuerst sauber stoppen
if sudo wg show "${WG_IFACE}" >/dev/null 2>&1; then
  say "Interface ${WG_IFACE} läuft – stoppe es zuerst..."
  sudo wg-quick down "${CONF_PATH}" || true
fi

# Start
if ! sudo wg-quick up "${CONF_PATH}"; then
  ERR=$?
  sudo chmod 666 "${CONF_PATH}"
  say "Fehler: wg-quick up fehlgeschlagen (Code ${ERR})."
  exit $ERR
fi

# Rechte zurück auf 666 (für Web-UI)
sudo chmod 666 "${CONF_PATH}"

# 7) Status ausgeben
WG_STATUS=$(sudo wg show "${WG_IFACE}" 2>&1 || true)
say "WireGuard-Status (${WG_IFACE}):"
echo "data: --- STATUS BEGIN ---"
echo ""
echo "data: ${WG_STATUS//$'\n'/$'\ndata: '}"
echo ""
echo "data: --- STATUS END ---"
echo ""

say "Fertig! Support-Verbindung erfolgreich hergestellt."
