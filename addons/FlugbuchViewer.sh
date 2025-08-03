#!/bin/bash
set -e

# === 1. CGI-Skript installieren ===
CGI="/usr/lib/cgi-bin/set_kiosk_url.sh"
cat > "$CGI" <<'EOF'
#!/bin/bash
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

set -e

LOGFILE="/var/log/set_kiosk_url.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

CONFIG="/etc/kiosk_url.conf"
URL_DEFAULT="http://localhost:8080"

# POST-Daten einlesen (bis Leerzeile)
POSTDATA=""
while read LINE; do
  [ "$LINE" == "" ] && break
done
read POSTDATA

parse_post() {
  echo "$POSTDATA" | sed -n 's/^url=\(.*\)$/\1/p' | sed 's/%3A/:/g; s/%2F/\//g'
}
KIOSK_URL=$(parse_post)
[ -z "$KIOSK_URL" ] && KIOSK_URL="$URL_DEFAULT"

echo "data: Setze Kiosk-URL: $KIOSK_URL"
echo ""
echo "$KIOSK_URL" | sudo tee "$CONFIG" > /dev/null

# Browser-Setup für den Kiosk-Modus einrichten:
USERNAME="pi"
HOME="/home/$USERNAME"
XINITRC="$HOME/.xinitrc"

if [ ! -f "$XINITRC" ]; then
  echo "data: Erstelle ~/.xinitrc für $USERNAME"
  sudo tee "$XINITRC" > /dev/null <<EOT
#!/bin/bash
xset -dpms
xset s off
xset s noblank
unclutter &
openbox-session &
chromium-browser --noerrdialogs --disable-infobars --kiosk "\$(cat /etc/kiosk_url.conf)"
EOT
  sudo chmod +x "$XINITRC"
  sudo chown $USERNAME:$USERNAME "$XINITRC"
fi

# Füge rc.local-Autostart ein, falls nicht vorhanden:
RCLOCAL="/etc/rc.local"
if ! grep -q "startx" "$RCLOCAL"; then
  sudo sed -i '/^exit 0/i\
sudo -u '"$USERNAME"' startx &\
' "$RCLOCAL"
fi

echo "data: Kiosk-Modus aktiviert! Neustart nötig."
echo ""
EOF

chmod +x "$CGI"

# === 2. HTML-Interface anlegen ===
HTML="/var/www/html/set_kiosk_url.html"
cat > "$HTML" <<'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Kiosk-Modus Setup</title>
  <style>
    body { font-family: Arial,sans-serif; background:#f4f7fc; margin:0; padding:0; }
    .container {
      background:#fff; margin:50px auto; max-width:600px; padding:30px; border-radius:12px;
      box-shadow:0 6px 16px rgba(0,0,0,0.13); text-align:center;
    }
    h1 { font-size:28px; margin-bottom:10px;}
    label, input, button { font-size:16px; margin:10px 0; }
    input[type=text] { width:80%; padding:7px; border-radius:6px; border:1px solid #ccc; }
    button { background:#4CAF50; color:#fff; border:none; border-radius:8px; padding:10px 24px; cursor:pointer;}
    button:hover { background:#388e3c; }
    pre { text-align:left; background:#e8f0fe; padding:10px; border-radius:8px; margin-top:15px; height:120px; overflow:auto; }
  </style>
</head>
<body>
<div class="container">
  <h1>Kiosk-Modus aktivieren</h1>
  <form id="kioskForm">
    <label for="url">URL für den Kiosk-Browser (z.B. http://localhost:8080):</label><br>
    <input type="text" id="url" name="url"
      value="http://localhost:8080" /><br>
    <button type="submit">Kiosk-URL setzen</button>
  </form>
  <pre id="log">Status: Noch keine Aktion durchgeführt.</pre>
  <a href="index.html">Zurück zur Startseite</a>
</div>

<script>
document.getElementById('kioskForm').onsubmit = function(e) {
  e.preventDefault();
  let url = document.getElementById('url').value;
  const log = document.getElementById('log');
  log.textContent = 'Kiosk-URL wird gesetzt...\n';

  const xhr = new XMLHttpRequest();
  xhr.open("POST", "/cgi-bin/set_kiosk_url.sh", true);
  xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
  xhr.onreadystatechange = function() {
    if (xhr.readyState === 3 || xhr.readyState === 4) {
      log.textContent += xhr.responseText;
      log.scrollTop = log.scrollHeight;
    }
  };
  xhr.send("url=" + encodeURIComponent(url));
};
</script>
</body>
</html>
EOF

# === 3. Sudoers-Konfiguration ===
SUDOERS_LINE="www-data ALL=(ALL) NOPASSWD: /usr/bin/tee, /usr/bin/chmod, /usr/bin/chown, /bin/sed"
if ! grep -qF "$SUDOERS_LINE" /etc/sudoers; then
  echo "$SUDOERS_LINE" | sudo tee -a /etc/sudoers > /dev/null
fi

# === 4. Button in index.html einfügen ===
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''set_kiosk_url.html'\''">Kiosk-Modus aktivieren</button>'
if ! grep -q "set_kiosk_url.html" "$INDEX_HTML"; then
  echo "Füge Kiosk-Modus-Button zur index.html hinzu..."
  sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML"
fi

# === 5. Pakete für Kiosk-Modus installieren ===
sudo apt update
sudo apt install --no-install-recommends -y xserver-xorg x11-xserver-utils xinit openbox chromium-browser unclutter

echo ""
echo "Fertig! Kiosk-Setup wurde installiert."
echo "Öffne im Browser: http://<IP>/set_kiosk_url.html"
echo ""
echo "Trage die gewünschte URL ein, dann nach dem nächsten Neustart startet dein Pi im Kiosk-Browser."
