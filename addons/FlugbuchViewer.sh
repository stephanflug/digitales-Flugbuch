#!/bin/bash
set -e

USERNAME="flugbuch"
HOME="/home/$USERNAME"

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

# 1. Pakete für Kiosk-Modus und Splashscreen installieren
sudo apt update
sudo apt install --no-install-recommends -y \
  xserver-xorg x11-xserver-utils xinit openbox chromium-browser unclutter fbi \
  lighttpd

# 2. Autologin für flugbuch auf tty1 einrichten
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF

# 3. Watchdog-Skript für Chromium-Kiosk anlegen (mit HTTP-Check!)
WATCHDOG="$HOME/kiosk_watchdog.sh"
sudo tee "$WATCHDOG" > /dev/null <<'EOF'
#!/bin/bash
export DISPLAY=:0
URL="$(cat /etc/kiosk_url.conf)"
LOGFILE="/var/log/kiosk_browser.log"

while true; do
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starte Chromium ($URL)" >> "$LOGFILE"
  chromium-browser --noerrdialogs --disable-infobars --kiosk "$URL" >> "$LOGFILE" 2>&1 &
  CHR_PID=$!

  # Prüfe alle 10 Sekunden, ob die Seite erreichbar ist
  while kill -0 $CHR_PID 2>/dev/null; do
    if ! curl -s --head --max-time 5 "$URL" | grep -q "200 OK"; then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] Seite nicht erreichbar, Browser wird neugestartet" >> "$LOGFILE"
      kill $CHR_PID
      sleep 2
      break
    fi
    sleep 10
  done

  sleep 5
done
EOF
sudo chmod +x "$WATCHDOG"
sudo chown $USERNAME:$USERNAME "$WATCHDOG"

# 3b. Logfile für Watchdog anlegen (Rechte setzen, falls noch nicht vorhanden)
sudo touch /var/log/kiosk_browser.log
sudo chown $USERNAME:$USERNAME /var/log/kiosk_browser.log
sudo chmod 664 /var/log/kiosk_browser.log

# 4. .xinitrc für Splash-Logo + Watchdog anlegen
XINITRC="$HOME/.xinitrc"
sudo tee "$XINITRC" > /dev/null <<EOF
#!/bin/bash
# Splash-Logo anzeigen (Logo als /opt/boot/flugbuch.png)
if [ -f "/opt/boot/flugbuch.png" ]; then
  fbi -T 1 -a /opt/boot/flugbuch.png &
  sleep 4
  killall fbi
fi
xset -dpms
xset s off
xset s noblank
unclutter &
openbox-session &
/home/$USERNAME/kiosk_watchdog.sh
EOF
sudo chmod +x "$XINITRC"
sudo chown $USERNAME:$USERNAME "$XINITRC"

# 5. .bash_profile für Autostart auf tty1 (NICHT bei SSH)
BASH_PROFILE="$HOME/.bash_profile"
sudo tee "$BASH_PROFILE" > /dev/null <<EOF
# Starte nur auf tty1 (HDMI), nicht bei SSH
if [ -z "\$SSH_CONNECTION" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  if ! pgrep -f kiosk_watchdog.sh >/dev/null; then
    startx
  fi
fi
EOF
sudo chown $USERNAME:$USERNAME "$BASH_PROFILE"

# 6. CGI-Skript für Web-URL-Änderung installieren
CGI="/usr/lib/cgi-bin/set_kiosk_url.sh"
sudo tee "$CGI" > /dev/null <<'EOF'
#!/bin/bash

LOGFILE="/var/log/set_kiosk_url.log"
exec > >(tee -a "$LOGFILE")
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
  echo "data: Achtung: Pi Zero oder Zero 2 erkannt."
  echo "data: Dieses Kiosk-Setup ist auf Pi Zero/Zero2 nicht unterstützt und wurde nicht installiert."
  echo "data: Bitte verwende einen leistungsfähigeren Pi (z.B. 3, 4, 5)."
  exit 0
fi

CONFIG="/etc/kiosk_url.conf"
URL_DEFAULT="http://localhost:1880/viewerAT"

# POST-Daten einlesen
POSTDATA=$(cat)

parse_post() {
  echo "$POSTDATA" | sed -n 's/^url=\(.*\)$/\1/p' | sed 's/%3A/:/g; s/%2F/\//g'
}
KIOSK_URL=$(parse_post)
[ -z "$KIOSK_URL" ] && KIOSK_URL="$URL_DEFAULT"

echo "data: Setze Kiosk-URL: $KIOSK_URL"
echo ""
echo "$KIOSK_URL" | sudo tee "$CONFIG" > /dev/null

echo "data: Kiosk-URL gesetzt. Nach dem nächsten Reboot startet Chromium mit dieser URL."
echo ""
EOF
sudo chmod +x "$CGI"

# 7. CGI-Skript für Loganzeige
CGI_LOG="/usr/lib/cgi-bin/kiosk_log.sh"
sudo tee "$CGI_LOG" > /dev/null <<'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""
tail -n 200 /var/log/kiosk_browser.log 2>/dev/null || echo "Noch keine Logdatei gefunden."
EOF
sudo chmod +x "$CGI_LOG"

# 8. HTML-Interface anlegen (mit Log-Funktion!)
HTML="/var/www/html/set_kiosk_url.html"
sudo tee "$HTML" > /dev/null <<'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Kiosk-Modus Setup</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      background: url('flyer.png') no-repeat center center fixed;
      background-size: cover;
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
      box-shadow: 0 6px 16px rgba(0,0,0,0.15);
      width: 100%;
      max-width: 800px;
      text-align: center;
    }
    h1 {
      font-size: 30px;
      color: #333;
      margin-bottom: 20px;
    }
    label, input, button {
      font-size: 16px;
      margin: 10px 0;
    }
    input[type=text] {
      width: 80%;
      padding: 7px;
      border-radius: 6px;
      border: 1px solid #ccc;
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
      margin-top: 10px;
    }
    button:hover {
      background-color: #45a049;
      transform: scale(1.05);
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
    .license-info p {
      margin: 0;
    }
    .license-info a {
      color: #333;
      text-decoration: none;
    }
    .license-info a:hover {
      text-decoration: underline;
    }
    pre {
      text-align:left;
      background:#e8f0fe;
      padding:10px;
      border-radius:8px;
      margin-top:15px;
      height:120px;
      overflow:auto;
    }
    .warn { color:#c00; font-weight:bold; }
    .logblock {
      margin-top:10px;
      background:#111;
      color:#fffd;
      padding:8px;
      font-size:12px;
      border-radius:8px;
      max-height:300px;
      overflow:auto;
    }
  </style>
</head>
<body>
<div class="container">
  <h1>Kiosk-Modus</h1>
  <div id="zeroWarn" class="warn" style="display:none;">
    <b>Dieses Setup funktioniert nicht auf Raspberry Pi Zero / Zero 2!</b><br>
    Bitte nutze einen Pi 3, 4 oder neuer.
  </div>
  <form id="kioskForm">
    <label for="url">URL für den Kiosk-Browser (z.B. http://localhost:1880/viewerAT):</label><br>
    <input type="text" id="url" name="url"
      value="http://localhost:1880/viewerAT" /><br>
    <button type="submit">Kiosk-URL setzen</button>
  </form>
  <pre id="log">Status: Noch keine Aktion durchgeführt.</pre>
  <button onclick="kioskLog();return false;" style="margin-top:18px;">Log anzeigen</button>
  <div id="kioskLog" class="logblock"></div>
  <a href="index.html" class="back-to-home">Zurück zur Startseite</a>
  <div class="footer-note">Powered by Ebner Stephan</div>
  <div class="license-info">
    <p>Dieses Projekt steht unter der <a href="https://github.com/stephanflug/digitales-Flugbuch/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">MIT-Lizenz</a>.</p>
  </div>
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

function kioskLog() {
  fetch('/cgi-bin/kiosk_log.sh')
    .then(r => r.text())
    .then(txt => document.getElementById('kioskLog').textContent = txt)
    .catch(e => document.getElementById('kioskLog').textContent = 'Fehler beim Log-Download: ' + e);
}
</script>
</body>
</html>
EOF

# 9. Sudoers-Konfiguration
SUDOERS_LINE="www-data ALL=(ALL) NOPASSWD: /usr/bin/tee, /usr/bin/chmod, /usr/bin/chown, /bin/sed, /usr/bin/tail"
if ! sudo grep -qF "$SUDOERS_LINE" /etc/sudoers; then
  echo "$SUDOERS_LINE" | sudo tee -a /etc/sudoers > /dev/null
fi

# 10. Button in index.html einfügen
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''set_kiosk_url.html'\''">Kiosk-Modus</button>'
if ! sudo grep -q "set_kiosk_url.html" "$INDEX_HTML"; then
  echo "Füge Kiosk-Modus-Button zur index.html hinzu..."
  sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML"
fi

echo ""
echo "Fertig! Kiosk-Setup wurde installiert. Bitte das ganze System neustarten!"
echo "Öffne im Browser: http://<IP>/set_kiosk_url.html"
