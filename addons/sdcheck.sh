#!/bin/sh

# Server-Sent Events Header (für CGI/Webserver wie lighttpd)
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

echo "data: Starte SD-Karten-Fehlerüberprüfung..."
echo ""

# Hole relevante dmesg-Zeilen
LOG=$(dmesg | grep -iE 'mmc|error|fail|io error')

# Prüfe auf echte Fehler (nicht nur SD-Initialisierungen)
FEHLER=$(echo "$LOG" | grep -iE 'error|fail|io error')

if [ -n "$FEHLER" ]; then
    echo "data:SD-Kartenfehler entdeckt:"
    echo ""
    echo "$FEHLER" | while IFS= read -r line; do
        echo "data: $line"
    done
else
    echo "data:Keine SD-Karten-Fehler in dmesg gefunden."
fi

echo ""
