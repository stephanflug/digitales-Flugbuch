#!/bin/sh

# Setze das Verzeichnis
TEST_DIR="/opt/addons"

# Starte den Test
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

# Teste, ob das Verzeichnis existiert
echo "data: Starte Test..."
echo ""

if [ -d "$TEST_DIR" ]; then
    echo "data: Test bestanden: Verzeichnis '$TEST_DIR' existiert."
    echo ""
    exit 0
else
    echo "data: Test fehlgeschlagen: Verzeichnis '$TEST_DIR' existiert nicht."
    echo ""
    exit 1
fi
