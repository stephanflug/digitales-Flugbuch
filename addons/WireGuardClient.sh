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
sudo apt install -y wireguard

# 2. Konfiguration vorbereiten
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
if [ ! -f "$CONF_PATH" ]; then
  echo "data: Erstelle leere WireGuard-Konfiguration..."
  sudo touch "$CONF_PATH"
  sudo chmod 600 "$CONF_PATH"
fi

# 3. CGI-Skript speichern
CGI_SCRIPT="/usr/lib/cgi-bin/wireguard_control.sh"
sudo tee "$CGI_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash

echo "Content-type: text/html"
echo ""

WG_CONF="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"

read -n "$CONTENT_LENGTH" POST_DATA

ACTION=$(echo "$POST_DATA" | grep -oP '(?<=action=)[^&]*')
NEW_CONF=$(echo "$POST_DATA" | grep -oP '(?<=config=).*' | sed 's/%0D%0A/\n/g' | sed 's/+/ /g' | sed 's/%3A/:/g' | sed 's/%2F/\//g')

html_response() {
  echo "<html><body><h2>$1</h2><a href=\"/html/wireguard.html\">Zur&uuml;ck</a></body></html>"
}

case "$ACTION" in
  start)
    sudo wg-quick up "$WG_CONF" > /dev/null 2>&1 && html_response "WireGuard aktiviert." || html_response "Fehler beim Starten von WireGuard."
    ;;
  stop)
    sudo wg-quick down "$WG_CONF" > /dev/null 2>&1 && html_response "WireGuard deaktiviert." || html_response "Fehler beim Stoppen von WireGuard."
    ;;
  update)
    if [ -n "$NEW_CONF" ]; then
      echo -e "$NEW_CONF" | sudo tee "$WG_CONF" > /dev/null
      sudo chmod 600 "$WG_CONF"
      html_response "Konfiguration gespeichert."
    else
      html_response "Keine Konfigurationsdaten übermittelt."
    fi
    ;;
  *)
    html_response "Unbekannte Aktion."
    ;;
esac
EOF

sudo chmod +x "$CGI_SCRIPT"

# 4. HTML-Datei speichern
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
      <textarea name="config" placeholder="[Interface] ...">[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <SERVER_IP>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25</textarea>
      <br>
      <button type="submit" name="action" value="update">Konfiguration speichern</button>
    </form>

    <a href="index.html" class="back-to-home">Zur&uuml;ck zur Startseite</a>

    <div class="footer-note">Powered by Ebner Stephan</div>
    <div class="license-info">
      <p>Dieses Projekt steht unter der <a href="https://github.com/stephanflug/digitales-Flugbuch/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">MIT-Lizenz</a>.</p>
    </div>
  </div>
</body>
</html>
EOF

# 5. www-data darf wg-quick ohne Passwort ausführen
SUDO_LINE="www-data ALL=(ALL) NOPASSWD: /usr/bin/wg-quick"
if ! sudo grep -qF "$SUDO_LINE" /etc/sudoers; then
  echo "data: Sudoers-Regel wird hinzugefügt..."
  echo "$SUDO_LINE" | sudo tee -a /etc/sudoers > /dev/null
fi

# 6. WireGuard-Link zur index.html hinzufügen, falls noch nicht vorhanden
INDEX_HTML="/var/www/html/index.html"
LINK_CODE='<button type="button" onclick="window.location.href='\''wireguard.html'\''">WireGuard</button>'

if ! grep -q "wireguard.html" "$INDEX_HTML"; then
  echo "data: Füge WireGuard-Link zur index.html hinzu..."

  # Direkt vor </div> der Button-Container einfügen
  sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK_CODE
  }" "$INDEX_HTML"
fi

echo ""
echo "data: Fertig! Öffne im Browser: http://<IP>/html/wireguard.html"
echo ""
