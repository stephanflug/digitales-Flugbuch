#!/bin/bash
# Datei: /usr/local/bin/wireguard_fetch_and_enable.sh

LOGFILE="/var/log/support_help.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

set -euo pipefail
set -x

say() { echo "data: $*"; echo ""; }

SCRIPT_PATH="$(realpath "$0")"
TMP_FILE=""

# Löscht sich NUR bei Fehler (Exit-Code != 0) und räumt Temp-Datei auf
trap '
  rc=$?
  if [ -n "${TMP_FILE:-}" ] && [ -f "$TMP_FILE" ]; then rm -f "$TMP_FILE"; fi
  if [ $rc -ne 0 ]; then
    say "Fehler aufgetreten (Exit-Code $rc) – Script wird entfernt..."
    rm -f "$SCRIPT_PATH"
  fi
  exit $rc
' EXIT

say "Starte Support Help Funktion"

# === Konfiguration ===
ID_FILE="/opt/digitalflugbuch/data/DatenBuch/IDnummer.txt"
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
WG_IFACE="wg0"   # muss dem Interface-Namen in der wg0.conf entsprechen
BASE_URL="https://flugbuch.gltdienst.home64.de/Support"
USE_REWRITE=0    # 0 = fetch.php?id=<ID>, 1 = /Support/<ID>/wg0.conf
# ======================

# 1) WireGuard und curl sicherstellen
say "Installiere erforderliche Pakete..."
sudo apt-get update
sudo apt-get install -y wireguard resolvconf curl ca-certificates

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

HTTP_STATUS=$(curl -w "%{http_code}" -fsSL "${CONF_URL}" -o "${TMP_FILE}" || true)
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

# 5) Datei speichern & Rechte setzen (wie bei dir: 666 für Web-Addon)
sudo mkdir -p "$(dirname "$CONF_PATH")"
sudo mv "${TMP_FILE}" "${CONF_PATH}"
TMP_FILE=""
sudo chown www-data:www-data "${CONF_PATH}"
sudo chmod 666 "${CONF_PATH}"
say "Konfiguration gespeichert unter ${CONF_PATH} (Rechte 666, Eigentümer www-data)."

# 6) Verbindung aktivieren (OHNE systemd-Unit, direkt mit deiner Datei)
say "Starte WireGuard über ${CONF_PATH} (ohne Kopie/Unit)..."

# wg-quick verlangt restriktive Rechte -> temporär 600 setzen
sudo chmod 600 "${CONF_PATH}"

# Falls Interface bereits läuft: erst sauber runterfahren (mit exakt derselben Datei)
if sudo wg show "${WG_IFACE}" >/dev/null 2>&1; then
  say "Interface ${WG_IFACE} läuft – stoppe es zuerst..."
  sudo wg-quick down "${CONF_PATH}" || true
fi

# Jetzt starten – direkt mit deinem Pfad
if ! sudo wg-quick up "${CONF_PATH}"; then
  ERR=$?
  # Rechte zurücksetzen, damit Web-UI weiterarbeiten kann
  sudo chmod 666 "${CONF_PATH}"
  say "Fehler: wg-quick up fehlgeschlagen (Code ${ERR})."
  exit $ERR
fi

# Rechte zurück auf 666 (kompatibel mit deinem Web-Addon)
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
