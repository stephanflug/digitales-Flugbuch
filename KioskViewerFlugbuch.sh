#!/bin/bash

# --- Kiosk mit Admin-Webinterface (ohne Port) ---

set -e

echo "Kiosk-Setup mit Admin-Webinterface wird installiert..."

# 1. Pakete installieren
sudo apt update
sudo apt install -y xserver-xorg x11-xserver-utils xinit openbox chromium-browser python3-flask xdotool

# 2. Konfigurationsdatei für die Kiosk-URL
CONFIGFILE="/home/pi/kiosk_url.txt"
if [ ! -f "$CONFIGFILE" ]; then
  echo "http://example.com" > "$CONFIGFILE"
  echo "Konfigurationsdatei $CONFIGFILE angelegt."
fi

# 3. Kiosk-Startskript
KIOSKSH="/home/pi/kiosk.sh"
cat << 'EOF' > "$KIOSKSH"
#!/bin/bash
URL=$(cat /home/pi/kiosk_url.txt)
chromium-browser --noerrdialogs --disable-infobars --kiosk "$URL"
EOF
chmod +x "$KIOSKSH"
echo "Kiosk-Startskript $KIOSKSH angelegt."

# 4. Openbox Autostart
AUTOSTART="/home/pi/.config/openbox/autostart"
mkdir -p "$(dirname "$AUTOSTART")"
if ! grep -q "$KIOSKSH" "$AUTOSTART" 2>/dev/null; then
  echo "$KIOSKSH &" >> "$AUTOSTART"
  echo "Autostart für Kiosk aktualisiert."
fi

# 5. Automatisches Starten von X (TTY1)
PROFILE="/home/pi/.bash_profile"
if ! grep -q "startx" "$PROFILE" 2>/dev/null; then
  echo '
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  startx
fi' >> "$PROFILE"
  echo "Automatischer X-Start hinzugefügt."
fi

# 6. Admin-Webserver (Flask) als /home/pi/admin.py anlegen
ADMINPY="/home/pi/admin.py"
cat << 'EOF' > "$ADMINPY"
from flask import Flask, render_template_string, request, redirect
import os
import subprocess

CONFIGFILE = "/home/pi/kiosk_url.txt"
KIOSK_PROCESS_NAME = "chromium"

app = Flask(__name__)

TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Kiosk Verwaltung</title>
    <style>
        body { font-family: sans-serif; background: #f5f5f5; padding: 30px; }
        input[type=text] { width: 400px; padding: 5px; }
        button { padding: 10px 20px; margin: 5px;}
    </style>
</head>
<body>
    <h2>Kiosk-URL einstellen</h2>
    <form method="POST">
        <input type="text" name="url" value="{{ url }}" placeholder="Neue Kiosk-URL eingeben">
        <button type="submit">URL speichern</button>
    </form>
    <h3>Weitere Aktionen</h3>
    <form method="POST" action="/restart">
        <button type="submit">Browser neustarten</button>
    </form>
    <form method="POST" action="/refresh">
        <button type="submit">Seite aktualisieren (Reload)</button>
    </form>
    <p>Aktuelle URL: <b>{{ url }}</b></p>
</body>
</html>
"""

def get_url():
    if os.path.exists(CONFIGFILE):
        with open(CONFIGFILE) as f:
            return f.read().strip()
    return ""

def set_url(url):
    with open(CONFIGFILE, "w") as f:
        f.write(url.strip())

@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        url = request.form.get("url", "")
        if url:
            set_url(url)
    return render_template_string(TEMPLATE, url=get_url())

@app.route("/restart", methods=["POST"])
def restart():
    os.system(f"pkill {KIOSK_PROCESS_NAME}")
    subprocess.Popen(["/home/pi/kiosk.sh"])
    return redirect("/")

@app.route("/refresh", methods=["POST"])
def refresh():
    os.system("xdotool search --onlyvisible --class chromium key F5")
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
EOF

chmod +x "$ADMINPY"
echo "Admin-Webserver (Flask) wurde als $ADMINPY angelegt."

# 7. Flask-Webserver (Admin-Webinterface) als Root bei Boot starten (Port 80 braucht Root)
if ! sudo crontab -l 2>/dev/null | grep -q "python3 /home/pi/admin.py"; then
  (sudo crontab -l 2>/dev/null; echo "@reboot /usr/bin/python3 /home/pi/admin.py") | sudo crontab -
  echo "Flask-Webserver (Port 80) in Root-Crontab für Autostart eingetragen."
fi

echo ""
echo "FERTIG! Nach Neustart:"
echo "- HDMI zeigt die Kiosk-URL (aus $CONFIGFILE)."
echo "- Admin-Webseite erreichbar unter: http://<PI-IP> (ohne Port!)"
echo "- Dort kann die URL geändert und der Browser neu gestartet werden."
echo ""
echo ">> Bitte jetzt den Raspberry Pi neustarten! <<"
