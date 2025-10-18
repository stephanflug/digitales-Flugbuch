#!/bin/bash
# WireGuard Web-Installer (DNS-sicher & CGI-tauglich)
# - Fixiert DNS VOR apt update (wichtig!)
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

# ---------- DNS VOR apt update sicherstellen ----------
sse "Prüfe/konfiguriere DNS..."
has_resolved=false
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^systemd-resolved\.service'; then
  log "systemd-resolved erkannt → aktivieren"
  sudo systemctl enable --now systemd-resolved >>"$LOGFILE" 2>&1 || true
  has_resolved=true
fi

fix_dns() {
  if $has_resolved && systemctl is-active --quiet systemd-resolved; then
    # /etc/resolv.conf auf systemd-resolved linken
    if [ ! -L /etc/resolv.conf ] || [ "$(readlink -f /etc/resolv.conf)" != "/run/systemd/resolve/resolv.conf" ]; then
      log "Link /etc/resolv.conf -> /run/systemd/resolve/resolv.conf setzen"
      sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    fi
    # Optionale DNS-Setzung (nicht kritisch, falls DHCP schon DNS liefert)
    if command -v resolvectl >/dev/null 2>&1; then
      IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '/ dev /{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
      if [ -n "${IFACE:-}" ]; then
        sudo resolvectl dns "$IFACE" 1.1.1.1 8.8.8.8 >>"$LOGFILE" 2>&1 || true
        sudo resolvectl domain "$IFACE" "~." >>"$LOGFILE" 2>&1 || true
      fi
    fi
  else
    # Kein lokaler Stub → echte Nameserver in /etc/resolv.conf eintragen,
    # sofern nicht bereits brauchbare Nameserver vorhanden sind
    if ! grep -Eq '^\s*nameserver\s+(?!127\.0\.0\.1|127\.0\.0\.53)\S+' /etc/resolv.conf 2>/dev/null; then
      log "Schreibe echte Nameserver in /etc/resolv.conf"
      printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" | sudo tee /etc/resolv.conf >/dev/null
    else
      log "/etc/resolv.conf enthält bereits brauchbare Nameserver"
    fi
    # Optional: persistente DNS für dhcpcd (falls vorhanden)
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^dhcpcd\.service'; then
      if ! grep -q '^\s*interface\s\+wlan0' /etc/dhcpcd.conf 2>/dev/null || \
         ! grep -q '^\s*static\s\+domain_name_servers=' /etc/dhcpcd.conf 2>/dev/null; then
        log "Persistente DNS in /etc/dhcpcd.conf für wlan0 setzen"
        sudo bash -c 'cat >>/etc/dhcpcd.conf <<EOF

# DNS fest für WLAN (vom WireGuard-Setup-Script gesetzt)
interface wlan0
static domain_name_servers=1.1.1.1 8.8.8.8
EOF'
        sudo systemctl restart dhcpcd >>"$LOGFILE" 2>&1 || true
      fi
    fi
  fi
}
fix_dns

# kurzer, nicht-fataler DNS-Selbsttest
if ! getent hosts api.github.com >/dev/null 2>&1; then
  sse "WARNUNG: DNS-Auflösung für api.github.com fehlgeschlagen. Prüfe WLAN/AP-DNS."
  log "WARN: getent hosts api.github.com fehlgeschlagen"
else
  log "DNS-Check ok (api.github.com auflösbar)"
fi

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
      <button type="submit" name="action" value="autostart-off">Autostart deaktivieren</button>
      <button type="submit" name="action" value="autostart-status">Autostart-Status anzeigen</button>
    </form>

    <a href="index.html" class="back-to-home">Zur&uuml;ck zur Startseite</a>

    <div class="footer-note">Powered by Ebner Stephan</div>
    <div class="license-info">
      <p>Dieses Projekt steht unter der <a href="https://github.com/stephanflug/digitales-Flugbuch/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">MIT-Lizenz</a>.</p>
    </div>
  </div>

  <script>
    window.addEventListener('DOMContentLoaded', () => {
      fetch('/cgi-bin/get_wg_conf.sh')
        .then(r => r.ok ? r.text() : Promise.reject(r.statusText))
        .then(cfg => document.querySelector('textarea[name="config"]').value = cfg)
        .catch(err => console.error('Konfig nicht geladen:', err));
    });
  </script>
</body>
</html>
EOF

# ---------- Sudoers (sauber via /etc/sudoers.d) ----------
sse "Setze Sudo-Rechte für www-data..."
SUDO_DROPIN="/etc/sudoers.d/wireguard-web"
sudo bash -c "cat > '$SUDO_DROPIN' <<'EOSUDO'
www-data ALL=(ALL) NOPASSWD: /usr/bin/wg-quick, /bin/systemctl
Defaults:www-data !requiretty
EOSUDO"
# Syntax prüfen
sudo visudo -cf "$SUDO_DROPIN" >>"$LOGFILE" 2>&1 || { sse "FEHLER: /etc/sudoers.d/wireguard-web ungültig"; exit 1; }

# ---------- Button auf index.html hinzufügen (falls vorhanden) ----------
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''wireguard.html'\''">WireGuard</button>'
if [ -f "$INDEX_HTML" ]; then
  if ! grep -q "wireguard.html" "$INDEX_HTML"; then
    sse "Ergänze Link auf wireguard.html in index.html..."
    if grep -q '<div class="button-container">' "$INDEX_HTML"; then
      sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ { /<\/div>/ i \\        $LINK }" "$INDEX_HTML"
    else
      printf '\n<div class="button-container">\n  %s\n</div>\n' "$LINK" | sudo tee -a "$INDEX_HTML" >/dev/null
    fi
  fi
fi

# ---------- systemd-Service für Autostart ----------
sse "Erzeuge/aktiviere systemd-Service für Autostart..."
SERVICE_FILE="/etc/systemd/system/wg-custom.service"
if [ ! -f "$SERVICE_FILE" ]; then
  sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=WireGuard VPN (custom config)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/wg-quick up /opt/digitalflugbuch/data/DatenBuch/wg0.conf
ExecStop=/usr/bin/wg-quick down /opt/digitalflugbuch/data/DatenBuch/wg0.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
fi
sudo systemctl daemon-reload >>"$LOGFILE" 2>&1
sudo systemctl enable wg-custom.service >>"$LOGFILE" 2>&1 || true

sse "Fertig! Öffne im Browser: http://<IP>/wireguard.html"
log "=== DONE WireGuard-Setup ==="
