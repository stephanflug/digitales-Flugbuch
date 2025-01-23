#!/bin/bash

# Logfile definieren
LOGFILE="/var/log/digitalflugbuch_update.log"

# Ausgabe und Fehlerausgabe in die Logdatei umleiten
exec > >(tee -a "$LOGFILE") 2>&1

echo "-------------------------------------------"
echo "Start des Updates: $(date)"
echo "Logdatei: $LOGFILE"
echo "-------------------------------------------"

# Überprüfen, ob die IDnummer.txt existiert
IDDATEI="/opt/digitalflugbuch/data/DatenBuch/IDnummer.txt"
if [ ! -f "$IDDATEI" ]; then
    echo "Die Datei IDnummer.txt existiert nicht. Erstelle sie jetzt..."
    
    # Vereinsname abfragen
    echo "Geben Sie den Namen des Vereins ein:"
    read VEREINSNAME
    if [ -z "$VEREINSNAME" ]; then
        echo "Fehler: Kein Vereinsname angegeben."
        exit 1
    fi

    # Generiere eine zufällige UUID (wenn uuidgen nicht funktioniert, verwenden wir andere Methoden)
    IDNUMMER=$(uuidgen)
    if [ -z "$IDNUMMER" ]; then
        echo "Fehler: UUID konnte nicht generiert werden."
        IDNUMMER=$(date +%s)-$RANDOM
    fi

    # Speichere den Vereinsnamen und die ID in einer Textdatei
    echo "Vereinsname: $VEREINSNAME" > "$IDDATEI"
    echo "ID: $IDNUMMER" >> "$IDDATEI"
    echo "Vereinsinformationen wurden gespeichert: $IDDATEI"
else
    echo "Die Datei IDnummer.txt existiert bereits. Update wird fortgesetzt..."
fi

# Docker stoppen
echo "Docker-Container werden gestoppt..."
docker stop $(docker ps -q)
if [ $? -ne 0 ]; then
    echo "Fehler: Docker-Container konnten nicht gestoppt werden."
    exit 1
fi

# Überprüfen und Konvertieren von Windows-Zeilenenden in Unix-Zeilenenden
if file "$0" | grep -q "with CRLF line terminators"; then
    echo "Konvertiere Windows-Zeilenenden in Unix-Zeilenenden..."
    sed -i 's/\r$//' "$0"
fi

# Abhängigkeiten installieren, falls nicht vorhanden
echo "Überprüfe, ob jq installiert ist..."
if ! command -v jq &>/dev/null; then
    echo "jq nicht gefunden. Installiere jq..."
    sudo apt-get update && sudo apt-get install -y jq
    if [ $? -ne 0 ]; then
        echo "Fehler: jq konnte nicht installiert werden."
        exit 1
    fi
fi

# Shell In A Box installieren
echo "Überprüfe, ob Shell In A Box installiert ist..."
if ! command -v shellinaboxd &>/dev/null; then
    echo "Shell In A Box nicht gefunden. Installiere es..."
    sudo apt-get update && sudo apt-get install -y shellinabox
    if [ $? -ne 0 ]; then
        echo "Fehler: Shell In A Box konnte nicht installiert werden."
        exit 1
    fi

    # Standardkonfiguration für Shell In A Box
    echo "Aktiviere und starte Shell In A Box..."
    sudo systemctl enable shellinabox
    sudo systemctl start shellinabox
    if [ $? -ne 0 ]; then
        echo "Fehler: Shell In A Box konnte nicht gestartet werden."
        exit 1
    fi
else
    echo "Shell In A Box ist bereits installiert. Stelle sicher, dass der Dienst läuft..."
    sudo systemctl enable shellinabox
    sudo systemctl start shellinabox
fi

# GitHub-Repository und Release-Datei
REPO="stephanflug/digitales-Flugbuch"
ASSET_NAME="data.tar"
COMPOSE_FILE="compose.yaml"

# Backup erstellen
echo "Erstelle Backup der Daten..."
sudo tar -cvf /opt/digitalflugbuch/DatenBuch_backup.tar /opt/digitalflugbuch/data/DatenBuch
if [ $? -ne 0 ]; then
    echo "Fehler: Backup konnte nicht erstellt werden."
    exit 1
fi

# Die neueste Release-Version abrufen
echo "Hole die neueste Release-URL..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)
if [ -z "$LATEST_RELEASE" ]; then
    echo "Fehler: Release-Daten konnten nicht abgerufen werden."
    exit 1
fi

# Die Download-URL für das Asset extrahieren
ASSET_URL=$(echo $LATEST_RELEASE | jq -r ".assets[] | select(.name==\"$ASSET_NAME\") | .browser_download_url")
if [ "$ASSET_URL" != "null" ]; then
    # Datei herunterladen
    echo "Lade die neueste Datei herunter..."
    wget -O /tmp/data.tar $ASSET_URL
    if [ $? -ne 0 ]; then
        echo "Fehler: Datei konnte nicht heruntergeladen werden."
        exit 1
    fi

    # Datei entpacken
    echo "Entpacke die Datei..."
    tar -xvf /tmp/data.tar -C /opt/digitalflugbuch/
    if [ $? -ne 0 ]; then
        echo "Fehler: Datei konnte nicht entpackt werden."
        exit 1
    fi
    echo "Entpacken abgeschlossen."
else
    echo "Fehler: Die Datei $ASSET_NAME konnte nicht gefunden werden."
    exit 1
fi

# Die compose.yaml-Datei herunterladen
echo "Lade die compose.yaml-Datei herunter..."
curl -L -o /opt/digitalflugbuch/$COMPOSE_FILE https://raw.githubusercontent.com/$REPO/main/$COMPOSE_FILE
if [ $? -ne 0 ]; then
    echo "Fehler: compose.yaml konnte nicht heruntergeladen werden."
    exit 1
fi

# Berechtigungen setzen
echo "Setze Berechtigungen für /opt/digitalflugbuch/data..."
sudo chown -R 1000:1000 /opt/digitalflugbuch/data
if [ $? -ne 0 ]; then
    echo "Fehler: Berechtigungen konnten nicht gesetzt werden."
    exit 1
fi

# Docker-Container starten
echo "Starte Docker-Container..."
docker start $(docker ps -a -q)
if [ $? -ne 0 ]; then
    echo "Fehler: Docker-Container konnten nicht gestartet werden."
    exit 1
fi

echo "-------------------------------------------"
echo "Update abgeschlossen: $(date)"
echo "Shell In A Box ist unter http://<IP>:4200 erreichbar."
echo "Überprüfen Sie die Logdatei unter $LOGFILE"
echo "-------------------------------------------"
