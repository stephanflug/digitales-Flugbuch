#!/bin/sh

TEST_DIR="/opt/addons"

echo "Starte Test..."

if [ -d "$TEST_DIR" ]; then
    echo  "Test bestanden: Verzeichnis '$TEST_DIR' existiert."
    exit 0
else
    echo " Test fehlgeschlagen: Verzeichnis '$TEST_DIR' existiert nicht."
    exit 1
fi
