#!/bin/sh

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

echo "data: Starte Journalprüfung auf SD-Kartenfehler..."
echo ""

LOG=$(journalctl -k | grep -iE 'mmc|error|fail|io error')
FEHLER=$(echo "$LOG" | grep -iE 'error|fail|io error')

if [ -n "$FEHLER" ]; then
    echo "data:  Fehler gefunden im Kernel-Journal:"
    echo ""
    echo "$FEHLER" | while IFS= read -r line; do
        echo "data: $line"
    done
else
    echo "data:  Keine Fehler im Kernel-Journal gefunden."
fi

echo ""
