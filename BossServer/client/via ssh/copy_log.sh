#!/bin/bash

# Variablen
QUELLDATEI="/opt/digitalflugbuch/data/DatenBuch/log.txt"
ZIELSERVER="192.168.100.4" # IP Adresse des Boss Server Beispiel 192.168.100.4
ZIELUSER="root"  # Benutzer auf dem Zielserver
DATUM=$(date "+%Y-%m")  # Aktuelles Datum (z.B. 2024-12-09)
STUNDE=$(date "")  # Aktuelle Stunde, Minute und Sekunde (z.B. 14-30-45)
ZIELPFAD="/vereinMuster/addons/flugbuch/flugbuch_${DATUM}_${STUNDE}.log.txt"  # Zielpfad mit Datum und Stunde im Dateinamen

# Datei kopieren
echo "[$DATUM $STUNDE] Starte das Kopieren der Datei von $QUELLDATEI nach $ZIELUSER@$ZIELSERVER:$ZIELPFAD"
scp "$QUELLDATEI" "$ZIELUSER@$ZIELSERVER:$ZIELPFAD"

# Überprüfen, ob das Kopieren erfolgreich war
if [ $? -eq 0 ]; then
    echo "[$DATUM $STUNDE] Datei wurde erfolgreich kopiert."
else
    echo "[$DATUM $STUNDE] Fehler beim Kopieren der Datei."
    exit 1
fi
