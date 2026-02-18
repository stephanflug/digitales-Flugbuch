#!/bin/bash
set -euo pipefail

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

echo "data: Starte FlugbuchViewer PI5 Installation..."
echo ""

USERNAME="flugbuch"
USER_HOME="/home/$USERNAME"
SELF_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# === 0) Nur Raspberry Pi 5 erlauben ===
MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
if [[ -z "$MODEL" ]] || [[ "$MODEL" != *"Raspberry Pi 5"* ]]; then
  echo "data: -----------------------------------------------------------------"
  echo "data: Abbruch: Dieses Kiosk-Setup ist NUR für Raspberry Pi 5 erlaubt."
  echo "data: Gefundenes Modell: ${MODEL:-unbekannt}"
  echo "data: Script wird gelöscht."
  echo "data: -----------------------------------------------------------------"
  rm -f -- "$SELF_PATH" || true
  exit 1
fi

echo "data: OK: Raspberry Pi 5 erkannt: $MODEL"

# 1) Pakete installieren
sudo apt update
sudo apt install --no-install-recommends -y \
  xserver-xorg xserver-xorg-core xserver-xorg-input-all \
  x11-xserver-utils xinit openbox unclutter fbi \
  lighttpd curl xserver-xorg-legacy xauth dbus-x11

# Auf Pi5 kein fbdev-Xorg-Treiber (verursacht "framebuffer mode"-Fatal)
sudo apt purge -y xserver-xorg-video-fbdev || true

# Xorg/startx auf Pi5 stabilisieren (tty1 kiosk)
sudo tee /etc/X11/Xwrapper.config >/dev/null <<EOF
allowed_users=anybody
needs_root_rights=yes
EOF

# Xorg auf KMS/modesetting für Pi5 festnageln
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/99-pi5-kms.conf >/dev/null <<EOF
Section "Device"
    Identifier "Pi5KMS"
    Driver "modesetting"
    Option "kmsdev" "/dev/dri/card0"
EndSection
EOF

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

# 1c) Benutzerrechte für Grafik-/Input-Stack absichern
sudo usermod -aG video,render,input "$USERNAME" || true

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
export HOME="/home/flugbuch"
export XDG_RUNTIME_DIR="/run/user/1000"
unset DBUS_SESSION_BUS_ADDRESS || true
URL="$(cat /etc/kiosk_url.conf)"
LOGFILE="/var/log/kiosk_browser.log"

# sicherstellen, dass Cache-Verzeichnisse existieren und beschreibbar sind
mkdir -p "$HOME/.cache/chromium" "$HOME/.cache/mesa_shader_cache" "$HOME/.config"

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
# auch für CGI (www-data) lesbar machen
sudo chmod 644 /var/log/kiosk_browser.log

# Rechte auf User-Cache/Config reparieren (wichtig nach früheren Root-Starts)
sudo mkdir -p "$USER_HOME/.cache" "$USER_HOME/.config" "$USER_HOME/.local/share"
sudo chown -R $USERNAME:$USERNAME "$USER_HOME/.cache" "$USER_HOME/.config" "$USER_HOME/.local"

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

# 4b) .xserverrc für stabile Xorg-Initialisierung auf tty1
XSERVER_RC="$USER_HOME/.xserverrc"
sudo tee "$XSERVER_RC" > /dev/null <<'EOF'
#!/bin/sh
exec /usr/lib/xorg/Xorg -nolisten tcp "$@"
EOF
sudo chmod +x "$XSERVER_RC"
sudo chown $USERNAME:$USERNAME "$XSERVER_RC"

# 5) .bash_profile
BASH_PROFILE="$USER_HOME/.bash_profile"
sudo tee "$BASH_PROFILE" > /dev/null <<'EOF'
if [ -z "$SSH_CONNECTION" ] && [ "$(tty)" = "/dev/tty1" ]; then
  if ! pgrep -f kiosk_watchdog.sh >/dev/null; then
    rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true
    startx /home/flugbuch/.xinitrc -- :0 vt1 -keeptty
  fi
fi
EOF
sudo chown $USERNAME:$USERNAME "$BASH_PROFILE"

# Start-URL Datei anlegen (bewusst leer, muss im UI gesetzt werden)
if [ ! -f /etc/kiosk_url.conf ]; then
  : | sudo tee /etc/kiosk_url.conf >/dev/null
fi

# 6) CGI set_kiosk_url.sh
CGI="/usr/lib/cgi-bin/set_kiosk_url.sh"
sudo tee "$CGI" > /dev/null <<'EOF'
#!/bin/bash
LOGFILE="/var/log/set_kiosk_url.log"
# WICHTIG: Debug darf HTTP-Header nicht verschmutzen (sonst ERR_INVALID_RESP hinter Proxy)
exec 3>>"$LOGFILE"
export BASH_XTRACEFD=3
set -x

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

sse() { echo "data: $*"; echo ""; }

sse "Starte Kiosk-Setup..."
MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
if [[ -z "$MODEL" ]] || [[ "$MODEL" != *"Raspberry Pi 5"* ]]; then
  sse "Abbruch: Nur Raspberry Pi 5 unterstützt."
  sse "Gefunden: ${MODEL:-unbekannt}"
  exit 0
fi

CONFIG="/etc/kiosk_url.conf"
POSTDATA=$(cat)
parse_post() {
  raw=$(echo "$POSTDATA" | sed -n 's/^url=\(.*\)$/\1/p')
  raw=${raw//+/ }
  printf '%b' "${raw//%/\\x}"
}
KIOSK_URL=$(parse_post)

if [ -z "$KIOSK_URL" ]; then
  sse "Fehler: Keine URL übergeben. Bitte im UI AT/DE auswählen oder manuell eintragen."
  exit 0
fi

sse "Setze Kiosk-URL: $KIOSK_URL"
echo "$KIOSK_URL" | sudo tee "$CONFIG" > /dev/null

sse "Kiosk-URL gesetzt. Nach Reboot aktiv."
EOF
sudo chmod +x "$CGI"

# 7) CGI Loganzeige
CGI_LOG="/usr/lib/cgi-bin/kiosk_log.sh"
sudo tee "$CGI_LOG" > /dev/null <<'EOF'
#!/bin/bash
echo "Content-type: text/plain"
echo ""
if [ -r /var/log/kiosk_browser.log ]; then
  tail -n 200 /var/log/kiosk_browser.log
else
  echo "Log nicht lesbar oder nicht vorhanden: /var/log/kiosk_browser.log"
  ls -l /var/log/kiosk_browser.log 2>/dev/null || true
fi
EOF
sudo chmod +x "$CGI_LOG"

# 7b) CGI in lighttpd aktivieren (sonst liefert /cgi-bin/* nichts)
sudo lighttpd-enable-mod cgi >/dev/null 2>&1 || true
sudo systemctl restart lighttpd || true

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
  <div style="text-align:left;background:#f7faff;border:1px solid #d8e6ff;border-radius:10px;padding:12px 14px;margin-bottom:14px;">
    <b>Hinweis:</b> Beim <b>ersten Start</b> oder nach einem <b>Update</b> muss die Start-URL gesetzt werden.<br>
    W&auml;hle dazu unten eine Funktion (AT/DE) oder trage eine eigene URL ein.
  </div>

  <form id="kioskForm">
    <label for="preset">Funktion ausw&auml;hlen:</label><br>
    <select id="preset" name="preset" style="width:80%;padding:7px;border-radius:6px;border:1px solid #ccc;">
      <option value="">-- Bitte ausw&auml;hlen --</option>
      <option value="http://localhost:1880/viewerAT">AT (http://localhost:1880/viewerAT)</option>
      <option value="http://localhost:1880/viewerDE">DE (http://localhost:1880/viewerDE)</option>
      <option value="custom">Eigene URL manuell eingeben</option>
    </select><br>

    <label for="url">Start-URL f&uuml;r den Kiosk-Browser:</label><br>
    <input type="text" id="url" name="url" value="" placeholder="z. B. http://localhost:1880/viewerAT" /><br>
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
const preset = document.getElementById('preset');
const urlInput = document.getElementById('url');

preset.addEventListener('change', function () {
  if (this.value === 'custom') {
    urlInput.focus();
    return;
  }
  urlInput.value = this.value || '';
});

document.getElementById('kioskForm').onsubmit = function(e) {
  e.preventDefault();
  const log = document.getElementById('log');

  let url = (urlInput.value || '').trim();
  if (!url) {
    log.textContent = 'Bitte zuerst eine Funktion auswählen (AT/DE) oder eine URL manuell eintragen.\n';
    return;
  }

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
  const box = document.getElementById('kioskLog');
  box.textContent = 'Lade Log...';
  fetch('/cgi-bin/kiosk_log.sh', {cache: 'no-store'})
    .then(r => {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.text();
    })
    .then(txt => box.textContent = txt || 'Log ist leer.')
    .catch(e => box.textContent = 'Fehler beim Log-Download: ' + e + '\nPrüfe: lighttpd cgi Modul aktiv?');
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
echo "data: Fertig! Pi5-Kiosk-Setup wurde installiert."
echo "data: Monitor an HDMI0 (Port nahe USB-C), dann Neustart."
echo "data: Öffne im Browser: http://<IP>/set_kiosk_url.html"
echo ""
