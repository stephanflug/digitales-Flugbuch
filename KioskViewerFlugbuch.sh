#!/bin/bash

set -e

echo "FlugbuchViewer Installation (SELF-HEALING)..."

INSTALLDIR="/opt/FlugbuchViewer"
LOGO_URL="https://github.com/stephanflug/digitales-Flugbuch/raw/main/Logo/LOGO.jpg"
LOGO="$INSTALLDIR/LOGO.jpg"
CONFIGFILE="$INSTALLDIR/kiosk_url.txt"
KIOSKSH="$INSTALLDIR/kiosk.sh"
SPLASH="$INSTALLDIR/show-logo.sh"
AUTOSTART="/home/pi/.config/openbox/autostart"
PROFILE="/home/pi/.bash_profile"
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"

echo "Prüfe auf Desktopumgebung..."
if ! dpkg -l | grep -q raspberrypi-ui-mods; then
  echo "-> Es wurde ein Lite-System erkannt! Installiere kompletten Desktop... (kann 10-15 Minuten dauern)"
  sudo apt update
  sudo apt install -y raspberrypi-ui-mods lxsession lxde xserver-xorg xinit openbox lightdm policykit-1
  # Den Pi-User zur lightdm-Gruppe hinzufügen, falls nötig:
  sudo usermod -a -G lightdm pi
  # Sicherstellen, dass das Xauthority-Verzeichnis existiert
  sudo mkdir -p /home/pi/.Xauthority
  sudo chown pi:pi /home/pi/.Xauthority
  echo "-> Desktop-Umgebung installiert."
fi

sudo mkdir -p "$INSTALLDIR"
sudo chown pi:pi "$INSTALLDIR"

# 1. Desktop-Umgebung sicherstellen
if ! dpkg -l | grep -q raspberrypi-ui-mods; then
  echo "Desktop-Umgebung nicht gefunden. Installiere..."
  sudo apt update
  sudo apt install --no-install-recommends -y raspberrypi-ui-mods lxsession lxde
fi

# 1. Setze Boot-Target auf grafische Oberfläche (Desktop)
sudo systemctl set-default graphical.target

# 2. LightDM-Konfiguration für Autologin als User "pi"
if [ -f /etc/lightdm/lightdm.conf ]; then
  sudo sed -i '/^autologin-user=/d' /etc/lightdm/lightdm.conf
  sudo sed -i '/^\[Seat:\*\]/a autologin-user=pi' /etc/lightdm/lightdm.conf
else
  sudo tee /etc/lightdm/lightdm.conf > /dev/null <<EOF
[Seat:*]
autologin-user=pi
EOF
fi

# 3. Desktop-Pakete (ggf. erneut) installieren/reparieren
sudo apt update
sudo apt install --reinstall -y raspberrypi-ui-mods lxsession lxde xserver-xorg xinit openbox lightdm

echo "Desktop-Start und Autologin für pi wurden fest eingestellt."

# 2. Nötige Pakete
sudo apt update
sudo apt install -y xserver-xorg x11-xserver-utils xinit openbox chromium-browser xdotool lighttpd python3 fbi wget lsb-release

# 3. lighttpd & CGI
sudo lighttpd-enable-mod cgi
sudo systemctl restart lighttpd

# 4. Kiosk-URL config (immer überschreiben, falls leer)
if ! grep -q "http" "$CONFIGFILE" 2>/dev/null; then
  echo "http://example.com" > "$CONFIGFILE"
  echo "Konfigurationsdatei $CONFIGFILE gesetzt."
fi

# 5. Logo laden (immer neu, falls leer)
sudo wget -q -O "$LOGO" "$LOGO_URL"
sudo chmod 644 "$LOGO"
echo "Logo aktualisiert: $LOGO"

# 6. Splash-Skript anlegen (wird immer neu geschrieben)
cat << SPLASH_EOF > "$SPLASH"
#!/bin/bash
sudo fbi -T 1 -d /dev/fb0 -noverbose -a "$LOGO"
sleep 2
sudo killall fbi
SPLASH_EOF
sudo chmod +x "$SPLASH"

if ! sudo crontab -l 2>/dev/null | grep -q "$SPLASH"; then
  (sudo crontab -l 2>/dev/null; echo "@reboot $SPLASH") | sudo crontab -
  echo "Boot-Splash in Root-Crontab eingetragen."
fi

# 7. Desktop Autologin + Boot zum Desktop erzwingen
sudo raspi-config nonint do_boot_behaviour B4 || true
if ! grep -q "autologin-user=pi" "$LIGHTDM_CONF" 2>/dev/null; then
  sudo sed -i '/^\[Seat:\*\]/a autologin-user=pi' "$LIGHTDM_CONF" 2>/dev/null || true
fi

# 8. Kiosk-Startskript schreiben (immer frisch!)
cat << EOS > "$KIOSKSH"
#!/bin/bash
for i in {1..20}; do
  if pgrep -x Xorg >/dev/null; then break; fi
  sleep 1
done
sleep 2
URL=\$(cat "$CONFIGFILE")
chromium-browser --noerrdialogs --disable-infobars --kiosk "\$URL"
EOS
chmod +x "$KIOSKSH"

# 9. Openbox Autostart überschreiben (immer frisch, alles andere raus!)
mkdir -p "$(dirname "$AUTOSTART")"
echo "$KIOSKSH &" > "$AUTOSTART"
chmod 644 "$AUTOSTART"

# 10. .bash_profile für Autostart
if ! grep -q "startx" "$PROFILE" 2>/dev/null; then
  echo '
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  startx
fi' >> "$PROFILE"
fi

# 11. CGI-Skripte (immer neu schreiben)
sudo mkdir -p /usr/lib/cgi-bin

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

sudo tee /usr/lib/cgi-bin/restart.py > /dev/null << EOF
#!/usr/bin/env python3
import os
print("Content-Type: text/html\n")
os.system("pkill chromium")
os.system("$KIOSKSH &")
print("Browser neugestartet! <a href='/'>Zurück</a>")
EOF
sudo chmod +x /usr/lib/cgi-bin/restart.py

sudo tee /usr/lib/cgi-bin/reload.py > /dev/null << EOF
#!/usr/bin/env python3
import os
print("Content-Type: text/html\n")
os.system("xdotool search --onlyvisible --class chromium key F5")
print("Browser neu geladen! <a href='/'>Zurück</a>")
EOF
sudo chmod +x /usr/lib/cgi-bin/reload.py

# 12. Admin-Oberfläche (immer neu schreiben)
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

# Hostname ändern (immer frisch setzen!)
sudo hostnamectl set-hostname FlugbuchViewer
sudo sed -i "s/127.0.1.1.*/127.0.1.1\tFlugbuchViewer/" /etc/hosts

echo ""
echo "-----------------------------------------"
echo "FERTIG! Raspberry Pi ist jetzt ein FLUGBUCH-VIEWER!"
echo "- Bootet direkt auf Desktop und Kiosk-Browser."
echo "- Splash-Logo erscheint kurz am HDMI beim Start."
echo "- Admin-Webinterface: http://<PI-IP>/"
echo "- Alles kann beliebig oft installiert werden."
echo ""
echo ">> Bitte Raspberry Pi jetzt neustarten! <<"
echo "-----------------------------------------"
