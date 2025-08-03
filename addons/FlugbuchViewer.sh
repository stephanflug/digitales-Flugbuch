#!/bin/bash
set -e

# === 0. Prüfe, ob das ein Pi Zero oder Zero 2 ist ===
IS_ZERO=0
if grep -qi "Zero" /proc/device-tree/model 2>/dev/null; then
  IS_ZERO=1
fi

if [ "$IS_ZERO" = "1" ]; then
  echo "-----------------------------------------------------------------"
  echo "Achtung: Dieses Kiosk-Setup wird auf Raspberry Pi Zero/Zero 2 NICHT unterstützt!"
  echo "Der Browser-Kiosk-Modus ist darauf extrem langsam oder läuft nicht."
  echo "Bitte nutze mindestens ein Raspberry Pi 3, 4 oder höher."
  echo "Setup wird abgebrochen."
  echo "-----------------------------------------------------------------"
  exit 1
fi

USERNAME="flugbuch"
HOME="/home/$USERNAME"

# 1. CGI-Skript installieren
CGI="/usr/lib/cgi-bin/set_kiosk_url.sh"
sudo tee "$CGI" > /dev/null <<EOF
#!/bin/bash

LOGFILE="/var/log/set_kiosk_url.log"
exec > >(tee -a "\$LOGFILE")
exec 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

set -x

echo "data: Starte Kiosk-Setup..."
echo ""

# === Zero/Zero2-Erkennung ===
if grep -qi "Zero" /proc/device-tree/model 2>/dev/null; then
  echo "data: ❗️ Achtung: Pi Zero oder Zero 2 erkannt."
  echo "data: Dieses Kiosk-Setup ist auf Pi Zero/Zero2 nicht unterstützt und wurde nicht installiert."
  echo "data: Bitte verwende einen leistungsfähigeren Pi (z.B. 3, 4, 5)."
  exit 0
fi

CONFIG="/etc/kiosk_url.conf"
URL_DEFAULT="http://localhost:8080"

# POST-Daten einlesen (bis Leerzeile)
POSTDATA=""
while read LINE; do
  [ "\$LINE" == "" ] && break
done
read POSTDATA

parse_post() {
  echo "\$POSTDATA" | sed -n 's/^url=\\(.*\\)\$/\\1/p' | sed 's/%3A/:/g; s/%2F/\\//g'
}
KIOSK_URL=\$(parse_post)
[ -z "\$KIOSK_URL" ] && KIOSK_URL="\$URL_DEFAULT"

echo "data: Setze Kiosk-URL: \$KIOSK_URL"
echo ""
echo "\$KIOSK_URL" | sudo tee "\$CONFIG" > /dev/null

# Browser-Setup für den Kiosk-Modus einrichten:
USERNAME="$USERNAME"
HOME="/home/\$USERNAME"
XINITRC="\$HOME/.xinitrc"

if [ ! -f "\$XINITRC" ]; then
  echo "data: Erstelle ~/.xinitrc für \$USERNAME"
  sudo tee "\$XINITRC" > /dev/null <<EOT
#!/bin/bash
xset -dpms
xset s off
xset s noblank
unclutter &
openbox-session &
chromium-browser --noerrdialogs --disable-infobars --kiosk "\$(cat /etc/kiosk_url.conf)"
EOT
  sudo chmod +x "\$XINITRC"
  sudo chown \$USERNAME:\$USERNAME "\$XINITRC"
fi

# Füge rc.local-Autostart ein, falls nicht vorhanden:
RCLOCAL="/etc/rc.local"
if ! grep -q "startx" "\$RCLOCAL"; then
  sudo sed -i '/^exit 0/i\
sudo -u \$USERNAME startx &\
' "\$RCLOCAL"
fi

echo "data: Kiosk-Modus aktiviert! Neustart nötig."
echo ""
EOF

sudo chmod +x "$CGI"

# 2. HTML-Interface anlegen
HTML="/var/www/html/set_kiosk_url.html"
sudo tee "$HTML" > /dev/null <<'EOF'
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
    .warn { color:#c00; font-weight:bold;}
  </style>
</head>
<body>
<div class="container">
  <h1>Kiosk-Modus aktivieren</h1>
  <div id="zeroWarn" class="warn" style="display:none;">
    ❗️ <b>Dieses Setup funktioniert nicht auf Raspberry Pi Zero / Zero 2!</b><br>
    Bitte nutze einen Pi 3, 4 oder neuer.
  </div>
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
fetch('/proc/device-tree/model')
  .then(r=>r.text())
  .then(t=>{
    if(t.match(/Zero/i)) {
      document.getElementById('zeroWarn').style.display = '';
      document.getElementById('kioskForm').style.display = 'none';
    }
  });
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

# 3. Sudoers-Konfiguration
SUDOERS_LINE="www-data ALL=(ALL) NOPASSWD: /usr/bin/tee, /usr/bin/chmod, /usr/bin/chown, /bin/sed"
if ! sudo grep -qF "$SUDOERS_LINE" /etc/sudoers; then
  echo "$SUDOERS_LINE" | sudo tee -a /etc/sudoers > /dev/null
fi

# 4. Button in index.html einfügen
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''set_kiosk_url.html'\''">Kiosk-Modus aktivieren</button>'
if ! sudo grep -q "set_kiosk_url.html" "$INDEX_HTML"; then
  echo "Füge Kiosk-Modus-Button zur index.html hinzu..."
  sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML"
fi

# 5. Pakete für Kiosk-Modus installieren
sudo apt update
sudo apt install --no-install-recommends -y xserver-xorg x11-xserver-utils xinit openbox chromium-browser unclutter

echo ""
echo "Fertig! Kiosk-Setup wurde installiert."
echo "Öffne im Browser: http://<IP>/set_kiosk_url.html"
echo ""
echo "Trage die gewünschte URL ein, dann nach dem nächsten Neustart startet dein Pi im Kiosk-Browser."
