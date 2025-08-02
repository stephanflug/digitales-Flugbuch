#!/bin/bash

set -e

echo "Flugbuch Viewer mit lighttpd und Admin-Webinterface wird installiert..."

# 0. Installationsverzeichnis festlegen
INSTALLDIR="/opt/FlugbuchViewer"
sudo mkdir -p "$INSTALLDIR"
sudo chown $USER:$USER "$INSTALLDIR"

# 1. Prüfen, ob Desktop-Umgebung installiert ist
if ! dpkg -l | grep -q raspberrypi-ui-mods; then
  echo "Desktop-Umgebung nicht gefunden. Installiere minimale Desktop-Oberfläche..."
  sudo apt update
  sudo apt install --no-install-recommends -y raspberrypi-ui-mods lxsession lxde
fi

# 2. Pakete installieren
sudo apt update
sudo apt install -y xserver-xorg x11-xserver-utils xinit openbox chromium-browser xdotool lighttpd python3

# 3. lighttpd CGI aktivieren
sudo lighttpd-enable-mod cgi
sudo systemctl restart lighttpd

# 4. Konfigurationsdatei für die Kiosk-URL im INSTALLDIR
CONFIGFILE="$INSTALLDIR/kiosk_url.txt"
if [ ! -f "$CONFIGFILE" ]; then
  echo "http://example.com" > "$CONFIGFILE"
  echo "Konfigurationsdatei $CONFIGFILE angelegt."
fi

# 5. Kiosk-Startskript ins INSTALLDIR
KIOSKSH="$INSTALLDIR/kiosk.sh"
cat << EOS > "$KIOSKSH"
#!/bin/bash
URL=\$(cat "$CONFIGFILE")
chromium-browser --noerrdialogs --disable-infobars --kiosk "\$URL"
EOS
chmod +x "$KIOSKSH"
echo "Kiosk-Startskript $KIOSKSH angelegt."

# 6. Openbox Autostart auf das neue Skript anpassen
AUTOSTART="/home/pi/.config/openbox/autostart"
mkdir -p "$(dirname "$AUTOSTART")"
if ! grep -q "$KIOSKSH" "$AUTOSTART" 2>/dev/null; then
  echo "$KIOSKSH &" >> "$AUTOSTART"
  echo "Autostart für Kiosk aktualisiert."
fi

# 7. Automatisches Starten von X (TTY1)
PROFILE="/home/pi/.bash_profile"
if ! grep -q "startx" "$PROFILE" 2>/dev/null; then
  echo '
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  startx
fi' >> "$PROFILE"
  echo "Automatischer X-Start hinzugefügt."
fi

# 8. CGI-Skripte für Admin-Funktionen (nutzen INSTALLDIR)
sudo mkdir -p /usr/lib/cgi-bin

# 8a. URL speichern
sudo tee /usr/lib/cgi-bin/seturl.py > /dev/null << EOF
#!/usr/bin/env python3
import cgi
form = cgi.FieldStorage()
print("Content-Type: text/html\n")
if "url" in form:
    with open("$CONFIGFILE", "w") as f:
        f.write(form["url"].value)
    print("URL gespeichert! <a href='/'>Zurück</a>")
else:
    print("Fehler: Keine URL übergeben!")
EOF
sudo chmod +x /usr/lib/cgi-bin/seturl.py

# 8b. Browser neustarten
sudo tee /usr/lib/cgi-bin/restart.py > /dev/null << EOF
#!/usr/bin/env python3
import os
print("Content-Type: text/html\n")
os.system("pkill chromium")
os.system("$KIOSKSH &")
print("Browser neugestartet! <a href='/'>Zurück</a>")
EOF
sudo chmod +x /usr/lib/cgi-bin/restart.py

# 8c. Browser reload (F5)
sudo tee /usr/lib/cgi-bin/reload.py > /dev/null << EOF
#!/usr/bin/env python3
import os
print("Content-Type: text/html\n")
os.system("xdotool search --onlyvisible --class chromium key F5")
print("Browser neu geladen! <a href='/'>Zurück</a>")
EOF
sudo chmod +x /usr/lib/cgi-bin/reload.py

# 9. Admin-Oberfläche (index.html)
sudo tee /var/www/html/index.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <title>Flugbuch Viewer Verwaltung</title>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;700&display=swap" rel="stylesheet">
  <style>
    body { background: #181f29; color: #f2f2f2; font-family: 'Roboto', Arial, sans-serif; display: flex; flex-direction: column; align-items: center; min-height: 100vh; margin: 0;}
    .container { background: #232b3a; padding: 2.5rem 2.5rem 1.5rem 2.5rem; border-radius: 1.25rem; margin-top: 3rem; box-shadow: 0 4px 32px rgba(0,0,0,0.22); width: 100%; max-width: 460px;}
    h1 { font-size: 2.1rem; font-weight: 700; margin-bottom: 0.4em; text-align: center; letter-spacing: 0.02em;}
    h2 { font-size: 1.12rem; font-weight: 400; text-align: center; margin-top: 0.4em; margin-bottom: 1.7em; color: #aaa;}
    label { font-weight: 500; margin-bottom: 0.6em; display: block;}
    input[type=text] { width: 95%; padding: 0.5em; font-size: 1em; border-radius: 0.5em; border: none; margin-bottom: 1.3em; outline: none; background: #1b2230; color: #eee;}
    button { background: #448aff; color: #fff; font-size: 1.03em; padding: 0.65em 1.7em; margin: 0.2em 0.3em; border: none; border-radius: 0.5em; font-weight: 600; letter-spacing: 0.01em; cursor: pointer; transition: background 0.2s;}
    button:hover { background: #005ee6;}
    .actions { display: flex; justify-content: center; gap: 0.5em; margin-bottom: 1.2em;}
    .status { text-align: center; margin-top: 0.7em; font-size: 1.07em; color: #60e888;}
    .footer { margin-top: 1.7em; text-align: center; color: #777; font-size: 0.98em;}
    .footer a { color: #448aff; text-decoration: none; margin-left: 0.4em; font-weight: 500;}
    .version { display: block; margin-top: 0.3em; font-size: 0.93em; color: #6da5ff; font-weight: 500;}
  </style>
</head>
<body>
  <div class="container">
    <h1>Flugbuch Viewer</h1>
    <h2>Powerby Ebner Stephan</h2>
    <form action="/cgi-bin/seturl.py" method="post">
      <label for="url">Kiosk-URL ändern:</label>
      <input type="text" id="url" name="url" placeholder="Neue Kiosk-URL eingeben">
      <div class="actions">
        <button type="submit">URL speichern</button>
      </div>
    </form>
    <form action="/cgi-bin/restart.py" method="post" style="display:inline;">
      <button type="submit">Browser neustarten</button>
    </form>
    <form action="/cgi-bin/reload.py" method="post" style="display:inline;">
      <button type="submit">Seite neu laden</button>
    </form>
    <div class="footer">
      <span class="version">Version 1.0</span>
      <span>|</span>
      <a href="https://github.com/stephanflug/digitales-Flugbuch" target="_blank">GitHub: digitales-Flugbuch</a>
      <br>Powerby Ebner Stephan
    </div>
  </div>
</body>
</html>
EOF

sudo chown www-data:www-data /var/www/html/index.html

echo ""
echo "FERTIG! Nach Neustart:"
echo "- HDMI zeigt die Kiosk-URL (aus $CONFIGFILE)."
echo "- Admin-Webseite erreichbar unter: http://<PI-IP>/"
echo "- Dort kann die URL geändert und der Browser neu gestartet werden."
echo ""
echo ">> Bitte jetzt den Raspberry Pi neustarten! <<"
