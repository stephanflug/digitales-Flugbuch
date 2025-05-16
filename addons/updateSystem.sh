#!/bin/bash

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

echo "data: Starte Systemupdate..."
echo ""

echo "data: Aktualisiere Paketlisten..."
echo ""
sudo apt update 2>&1 | while IFS= read -r line; do echo "data: $line"; echo ""; done

echo "data: Starte Upgrade der Pakete..."
echo ""
sudo apt upgrade -y 2>&1 | while IFS= read -r line; do echo "data: $line"; echo ""; done

echo "data: Entferne nicht benötigte Pakete..."
echo ""
sudo apt autoremove -y 2>&1 | while IFS= read -r line; do echo "data: $line"; echo ""; done

echo "data: Systemupdate abgeschlossen."
echo ""
