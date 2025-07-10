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

# 1) Lese die gesamte POST-Payload
POST_DATA=$(cat)

# 2) URL-Dekodierung
urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

DECODED=$(urldecode "$POST_DATA")

# 3) Aktion extrahieren (start|stop|update)
ACTION=$(printf '%s\n' "$DECODED" | sed -n 's/.*action=\([^&]*\).*/\1/p')

# 4) Konfig-Text extrahieren (alles nach "config=")
CONFIG_CONTENT=$(printf '%s\n' "$DECODED" | sed -n 's/.*config=\(.*\)/\1/p')

# Hilfsfunktion für HTML-Antwort mit Debug-Ausgabe
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
    # Führe wg-quick mit voller Ausgabe aus
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
      sudo chmod 600 "$WG_CONF"
      html_response "Konfiguration gespeichert." "$OUTPUT"
    else
      html_response "Keine Konfigurationsdaten übermittelt." ""
    fi
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

# 5. HTML-Datei speichern
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
      box-sizing: border-box;
    }
    .container {
      background-color: #ffffff;
      padding: 30px;
      border-radius: 12px;
      box-shadow: 0 6px 16px rgba(0, 0, 0, 0.15);
      width: 100%;
      max-width: 800px;
      text-align: center;
    }
    h1 {
      font-size: 30px;
      color: #333;
      margin-bottom: 20px;
    }
    form {
      margin-top: 20px;
    }
    button {
      background-color: #4CAF50;
      color: white;
      padding: 10px 20px;
      border: none;
      border-radius: 8px;
      cursor: pointer;
      font-size: 16px;
      transition: background-color 0.3s ease, transform 0.3s ease;
      margin: 5px;
    }
    button:hover {
      background-color: #45a049;
      transform: scale(1.05);
    }
    textarea {
      width: 100%;
      height: 200px;
      font-family: monospace;
      font-size: 14px;
      padding: 10px;
      border-radius: 8px;
      border: 1px solid #ccc;
      margin-top: 10px;
    }
    .back-to-home {
      background-color: #2196F3;
      color: white;
      padding: 12px 20px;
      border: none;
      border-radius: 8px;
      font-size: 16px;
      cursor: pointer;
      text-decoration: none;
      display: inline-block;
      margin-top: 20px;
      transition: background-color 0.3s ease, transform 0.3s ease;
    }
    .back-to-home:hover {
      background-color: #1976D2;
      transform: scale(1.05);
    }
    .footer-note {
      margin-top: 20px;
      font-size: 14px;
      color: #888;
    }
    .license-info {
      margin-top: 30px;
      font-size: 14px;
      color: #555;
      border-top: 1px solid #ddd;
      padding-top: 15px;
    }
    .license-info a {
      color: #333;
      text-decoration: none;
    }
    .license-info a:hover {
      text-decoration: underline;
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

# 6. www-data darf wg-quick ohne Passwort ausführen
SUDO_LINE="www-data ALL=(ALL) NOPASSWD: /usr/bin/wg-quick"
if ! sudo grep -qF "$SUDO_LINE" /etc/sudoers; then
  echo "data: Sudoers-Regel wird hinzugefügt..."
  echo "$SUDO_LINE" | sudo tee -a /etc/sudoers > /dev/null
fi

# 7. WireGuard-Link zur index.html hinzufügen, falls noch nicht vorhanden
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''wireguard.html'\''">WireGuard</button>'
if ! grep -q "wireguard.html" "$INDEX_HTML"; then
  echo "data: Füge WireGuard-Link zur index.html hinzu..."
  sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML"
fi

echo ""
echo "data: Fertig! Öffne im Browser: http://<IP>/wireguard.html"
echo ""
