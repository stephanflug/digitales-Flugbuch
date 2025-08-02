#!/bin/bash

# --- Raspberry Pi Kiosk-Modus Setup ---

set -e

echo "Starte Installation für den Kiosk-Modus..."

# 1. System aktualisieren & benötigte Pakete installieren
sudo apt update
sudo apt install --no-install-recommends -y xserver-xorg x11-xserver-utils xinit openbox chromium-browser

# 2. Kiosk-URL Konfigurationsdatei anlegen (falls nicht vorhanden)
CONFIGFILE="/home/pi/kiosk_url.txt"
if [ ! -f "$CONFIGFILE" ]; then
  echo "http://192.168.1.100:8080" > "$CONFIGFILE"
  echo "Konfigurationsdatei $CONFIGFILE angelegt."
fi

# 3. Kiosk-Startskript anlegen
KIOSKSH="/home/pi/kiosk.sh"
cat << 'EOF' > "$KIOSKSH"
#!/bin/bash
URL=$(cat /home/pi/kiosk_url.txt)
chromium-browser --noerrdialogs --disable-infobars --kiosk "$URL"
EOF
chmod +x "$KIOSKSH"
echo "Kiosk-Startskript $KIOSKSH angelegt."

# 4. Openbox Autostart anpassen
AUTOSTART="/home/pi/.config/openbox/autostart"
mkdir -p "$(dirname "$AUTOSTART")"
if ! grep -q "$KIOSKSH" "$AUTOSTART" 2>/dev/null; then
  echo "$KIOSKSH &" >> "$AUTOSTART"
  echo "Autostart aktualisiert."
fi

# 5. Automatisch X-Server starten (nur auf TTY1)
PROFILE="/home/pi/.bash_profile"
if ! grep -q "startx" "$PROFILE" 2>/dev/null; then
  echo '
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  startx
fi' >> "$PROFILE"
  echo "Automatischen X-Start hinzugefügt."
fi

echo ""
echo "Setup abgeschlossen!"
echo "Passe die URL in $CONFIGFILE an, falls gewünscht."
echo "Beim nächsten Neustart startet der Pi direkt im Kiosk-Modus mit der gewählten URL."
