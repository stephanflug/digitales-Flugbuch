#!/bin/bash
# WireGuard Web-Installer (DNS-sicher & CGI-tauglich)
# - Installiert WireGuard
# - Richtet CGI-Steuerung & HTML-Seite ein
# - Loggt nach /var/log/wireguard_setup.log (Fallback /tmp)

set -Eeuo pipefail

# ---------- CGI-Header (Server-Sent Events) ----------
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

# ---------- Logging vorbereiten (nur ins Log, nicht ins SSE) ----------
LOGFILE="/var/log/wireguard_setup.log"
if ! sudo touch "$LOGFILE" 2>/dev/null; then
  LOGFILE="/tmp/wireguard_setup.log"
  touch "$LOGFILE"
fi
exec 3>>"$LOGFILE"

sse() { printf 'data: %s\n\n' "$*"; }
log() { printf '%s %s\n' "$(date -Iseconds)" "$*" >&3; }

trap 'sse "FEHLER: Installation abgebrochen (Zeile $LINENO). Siehe Log: $LOGFILE"; exit 1' ERR

sse "Starte Installation von WireGuard..."
log "=== START WireGuard-Setup ==="

# ---------- System aktualisieren ----------
sse "Aktualisiere Paketquellen..."
log "apt update"
sudo apt update >>"$LOGFILE" 2>&1

# ---------- WireGuard installieren ----------
sse "Installiere WireGuard..."
log "apt install -y wireguard"
sudo apt install -y wireguard >>"$LOGFILE" 2>&1

# ---------- WireGuard Konfigurationsdatei vorbereiten ----------
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
if [ ! -f "$CONF_PATH" ]; then
  sse "Erstelle leere WireGuard-Konfiguration..."
  log "mkdir -p $(dirname "$CONF_PATH")"
  sudo mkdir -p "$(dirname "$CONF_PATH")" >>"$LOGFILE" 2>&1
  sudo touch "$CONF_PATH" >>"$LOGFILE" 2>&1
  sudo chown www-data:www-data "$CONF_PATH" >>"$LOGFILE" 2>&1 || true
  sudo chmod 666 "$CONF_PATH" >>"$LOGFILE" 2>&1 || true
else
  log "WireGuard-Konfiguration existiert bereits: $CONF_PATH"
fi

# ---------- CGI-Skript: Steuerung ----------
sse "Installiere CGI-Steuerung..."
CGI_SCRIPT="/usr/lib/cgi-bin/wireguard_control.sh"
sudo tee "$CGI_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
echo "Content-type: text/html"
echo ""

WG_CONF="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
POST_DATA=$(cat)

urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

DECODED=$(urldecode "$POST_DATA")
ACTION=$(printf '%s\n' "$DECODED" | sed -n 's/.*action=\([^&]*\).*/\1/p')
CONFIG_CONTENT="${DECODED#*config=}"
CONFIG_CONTENT="${CONFIG_CONTENT%%&action=*}"

html_response() {
  cat <<HTML
<html>
  <body>
    <h2>$1</h2>
    <pre style="background:#f0f0f0;padding:10px;border-radius:4px;">$2</pre>
    <a href="/wireguard.html">Zur&uuml;ck zur Startseite</a>
  </body>
</html>
HTML
}

case "$ACTION" in
  start)
    OUTPUT=$(sudo /usr/bin/wg-quick up "$WG_CONF" 2>&1)
    RET=$?
    if [ $RET -eq 0 ]; then html_response "WireGuard aktiviert." "$OUTPUT"
    else html_response "Fehler beim Starten von WireGuard (Code $RET):" "$OUTPUT"; fi
    ;;
  stop)
    OUTPUT=$(sudo /usr/bin/wg-quick down "$WG_CONF" 2>&1)
    RET=$?
    if [ $RET -eq 0 ]; then html_response "WireGuard deaktiviert." "$OUTPUT"
    else html_response "Fehler beim Stoppen von WireGuard (Code $RET):" "$OUTPUT"; fi
    ;;
  update)
    if [ -n "$CONFIG_CONTENT" ]; then
      OUTPUT=$(printf '%s\n' "$CONFIG_CONTENT" | sudo tee "$WG_CONF" 2>&1)
      sudo chmod 666 "$WG_CONF"
      html_response "Konfiguration gespeichert." "$OUTPUT"
    else
      html_response "Keine Konfigurationsdaten übermittelt." ""
    fi
    ;;
  autostart-on)
    OUTPUT=$(sudo /bin/systemctl enable wg-custom.service 2>&1)
    html_response "Autostart aktiviert." "$OUTPUT"
    ;;
  autostart-off)
    OUTPUT=$(sudo /bin/systemctl disable wg-custom.service 2>&1)
    html_response "Autostart deaktiviert." "$OUTPUT"
    ;;
  autostart-status)
    OUTPUT=$(/bin/systemctl is-enabled wg-custom.service 2>&1)
    html_response "Autostart-Status:" "$OUTPUT"
    ;;
  *)
    html_response "Unbekannte Aktion: '$ACTION'." ""
    ;;
esac
EOF
sudo chmod +x "$CGI_SCRIPT" >>"$LOGFILE" 2>&1

# ---------- CGI-Skript: aktuelle Konfiguration ausgeben ----------
GET_CONF="/usr/lib/cgi-bin/get_wg_conf.sh"
sudo tee "$GET_CONF" > /dev/null << 'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""
cat /opt/digitalflugbuch/data/DatenBuch/wg0.conf
EOF
sudo chmod +x "$GET_CONF" >>"$LOGFILE" 2>&1

# ---------- HTML-Seite ----------
sse "Erzeuge HTML-Steuerseite..."
HTML_PATH="/var/www/html/wireguard.html"
sudo tee "$HTML_PATH" > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>WireGuard Steuerung</title>
  <style>
    body { font-family: Arial, sans-serif; background-color: #f4f7fc; margin:0; padding:0;
           display:flex; justify-content:center; align-items:center; height:100vh; }
    .container { background:#fff; padding:30px; border-radius:12px;
                 box-shadow:0 6px 16px rgba(0,0,0,0.15); max-width:800px; width:100%; text-align:center; }
    h1 { font-size:28px; margin-bottom:20px; }
    form { margin:15px 0; }
    button { background:#4CAF50; color:#fff; padding:10px 20px; border:none; border-radius:8px;
             cursor:pointer; font-size:16px; margin:5px; transition:0.3s; }
    button:hover { background:#45a049; transform:scale(1.05); }
    textarea { width:100%; height:200px; font-family:monospace; padding:10px;
               border-radius:8px; border:1px solid #ccc; margin-top:10px; }
    .footer-note, .license-info { margin-top:20px; font-size:14px; color:#666; }
    .license-info a { color:#4CAF50; text-decoration:none; } .license-info a:hover { text-decoration:underline; }
  </style>
</head>
<body>
  <div class="container">
    <h1>WireGuard Client Steuerung</h1>

    <form method="post" action="/cgi-bin/wireguard_control.sh">
      <button type="submit" name="action" value="start">Verbindung aktivieren</button>
      <button type="submit" name="action" value="stop">Verbindung deaktivieren</button>
    </form>

    <form method="post" action="/cgi-bin/wireguard_control.sh">
      <h2>Konfiguration bearbeiten</h2>
      <textarea name="config" placeholder="[Interface] …"></textarea><br>
      <button type="submit" name="action" value="update">Konfiguration speichern</button>
    </form>

    <form method="post" action="/cgi-bin/wireguard_control.sh">
      <h2>Autostart-Verwaltung</h2>
      <button type="submit" name="action" value="autostart-on">Autostart aktivieren</button>
      <button type="submit" name="action" value="autostart-off">Autostart
