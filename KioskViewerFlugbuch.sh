#!/bin/bash

set -e

echo "FlugbuchViewer Mini-Kiosk-Installation (systemd)..."

INSTALLDIR="/opt/FlugbuchViewer"
LOGO_URL="https://github.com/stephanflug/digitales-Flugbuch/raw/main/Logo/LOGO.jpg"
LOGO="$INSTALLDIR/LOGO.jpg"
CONFIGFILE="$INSTALLDIR/kiosk_url.txt"
KIOSKSH="$INSTALLDIR/kiosk.sh"
CGIDIR="/usr/lib/cgi-bin/flugbuchviewer"
HTMLDIR="/var/www/html/flugbuchviewer"

# 1. Verzeichnisse & Rechte
sudo mkdir -p "$INSTALLDIR" "$CGIDIR" "$HTMLDIR"
sudo chown pi:pi "$INSTALLDIR"
sudo chown -R www-data:www-data "$HTMLDIR" "$CGIDIR"

# 2. Pakete: NUR das nötigste!
sudo apt update
sudo apt install -y --no-install-recommends xserver-xorg xinit surf unclutter lighttpd python3 fbi wget

# 3. lighttpd & CGI
sudo lighttpd-enable-mod cgi
sudo systemctl restart lighttpd

# 4. Splash-Logo laden
wget -q -O "$LOGO" "$LOGO_URL"
chmod 644 "$LOGO"
chown pi:pi "$LOGO"

# 5. Splash-Skript + root-crontab
SPLASH="$INSTALLDIR/show-logo.sh"
cat <<SPLASH_EOF > "$SPLASH"
#!/bin/bash
sudo fbi -T 1 -d /dev/fb0 -noverbose -a "$LOGO"
sleep 2
sudo killall fbi
SPLASH_EOF
chmod +x "$SPLASH"
chown pi:pi "$SPLASH"
if ! sudo crontab -l 2>/dev/null | grep -q "$SPLASH"; then
  (sudo crontab -l 2>/dev/null; echo "@reboot $SPLASH") | sudo crontab -
fi

# 6. Kiosk-URL Config
if [ ! -f "$CONFIGFILE" ]; then
  echo "http://example.com" > "$CONFIGFILE"
fi

# 7. Kiosk-Startskript (surf, Maus verstecken)
cat <<EOS > "$KIOSKSH"
#!/bin/bash
unclutter -idle 1 &
URL=\$(cat "$CONFIGFILE")
surf -e -s "\$URL"
EOS
chmod +x "$KIOSKSH"
chown pi:pi "$KIOSKSH"

# 8. Systemd-Unit für Autostart (WICHTIG!)
SERVICE=/etc/systemd/system/kiosk.service
sudo tee \$SERVICE > /dev/null <<EOF
[Unit]
Description=FlugbuchViewer Kiosk (surf)
After=network.target

[Service]
User=pi
Environment=DISPLAY=:0
ExecStart=/usr/bin/startx $KIOSKSH
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kiosk.service
sudo systemctl restart kiosk.service

# 9. CGI-Skripte (immer neu schreiben, ausführbar!)
sudo tee "$CGIDIR/seturl.py" > /dev/null << EOF
#!/usr/bin/env python3
import cgi
form = cgi.FieldStorage()
print("Content-Type: text/html\\n")
if "url" in form:
    with open("$CONFIGFILE", "w") as f:
        f.write(form["url"].value)
    print("URL gespeichert! <a href='/flugbuchviewer/'>Zurück</a>")
else:
    print("Fehler: Keine URL übergeben!")
EOF

sudo tee "$CGIDIR/restart.py" > /dev/null << EOF
#!/usr/bin/env python3
import os
print("Content-Type: text/html\\n")
os.system("pkill surf")
os.system("$KIOSKSH &")
print("Browser neugestartet! <a href='/flugbuchviewer/'>Zurück</a>")
EOF

sudo tee "$CGIDIR/reload.py" > /dev/null << EOF
#!/usr/bin/env python3
import os
print("Content-Type: text/html\\n")
os.system("xdotool search --onlyvisible --class surf key F5")
print("Browser neu geladen! <a href='/flugbuchviewer/'>Zurück</a>")
EOF

sudo chmod +x "$CGIDIR/"*.py
sudo chown -R www-data:www-data "$CGIDIR"

# 10. Admin-HTML (im eigenen Ordner!)
sudo tee "$HTMLDIR/index.html" > /dev/null << 'EOF'
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
    <form action="/cgi-bin/flugbuchviewer/seturl.py" method="post">
      <label for="url">Kiosk-URL ändern:</label>
      <input type="text" id="url" name="url" placeholder="Neue Kiosk-URL eingeben">
      <div class="actions">
        <button type="submit">URL speichern</button>
      </div>
    </form>
    <form action="/cgi-bin/flugbuchviewer/restart.py" method="post" style="display:inline;">
      <button type="submit">Browser neustarten</button>
    </form>
    <form action="/cgi-bin/flugbuchviewer/reload.py" method="post" style="display:inline;">
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

sudo chown -R www-data:www-data "$HTMLDIR"

# 11. Hostname
sudo hostnamectl set-hostname FlugbuchViewer
sudo sed -i "s/127.0.1.1.*/127.0.1.1\tFlugbuchViewer/" /etc/hosts

echo ""
echo "-----------------------------------------"
echo "FERTIG! Raspberry Pi ist jetzt ein FLUGBUCH-VIEWER!"
echo "- Bootet NUR surf im Kiosk (kein Desktop, keine Leiste!)."
echo "- Splash-Logo erscheint kurz am HDMI beim Start."
echo "- Admin-Webinterface: http://<PI-IP>/flugbuchviewer/"
echo ""
echo ">> Reboot empfohlen: sudo reboot"
echo "-----------------------------------------"
