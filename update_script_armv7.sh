#!/bin/bash

# Logfile definieren
LOGFILE="/var/log/digitalflugbuch_update.log"

# Ausgabe und Fehlerausgabe in die Logdatei umleiten
exec > >(tee -a "$LOGFILE") 2>&1

echo "-------------------------------------------"
echo "Start des Updates: $(date)"
echo "Logdatei: $LOGFILE"
echo "-------------------------------------------"

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

    echo "Aktiviere und starte Shell In A Box..."
    sudo systemctl enable shellinabox
    sudo systemctl start shellinabox
else
    echo "Shell In A Box ist bereits installiert. Stelle sicher, dass der Dienst läuft..."
    sudo systemctl enable shellinabox
    sudo systemctl start shellinabox
fi

# GitHub-Repository und Release-Dateien
REPO="stephanflug/digitales-Flugbuch"
ASSET_NAME="data.tar"
TOOLS_ARCHIVE="systemtools.tar"
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

# data.tar herunterladen und entpacken
ASSET_URL=$(echo $LATEST_RELEASE | jq -r ".assets[] | select(.name==\"$ASSET_NAME\") | .browser_download_url")
if [ "$ASSET_URL" != "null" ]; then
    echo "Lade $ASSET_NAME herunter..."
    wget -O /tmp/data.tar $ASSET_URL
    if [ $? -ne 0 ]; then
        echo "Fehler: $ASSET_NAME konnte nicht heruntergeladen werden."
        exit 1
    fi

    echo "Entpacke $ASSET_NAME..."
    tar -xvf /tmp/data.tar -C /opt/digitalflugbuch/
    if [ $? -ne 0 ]; then
        echo "Fehler: $ASSET_NAME konnte nicht entpackt werden."
        exit 1
    fi
else
    echo "Fehler: $ASSET_NAME wurde im Release nicht gefunden."
    exit 1
fi

# systemtools.tar herunterladen und entpacken
TOOLS_URL=$(echo $LATEST_RELEASE | jq -r ".assets[] | select(.name==\"$TOOLS_ARCHIVE\") | .browser_download_url")
if [ "$TOOLS_URL" != "null" ]; then
    echo "Lade $TOOLS_ARCHIVE herunter..."
    wget -O /tmp/systemtools.tar $TOOLS_URL
    if [ $? -ne 0 ]; then
        echo "Fehler: $TOOLS_ARCHIVE konnte nicht heruntergeladen werden."
        exit 1
    fi

    echo "Entpacke $TOOLS_ARCHIVE nach /opt/tools/system/..."
    sudo mkdir -p /opt/tools/system/
    sudo tar -xvf /tmp/systemtools.tar -C /opt/tools/system/
    if [ $? -ne 0 ]; then
        echo "Fehler: $TOOLS_ARCHIVE konnte nicht entpackt werden."
        exit 1
    fi

    echo "Setze Berechtigungen auf rwxrwxrwx (777)..."
    sudo chmod -R 777 /opt/tools/system/
else
    echo "Hinweis: $TOOLS_ARCHIVE wurde im Release nicht gefunden."
fi

# host.tar herunterladen und entpacken
HOST_ARCHIVE="host.tar"
HOST_URL=$(echo $LATEST_RELEASE | jq -r ".assets[] | select(.name==\"$HOST_ARCHIVE\") | .browser_download_url")
if [ "$HOST_URL" != "null" ]; then
    echo "Lade $HOST_ARCHIVE herunter..."
    if wget -O /tmp/host.tar "$HOST_URL"; then
        echo "Entpacke $HOST_ARCHIVE..."
        mkdir -p /tmp/host_temp
        if tar -xvf /tmp/host.tar -C /tmp/host_temp; then
            echo "Verschiebe HTML-Dateien nach /var/www/..."
            sudo cp -r /tmp/host_temp/html/* /var/www/ 2>/dev/null || echo "Hinweis: Keine HTML-Dateien gefunden oder Fehler beim Kopieren."

            echo "Verschiebe CGI-Skripte nach /usr/lib/..."
            sudo cp -r /tmp/host_temp/cgi-bin/* /usr/lib/ 2>/dev/null || echo "Hinweis: Keine CGI-Dateien gefunden oder Fehler beim Kopieren."

            echo "Setze Berechtigungen auf 0777 für /var/www/ und /usr/lib/..."
            sudo chmod -R 0777 /var/www/html/
            sudo chmod -R 0777 /usr/lib/cgi-bin/
        else
            echo "Warnung: $HOST_ARCHIVE konnte nicht entpackt werden. Vorgang wird übersprungen."
        fi
    else
        echo "Warnung: $HOST_ARCHIVE konnte nicht heruntergeladen werden. Vorgang wird übersprungen."
    fi
else
    echo "Hinweis: $HOST_ARCHIVE wurde im Release nicht gefunden."
fi


# compose.yaml herunterladen
echo "Lade $COMPOSE_FILE herunter..."
curl -L -o /opt/digitalflugbuch/$COMPOSE_FILE https://raw.githubusercontent.com/$REPO/main/$COMPOSE_FILE
if [ $? -ne 0 ]; then
    echo "Fehler: $COMPOSE_FILE konnte nicht heruntergeladen werden."
    exit 1
fi

# Altes Verzeichnis löschen und neu erstellen
echo "Lösche altes Datenverzeichnis..."
sudo rm -rf /opt/digitalflugbuch/data/DatenBuch
sudo mkdir -p /opt/digitalflugbuch/data/DatenBuch
if [ $? -ne 0 ]; then
    echo "Fehler: Datenverzeichnis konnte nicht neu erstellt werden."
    exit 1
fi

# Backup wiederherstellen
echo "Stelle Backup wieder her..."
sudo tar -xvf /opt/digitalflugbuch/DatenBuch_backup.tar -C /
if [ $? -ne 0 ]; then
    echo "Fehler: Backup konnte nicht wiederhergestellt werden."
    exit 1
fi

# Berechtigungen setzen
echo "Setze Berechtigungen für /opt/digitalflugbuch/data..."
sudo chown -R 1000:1000 /opt/digitalflugbuch/data
if [ $? -ne 0 ]; then
    echo "Fehler: Berechtigungen konnten nicht gesetzt werden."
    exit 1
fi

# system_monitor.timer neu laden
echo "Lade systemd-Timer für system_monitor.sh neu..."
sudo systemctl daemon-reload
sudo systemctl restart system_monitor.timer

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
