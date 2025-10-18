#!/bin/bash

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

echo "data: Starte SD-Karten-Fehlerprüfung..."
echo ""

# SD-Log auslesen
if command -v journalctl >/dev/null 2>&1; then
    LOG=$(journalctl -k | grep -iE 'mmc|mmcblk')
else
    LOG=$(dmesg | grep -iE 'mmc|mmcblk')
fi

FEHLER=$(echo "$LOG" | grep -iE 'error|fail|io error')

# Ausgabe
if [ -n "$FEHLER" ]; then
    echo "data: Fehler gefunden:"
    echo ""
    echo "$FEHLER" | while IFS= read -r line; do
        echo "data: $line"
    done
else
    echo "data: Keine SD-Karten-Fehler gefunden."
fi

echo ""
echo "data: Überprüfung abgeschlossen – Script wird nun entfernt..."
echo ""

# Script-Pfad ermitteln und löschen
SCRIPT_PATH="$(realpath "$0")"
rm -f "$SCRIPT_PATH"

exit 0
