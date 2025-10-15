#!/bin/sh

# Setze das Verzeichnis
TEST_DIR="/opt/addons"

# Starte den Test (CGI-kompatibel)
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

set -x

echo "data: Starte Test..."
echo ""

# Teste, ob das Verzeichnis existiert
if [ -d "$TEST_DIR" ]; then
    echo "data: Test bestanden: Verzeichnis '$TEST_DIR' existiert."
    echo ""
    RESULT=0
else
    echo "data: Test fehlgeschlagen: Verzeichnis '$TEST_DIR' existiert nicht."
    echo ""
    RESULT=1
fi

echo "data: Test abgeschlossen – Script wird nun entfernt..."
echo ""

# Script-Pfad ermitteln und löschen
SCRIPT_PATH="$(realpath "$0")"
rm -f "$SCRIPT_PATH"

exit $RESULT
