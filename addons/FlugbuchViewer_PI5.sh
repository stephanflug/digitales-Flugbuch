#!/bin/bash
set -euo pipefail

USERNAME="flugbuch"
USER_HOME="/home/$USERNAME"
SELF_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# === 0) Nur Raspberry Pi 5 erlauben ===
MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
if [[ -z "$MODEL" ]] || [[ "$MODEL" != *"Raspberry Pi 5"* ]]; then
  echo "-----------------------------------------------------------------"
  echo "Abbruch: Dieses Kiosk-Setup ist NUR für Raspberry Pi 5 erlaubt."
  echo "Gefundenes Modell: ${MODEL:-unbekannt}"
  echo "Script wird gelöscht."
  echo "-----------------------------------------------------------------"
  rm -f -- "$SELF_PATH" || true
  exit 1
fi

echo "OK: Raspberry Pi 5 erkannt: $MODEL"

# 1) Pakete installieren
sudo apt update
sudo apt install --no-install-recommends -y \
  xserver-xorg x11-xserver-utils xinit openbox unclutter fbi \
  lighttpd curl

# Chromium robust installieren (Name variiert)
if ! command -v chromium-browser >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1; then
  sudo apt install -y chromium-browser || sudo apt install -y chromium
fi

# 1b) HDMI robust für Pi5 (1080p60)
CFG="/boot/firmware/config.txt"
if [ -f "$CFG" ]; then
  sudo cp "$CFG" "$CFG.bak.$(date +%Y%m%d_%H%M%S)"
  set_cfg() {
    local key="$1" val="$2"
    if sudo grep -qE "^${key}=" "$CFG"; then
      sudo sed -i "s|^${key}=.*|${key}=${val}|" "$CFG"
    else
      echo "${key}=${val}" | sudo tee -a "$CFG" >/dev/null
    fi
  }
  set_cfg "hdmi_force_hotplug" "1"
  set_cfg "hdmi_group" "2"
  set_cfg "hdmi_mode" "82"
  set_cfg "disable_overscan" "1"
fi

# 2) Autologin tty1
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF

# 3) Watchdog-Skript
WATCHDOG="$USER_HOME/kiosk_watchdog.sh"
sudo tee "$WATCHDOG" > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
export DISPLAY=:0
URL="$(cat /etc/kiosk_url.conf)"
LOGFILE="/var/log/kiosk_browser.log"

BROWSER="$(command -v chromium-browser || command -v chromium || true)"
if [ -z "$BROWSER" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Chromium nicht gefunden" >> "$LOGFILE"
  exit 1
fi

while true; do
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starte Chromium ($URL)" >> "$LOGFILE"
  "$BROWSER" --noerrdialogs --disable-infobars --kiosk "$URL" >> "$LOGFILE" 2>&1 &
  CHR_PID=$!

  while kill -0 $CHR_PID 2>/dev/null; do
    if ! curl -fsS --max-time 5 "$URL" >/dev/null; then
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] Seite nicht erreichbar, Browser wird neugestartet" >> "$LOGFILE"
      kill $CHR_PID || true
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

sudo touch /var/log/kiosk_browser.log
sudo chown $USERNAME:$USERNAME /var/log/kiosk_browser.log
sudo chmod 664 /var/log/kiosk_browser.log

# 4) .xinitrc
XINITRC="$USER_HOME/.xinitrc"
sudo tee "$XINITRC" > /dev/null <<EOF
#!/bin/bash
if [ -f "/opt/boot/flugbuch.png" ]; then
  fbi -T 1 -a /opt/boot/flugbuch.png &
  sleep 4
  killall fbi || true
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

# 5) .bash_profile
BASH_PROFILE="$USER_HOME/.bash_profile"
sudo tee "$BASH_PROFILE" > /dev/null <<'EOF'
if [ -z "$SSH_CONNECTION" ] && [ "$(tty)" = "/dev/tty1" ]; then
  if ! pgrep -f kiosk_watchdog.sh >/dev/null; then
    startx
  fi
fi
EOF
sudo chown $USERNAME:$USERNAME "$BASH_PROFILE"

# Default URL falls nicht vorhanden
if [ ! -f /etc/kiosk_url.conf ]; then
  echo "http://localhost:1880/viewerAT" | sudo tee /etc/kiosk_url.conf >/dev/null
fi

# 6) CGI set_kiosk_url.sh
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

echo "data: Starte Kiosk-Setup..."
echo ""

MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
if [[ -z "$MODEL" ]] || [[ "$MODEL" != *"Raspberry Pi 5"* ]]; then
  echo "data: Abbruch: Nur Raspberry Pi 5 unterstützt."
  echo "data: Gefunden: ${MODEL:-unbekannt}"
  exit 0
fi

CONFIG="/etc/kiosk_url.conf"
URL_DEFAULT="http://localhost:1880/viewerAT"
POSTDATA=$(cat)
parse_post() {
  echo "$POSTDATA" | sed -n 's/^url=\(.*\)$/\1/p' | sed 's/%3A/:/g; s/%2F/\//g'
}
KIOSK_URL=$(parse_post)
[ -z "$KIOSK_URL" ] && KIOSK_URL="$URL_DEFAULT"

echo "data: Setze Kiosk-URL: $KIOSK_URL"
echo ""
echo "$KIOSK_URL" | sudo tee "$CONFIG" > /dev/null

echo "data: Kiosk-URL gesetzt. Nach Reboot aktiv."
echo ""
EOF
sudo chmod +x "$CGI"

# 7) CGI Loganzeige
CGI_LOG="/usr/lib/cgi-bin/kiosk_log.sh"
sudo tee "$CGI_LOG" > /dev/null <<'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""
tail -n 200 /var/log/kiosk_browser.log 2>/dev/null || echo "Noch keine Logdatei gefunden."
EOF
sudo chmod +x "$CGI_LOG"

# 8) HTML-Interface anlegen (mit Log-Funktion, Pi5 Style wie Original)
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
  <h1>Kiosk-Modus (Pi5)</h1>
  <form id="kioskForm">
    <label for="url">URL f&uuml;r den Kiosk-Browser (z.B. http://localhost:1880/viewerAT):</label><br>
    <input type="text" id="url" name="url" value="http://localhost:1880/viewerAT" /><br>
    <button type="submit">Kiosk-URL setzen</button>
  </form>
  <pre id="log">Status: Noch keine Aktion durchgef&uuml;hrt&period;</pre>
  <button onclick="kioskLog();return false;" style="margin-top:18px;">Log anzeigen</button>
  <div id="kioskLog" class="logblock"></div>
  <a href="index.html" class="back-to-home">Zur&uuml;ck zur Startseite</a>
  <div class="footer-note">Powered by Ebner Stephan</div>
  <div class="license-info">
    <p>Dieses Projekt steht unter der <a href="https://github.com/stephanflug/digitales-Flugbuch/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">MIT-Lizenz</a>.</p>
  </div>
</div>

<script>
document.getElementById('kioskForm').onsubmit = function(e) {
  e.preventDefault();
  let url = document.getElementById('url').value;
  const log = document.getElementById('log');
  log.textContent = 'Kiosk-URL wird gesetzt...\n';

  const xhr = new XMLHttpRequest();
  xhr.open('POST', '/cgi-bin/set_kiosk_url.sh', true);
  xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
  xhr.onreadystatechange = function() {
    if (xhr.readyState === 3 || xhr.readyState === 4) {
      log.textContent += xhr.responseText;
      log.scrollTop = log.scrollHeight;
    }
  };
  xhr.send('url=' + encodeURIComponent(url));
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

# 9) sudoers
SUDOERS_LINE="www-data ALL=(ALL) NOPASSWD: /usr/bin/tee, /usr/bin/chmod, /usr/bin/chown, /bin/sed, /usr/bin/tail"
if ! sudo grep -qF "$SUDOERS_LINE" /etc/sudoers; then
  echo "$SUDOERS_LINE" | sudo tee -a /etc/sudoers > /dev/null
fi

# 10) Button in index.html
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''set_kiosk_url.html'\''">Kiosk-Modus</button>'
if [ -f "$INDEX_HTML" ] && ! sudo grep -q "set_kiosk_url.html" "$INDEX_HTML"; then
  TMP_FILE="$(mktemp)"
  awk -v link="$LINK" '
    /<div class="button-container">/ { in_block=1 }
    in_block && /<\/div>/ && !inserted {
      print "        " link
      inserted=1
    }
    { print }
  ' "$INDEX_HTML" > "$TMP_FILE"
  sudo mv "$TMP_FILE" "$INDEX_HTML"
fi

echo ""
echo "Fertig! Pi5-Kiosk-Setup wurde installiert."
echo "Monitor an HDMI0 (Port nahe USB-C), dann Neustart."
echo "Öffne im Browser: http://<IP>/set_kiosk_url.html"
