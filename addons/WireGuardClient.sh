#!/bin/bash

# Server-Sent Events Header
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

echo "data: Starte Installation des WireGuard-Clients..."
echo ""

# Schritt 1: System aktualisieren
echo "data: Aktualisiere Paketliste..."
echo ""
apt update -y && echo "data: Paketliste erfolgreich aktualisiert." || echo "data: Fehler beim Aktualisieren der Paketliste."
echo ""

# Schritt 2: WireGuard-Tools installieren
echo "data: Installiere WireGuard-Client-Komponenten..."
echo ""
apt install -y wireguard-tools resolvconf && echo "data: WireGuard-Client installiert." || echo "data: Fehler bei der Installation."
echo ""

# Schritt 3: Überprüfen ob wg-quick verfügbar ist
if command -v wg-quick >/dev/null 2>&1; then
    echo "data: wg-quick ist verfügbar – WireGuard-Client bereit."
else
    echo "data: Fehler: wg-quick wurde nicht gefunden."
fi
echo ""

# Schritt 4: Konfiguration speichern im gewünschten Ordner
WG_CONF="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"

if [ ! -f "$WG_CONF" ]; then
    echo "data: Erstelle Beispielkonfiguration wg0.conf in /opt/digitalflugbuch/data/DatenBuch/ ..."
    echo ""

    cat <<EOF > "$WG_CONF"
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <SERVER_IP>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    chmod 600 "$WG_CONF"
    echo "data: Konfigurationsdatei gespeichert unter: $WG_CONF"
else
    echo "data: Konfigurationsdatei existiert bereits – übersprungen."
fi
echo ""

# Schritt 5: Abschluss
echo "data: WireGuard-Client-Installation abgeschlossen."
echo ""
