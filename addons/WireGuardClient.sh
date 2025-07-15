#!/bin/bash

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

echo "data: Starte Installation von WireGuard..."
echo ""

# 1. WireGuard installieren
sudo apt update
sudo apt install -y wireguard resolvconf

# 2. Konfiguration vorbereiten
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
if [ ! -f "$CONF_PATH" ]; then
  echo "data: Erstelle leere WireGuard-Konfiguration..."
  sudo mkdir -p "$(dirname "$CONF_PATH")"
  sudo touch "$CONF_PATH"
  sudo chown www-data:www-data "$CONF_PATH"
  sudo chmod 666 "$CONF_PATH"
fi

# 3. CGI-Skript: control
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
    OUTPUT=$(sudo wg-quick up "$WG_CONF" 2>&1)
    RET=$?
    if [ $RET -eq 0 ]; then
      html_response "WireGuard aktiviert." "$OUTPUT"
    else
      html_response "Fehler beim Starten von WireGuard (Code $RET):" "$OUTPUT"
    fi
    ;;
  stop)
    OUTPUT=$(sudo wg-quick down "$WG_CONF" 2>&1)
    RET=$?
    if [ $RET -eq 0 ]; then
      html_response "WireGuard deaktiviert." "$OUTPUT"
    else
      html_response "Fehler beim Stoppen von WireGuard (Code $RET):" "$OUTPUT"
    fi
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
    OUTPUT=$(sudo systemctl enable wg-custom.service 2>&1)
    html_response "Autostart aktiviert." "$OUTPUT"
    ;;
  autostart-off)
    OUTPUT=$(sudo systemctl disable wg-custom.service 2>&1)
    html_response "Autostart deaktiviert." "$OUTPUT"
    ;;
  autostart-status)
    OUTPUT=$(systemctl is-enabled wg-custom.service 2>&1)
    html_response "Autostart-Status:" "$OUTPUT"
    ;;
  *)
    html_response "Unbekannte Aktion: '$ACTION'." ""
    ;;
esac
EOF
sudo chmod +x "$CGI_SCRIPT"

# 4. CGI-Skript: get current config
GET_CONF="/usr/lib/cgi-bin/get_wg_conf.sh"
sudo tee "$GET_CONF" > /dev/null << 'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""
cat /opt/digitalflugbuch/data/DatenBuch/wg0.conf
EOF
sudo chmod +x "$GET_CONF"

# 5. HTML-Datei
HTML_PATH="/var/www/html/wireguard.html"
sudo tee "$HTML_PATH" > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>WireGuard Steuerung</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      background-color: #f4f7fc;
      margin: 0;
      padding: 0;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
    }
    .container {
      background-color: #ffffff;
      padding: 30px;
      border-radius: 12px;
      box-shadow: 0 6px 16px rgba(0, 0, 0, 0.15);
      max-width: 800px;
      width: 100%;
      text-align: center;
    }
    h1 {
      font-size: 28px;
      margin-bottom: 20px;
    }
    form {
      margin: 15px 0;
    }
    button {
      background-color: #4CAF50;
      color: white;
      padding: 10px 20px;
      border: none;
      border-radius: 8px;
      cursor: pointer;
      font-size: 16px;
      margin: 5px;
      transition: 0.3s;
    }
    button:hover {
      background-color: #45a049;
      transform: scale(1.05);
    }
    textarea {
      width: 100%;
      height: 200px;
      font-family: monospace;
      padding: 10px;
      border-radius: 8px;
      border: 1px solid #ccc;
      margin-top: 10px;
    }
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

# 6. Sudoers-Regeln
SUDO_LINE1="www-data ALL=(ALL) NOPASSWD: /usr/bin/wg-quick"
SUDO_LINE2="www-data ALL=(ALL) NOPASSWD: /bin/systemctl"

if ! sudo grep -qF "$SUDO_LINE1" /etc/sudoers; then
  echo "$SUDO_LINE1" | sudo tee -a /etc/sudoers > /dev/null
fi
if ! sudo grep -qF "$SUDO_LINE2" /etc/sudoers; then
  echo "$SUDO_LINE2" | sudo tee -a /etc/sudoers > /dev/null
fi

# 7. Button auf index.html hinzufügen
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''wireguard.html'\''">WireGuard</button>'
if ! grep -q "wireguard.html" "$INDEX_HTML"; then
  echo "data: Füge WireGuard-Link zur index.html hinzu..."
  sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML"
fi

# 8. systemd-Service für Autostart erstellen
SERVICE_FILE="/etc/systemd/system/wg-custom.service"
if [ ! -f "$SERVICE_FILE" ]; then
  echo "data: Erstelle systemd-Service für WireGuard Autostart..."
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

  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable wg-custom.service
fi

echo ""
echo "data: Fertig! Öffne im Browser: http://<IP>/wireguard.html"
echo ""
