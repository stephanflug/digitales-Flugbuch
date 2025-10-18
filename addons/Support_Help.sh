#!/bin/bash
# Datei: /usr/local/bin/wireguard_fetch_and_enable.sh
# Zweck: WG-Konfig laden, speichern und Interface starten – ohne DNS-Manipulation

# --- CGI / Streaming-Header ---
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

# --- Logging ---
LOGFILE="/var/log/support_help.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

set -euo pipefail
set -x

say() { echo "data: $*"; echo ""; }

SCRIPT_PATH="$(realpath "$0")"
TMP_FILE=""

# Cleanup & Selbstentfernung bei Fehler
trap '
  rc=$?
  [ -n "${TMP_FILE:-}" ] && [ -f "$TMP_FILE" ] && rm -f "$TMP_FILE"
  if [ $rc -ne 0 ]; then
    say "Fehler aufgetreten (Exit-Code $rc) – Script wird entfernt..."
    rm -f "$SCRIPT_PATH" || true
  fi
  exit $rc
' EXIT

say "Starte Support Help Funktion"

# === Konfiguration ===
ID_FILE="/opt/digitalflugbuch/data/DatenBuch/IDnummer.txt"
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
WG_IFACE="wg0"
BASE_URL="https://flugbuch.gltdienst.home64.de/Support"
USE_REWRITE=0
# ======================

# 1) Pakete sicherstellen
say "Installiere erforderliche Pakete..."
sudo apt-get update
sudo apt-get install -y wireguard curl ca-certificates

# --- KEINE DNS-Änderungen mehr ---
say "Überspringe DNS-Konfiguration (wird extern verwaltet)..."

# 2) ID aus Datei lesen
if [[ ! -f "$ID_FILE" ]]; then
  say "Fehler: ID-Datei nicht gefunden ($ID_FILE)"
  exit 1
fi

ID=$(grep -E '^ID:' "$ID_FILE" | awk -F': ' '{print $2}' | tr -d "\r" | xargs)
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

# 3a) Robuster Download mit Fallback
HTTP_STATUS=$(curl -4 -A "curl" -m 20 --retry 3 --retry-delay 1 \
  -w "%{http_code}" -fsSL "${CONF_URL}" -o "${TMP_FILE}" || true)
if [[ "$HTTP_STATUS" != "200" ]]; then
  rm -f "${TMP_FILE}"
  say "Fehler: Download fehlgeschlagen (HTTP ${HTTP_STATUS}). Abbruch."
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
say "Starte WireGuard über ${CONF_PATH} (ohne Kopie/Unit)..."
sudo chmod 600 "${CONF_PATH}"

# Falls Interface bereits läuft
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

say "Fertig! Support Verbindung erfolgreich hergestellt."
