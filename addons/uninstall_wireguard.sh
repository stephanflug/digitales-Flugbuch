#!/bin/bash

echo "Starte Deinstallation von WireGuard und Entfernen aller zugehörigen Komponenten..."

# 1. Stoppe und deaktiviere systemd-Service
SERVICE_FILE="/etc/systemd/system/wg-custom.service"
if systemctl is-enabled --quiet wg-custom.service; then
  echo "→ Stoppe WireGuard systemd-Service..."
  sudo systemctl stop wg-custom.service
  sudo systemctl disable wg-custom.service
fi
if [ -f "$SERVICE_FILE" ]; then
  echo "→ Lösche systemd-Service-Datei..."
  sudo rm -f "$SERVICE_FILE"
  sudo systemctl daemon-reload
fi

# 2. Entferne sudoers-Zeilen
echo "→ Entferne sudoers-Einträge für www-data..."
sudo sed -i '/www-data ALL=(ALL) NOPASSWD: \/usr\/bin\/wg-quick/d' /etc/sudoers
sudo sed -i '/www-data ALL=(ALL) NOPASSWD: \/bin\/systemctl/d' /etc/sudoers

# 3. Entferne CGI-Skripte
echo "→ Entferne CGI-Skripte..."
sudo rm -f /usr/lib/cgi-bin/wireguard_control.sh
sudo rm -f /usr/lib/cgi-bin/get_wg_conf.sh

# 4. Entferne WireGuard-HTML-Seite
echo "→ Entferne HTML-Webinterface..."
sudo rm -f /var/www/html/wireguard.html

# 5. Entferne WireGuard-Konfigurationsdatei
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
if [ -f "$CONF_PATH" ]; then
  echo "→ Lösche Konfigurationsdatei: $CONF_PATH"
  sudo rm -f "$CONF_PATH"
fi

# 6. Entferne Link von index.html
INDEX_HTML="/var/www/html/index.html"
if grep -q "wireguard.html" "$INDEX_HTML"; then
  echo "→ Entferne WireGuard-Button aus index.html..."
  sudo sed -i "/wireguard\.html/d" "$INDEX_HTML"
fi

echo ""
echo "✅ WireGuard-Funktionen wurden entfernt."

# 8. Lösche dieses Skript selbst
SCRIPT_PATH="$(realpath "$0")"
echo "→ Lösche das Skript selbst: $SCRIPT_PATH"
rm -- "$SCRIPT_PATH"
