#!/bin/bash

set -e

echo "FlugbuchViewer MINI-KIOSK Installation..."

INSTALLDIR="/opt/FlugbuchViewer"
LOGO_URL="https://github.com/stephanflug/digitales-Flugbuch/raw/main/Logo/LOGO.jpg"
LOGO="$INSTALLDIR/LOGO.jpg"
CONFIGFILE="$INSTALLDIR/kiosk_url.txt"
KIOSKSH="$INSTALLDIR/kiosk.sh"
SPLASH="$INSTALLDIR/show-logo.sh"
PROFILE="/home/pi/.bash_profile"

sudo mkdir -p "$INSTALLDIR"
sudo chown pi:pi "$INSTALLDIR"

# 1. Notwendige Pakete installieren
sudo apt update
sudo apt install -y xserver-xorg xinit openbox surf lighttpd python3 fbi wget xdotool

# 2. Splash-Logo herunterladen
sudo wget -q -O "$LOGO" "$LOGO_URL"
sudo chmod 644 "$LOGO"

# 3. Splash-Skript anlegen
cat << SPLASH_EOF > "$SPLASH"
#!/bin/bash
sudo fbi -T 1 -d /dev/fb0 -noverbose -a "$LOGO"
sleep 2
sudo killall fbi
SPLASH_EOF
sudo chmod +x "$SPLASH"

# 4. Splash beim Boot ausführen (Crontab root)
if ! sudo crontab -l 2>/dev/null | grep -q "$SPLASH"; then
  (sudo crontab -l 2>/dev/null; echo "@reboot $SPLASH") | sudo crontab -
fi

# 5. Konfigurationsdatei für die Kiosk-URL
if ! [ -f "$CONFIGFILE" ]; then
  echo "http://example.com" > "$CONFIGFILE"
fi

# 6. Kiosk-Startskript
cat << EOS > "$KIOSKSH"
#!/bin/bash
URL=\$(cat "$CONFIGFILE")
surf "\$URL"
EOS
chmod +x "$KIOSKSH"

# 7. .bash_profile für Autostart (immer frisch überschreiben!)
cat << BASH_EOF > "$PROFILE"
# Starte Kiosk-Browser im X11, wenn am HDMI/TTY1
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  startx "$KIOSKSH"
  logout
fi
BASH_EOF
chown pi:pi "$PROFILE"

# 8. lighttpd & CGI aktivieren
sudo lighttpd-enable-mod cgi
sudo systemctl restart lighttpd

# 9. CGI-Skripte für Admin-Webinterface
sudo mkdir -p /usr/lib/cgi-bin

sudo tee /usr/lib/cgi-bin/seturl.py > /dev/null << EOF
#!/usr/bin/env python3
import cgi
form = cgi.FieldStorage()
print("Content-Type: text/html\\n")
if "url" in form:
    with open("$CONFIGFILE", "w") as f:
        f.write(form["url"].value)
    print("URL gespeichert! <a href='/'>Zurück</a>")
else:
    print("Fehler: Keine URL übergeben!")
EOF
sudo chmod +x /usr/lib/cgi-bin/seturl.py

sudo tee /usr/lib/cgi-bin/restart.py > /dev/null << EOF
#!/usr/bin/env python3
import os
print("Content-Type: text/html\\n")
os.system("pkill surf")
os.system("$KIOSKSH &")
print("Browser neugestartet! <a href='/'>Zurück</a>")
EOF
sudo chmod +x /usr/lib/cgi-bin/restart.py

sudo tee /usr/lib/cgi-bin/reload.py > /dev/null << EOF
#!/usr/bin/env python3
import os
print("Content-Type: text/html\\n")
os.system("xdotool search --onlyvisible --class surf key F5")
print("Browser neu geladen! <a href='/'>Zurück</a>")
EOF
sudo chmod +x /usr/lib/cgi-bin/reload.py

# 10. Admin-Oberfläche (index.html)
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

# Hostname ändern
sudo hostnamectl set-hostname FlugbuchViewer
sudo sed -i "s/127.0.1.1.*/127.0.1.1\tFlugbuchViewer/" /etc/hosts

echo ""
echo "-----------------------------------------"
echo "FERTIG! Raspberry Pi ist jetzt ein FLUGBUCH-VIEWER!"
echo "- Bootet direkt in den Surf-Kiosk-Browser (am HDMI, ohne Desktop!)"
echo "- Splash-Logo erscheint kurz am HDMI beim Start."
echo "- Admin-Webinterface: http://<PI-IP>/"
echo "- Alles kann beliebig oft installiert werden."
echo ""
echo ">> Jetzt Raspberry Pi neu starten! <<"
echo "-----------------------------------------"
