#!/bin/bash

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

echo "data: Starte Systemupdate..."
echo ""

# Paketlisten aktualisieren
echo "data: Aktualisiere Paketlisten..."
echo ""
if sudo apt update 2>&1 | while IFS= read -r line; do echo "data: $line"; echo ""; done; then
    echo "data: Paketlisten erfolgreich aktualisiert."
else
    echo "data: Fehler beim Aktualisieren der Paketlisten."
fi
echo ""

# Upgrade aller Pakete
echo "data: Starte Upgrade der Pakete..."
echo ""
if sudo apt upgrade -y 2>&1 | while IFS= read -r line; do echo "data: $line"; echo ""; done; then
    echo "data: Upgrade erfolgreich abgeschlossen."
else
    echo "data: Fehler beim Upgrade der Pakete."
fi
echo ""

# Autoremove
echo "data: Entferne nicht benötigte Pakete..."
echo ""
if sudo apt autoremove -y 2>&1 | while IFS= read -r line; do echo "data: $line"; echo ""; done; then
    echo "data: Autoremove abgeschlossen."
else
    echo "data: Fehler beim Entfernen von Paketen."
fi
echo ""

echo "data: Systemupdate abgeschlossen."
echo ""
