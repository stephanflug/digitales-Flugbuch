#!/bin/sh

# Header für Server-Sent-Events
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

echo "data: Starte SD-Karten-Fehlerüberprüfung..."
echo ""

# Prüfe dmesg auf SD-Karten- oder I/O-Fehler
ERRORS=$(dmesg | grep -iE 'mmc|error|fail|io error')

if [ -n "$ERRORS" ]; then
    echo "data: SD-Karten Fehler entdeckt:"
    echo "$ERRORS" | while IFS= read -r line; do
        echo "data: $line"
    done
else
    echo "data: Keine SD-Karten-Fehler in dmesg gefunden."
fi

echo ""
