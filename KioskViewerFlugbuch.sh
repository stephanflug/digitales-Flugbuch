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
<html lang="de">
<head>
    <meta charset="utf-8">
    <title>Flugbuch Viewer Verwaltung</title>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;700&display=swap" rel="stylesheet">
    <style>
        body {
            background: #181f29;
            color: #f2f2f2;
            font-family: 'Roboto', Arial, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            min-height: 100vh;
            margin: 0;
        }
        .container {
            background: #232b3a;
            padding: 2.5rem 2.5rem 1.5rem 2.5rem;
            border-radius: 1.25rem;
            margin-top: 3rem;
            box-shadow: 0 4px 32px rgba(0,0,0,0.22);
            width: 100%;
            max-width: 460px;
        }
        h1 {
            font-size: 2.1rem;
            font-weight: 700;
            margin-bottom: 0.4em;
            text-align: center;
            letter-spacing: 0.02em;
        }
        h2 {
            font-size: 1.12rem;
            font-weight: 400;
            text-align: center;
            margin-top: 0.4em;
            margin-bottom: 1.7em;
            color: #aaa;
        }
        label {
            font-weight: 500;
            margin-bottom: 0.6em;
            display: block;
        }
        input[type=text] {
            width: 95%;
            padding: 0.5em;
            font-size: 1em;
            border-radius: 0.5em;
            border: none;
            margin-bottom: 1.3em;
            outline: none;
            background: #1b2230;
            color: #eee;
        }
        button {
            background: #448aff;
            color: #fff;
            font-size: 1.03em;
            padding: 0.65em 1.7em;
            margin: 0.2em 0.3em;
            border: none;
            border-radius: 0.5em;
            font-weight: 600;
            letter-spacing: 0.01em;
            cursor: pointer;
            transition: background 0.2s;
        }
        button:hover {
            background: #005ee6;
        }
        .actions {
            display: flex;
            justify-content: center;
            gap: 0.5em;
            margin-bottom: 1.2em;
        }
        .status {
            text-align: center;
            margin-top: 0.7em;
            font-size: 1.07em;
            color: #60e888;
        }
        .footer {
            margin-top: 1.7em;
            text-align: center;
            color: #777;
            font-size: 0.98em;
        }
        .footer a {
            color: #448aff;
            text-decoration: none;
            margin-left: 0.4em;
            font-weight: 500;
        }
        .version {
            display: block;
            margin-top: 0.3em;
            font-size: 0.93em;
            color: #6da5ff;
            font-weight: 500;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Flugbuch Viewer</h1>
        <h2>Powerby Ebner Stephan</h2>
        <form method="POST">
            <label for="url">Kiosk-URL ändern:</label>
            <input type="text" id="url" name="url" value="{{ url }}" placeholder="Neue Kiosk-URL eingeben">
            <div class="actions">
                <button type="submit">URL speichern</button>
                <button type="submit" formaction="/restart">Browser neustarten</button>
                <button type="submit" formaction="/refresh">Seite neu laden</button>
            </div>
        </form>
        <div class="status">
            Aktuelle Kiosk-URL:<br>
            <b>{{ url }}</b>
        </div>
    </div>
    <div class="footer">
        <span class="version">Version 1.0</span>
        <span>|</span>
        <a href="https://github.com/stephanflug/digitales-Flugbuch" target="_blank">GitHub: digitales-Flugbuch</a>
    </div>
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
