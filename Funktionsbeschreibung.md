Funktionsbeschreibung:

RFID-Erkennung und Nutzerverifizierung:
Wenn ein Benutzer seinen RFID-Chip auf das Lesegerät legt, wird die aktuelle Uhrzeit zusammen mit dem Namen des Benutzers aus der Benutzerdatei gespeichert.
Falls der Benutzer nicht in der Benutzerdatei existiert, wird eine Fehlermeldung ausgegeben.

Erfassung einer zweiten Aktion:
Wenn derselbe Benutzer den RFID-Chip erneut auf das Lesegerät legt, wird eine zweite aktuelle Uhrzeit ermittelt.
Anschließend muss der Benutzer die Anzahl der Flüge (bzw. Aktionen) über ein Keypad eingeben.

Datenspeicherung:
Das Ergebnis (Benutzername, erste Uhrzeit, zweite Uhrzeit, Anzahl der eingegebenen Flüge) wird in einer Zeile gespeichert.



Dockerfile Beschreibung 
Dieses Dockerfile erstellt eine Containerumgebung, die für den Betrieb einer Node-RED-Instanz und zusätzlicher Python- und MQTT-Dienste optimiert ist. Es basiert auf dem offiziellen Debian Bullseye-Image und richtet sich an Benutzer, die eine flexible Entwicklungsumgebung für IoT-Anwendungen benötigen.

1.Basis-Image:
Das Dockerfile verwendet das Debian Bullseye-Image als Grundlage, was eine stabile und schlanke Linux-Basis bietet.

2. Umgebungsvariablen:
Mehrere Umgebungsvariablen werden definiert, um den Container zu konfigurieren:
DEBIAN_FRONTEND=noninteractive: Verhindert interaktive Dialoge während der Installation.
TZ=Europe/Berlin: Setzt die Zeitzone auf Mitteleuropa.

PYTHONUSERBASE=/data/python3: Spezifiziert den Speicherort für Python-Bibliotheken.

NODE_RED_HOME=/data/nodered: Gibt das Arbeitsverzeichnis für Node-RED an.

MQTT_DATA_PATH=/data/mqtt: Definiert das Verzeichnis für MQTT-Daten.

PATH="/usr/local/bin:$PATH": Fügt benutzerdefinierte Binaries zum Suchpfad hinzu.

4. Installation von Softwarepaketen:
Die notwendigen Pakete werden installiert:
curl, python3, pip, git, build-essential, mosquitto, mosquitto-clients.
Nicht benötigte Installationslisten werden nach der Installation gelöscht, um das Image schlank zu halten.

5. Installation von Node.js und Node-RED:
Node.js in Version 18 wird über das Nodesource-Setup-Skript installiert.
Node-RED wird ohne optionale Module installiert, um den Ressourcenverbrauch zu minimieren.

6. Python-Pakete:
Python-Pakete werden mit pip aktualisiert und vorbereitet. Diese werden lokal im Container unter /data/python3 gespeichert.

7. MQTT-Konfiguration:
MQTT wird vorkonfiguriert:
Das Standardkonfigurationsverzeichnis von Mosquitto wird in den Pfad /data/mqtt/config verschoben.
Standardwerte wie Speicherorte für Daten und Logs werden angepasst.

8. Arbeitsverzeichnis und Volumes:
Das Arbeitsverzeichnis wird auf /data gesetzt.
Das /data-Verzeichnis wird als Volume bereitgestellt, damit Daten auch nach einem Neustart des Containers erhalten bleiben.

9. Ports:
Zwei Ports werden exponiert:
1880: Für die Node-RED-Weboberfläche.
1883: Für MQTT-Kommunikation.



Vorbereitung:
Verzeichnisse erstellen und Berechtigungen setzen:

mkdir -p /opt/digitalflugbuch/data/mqtt
mkdir -p /opt/digitalflugbuch/data/nodered
mkdir -p /opt/digitalflugbuch/data/python3
sudo chown -R 1000:1000 /opt/digitalflugbuch/data

Container starten: Führe den oben genannten docker run-Befehl aus.

docker run -d \
  --name stephanflug_digitalflightlog \
  --privileged \
  -p 1880:1880 \
  -p 1883:1883 \
  --restart unless-stopped \
  --device /dev/gpiomem \
  --device /dev/spidev0.0 \
  --device /dev/spidev0.1 \
  -v /opt/digitalflugbuch/data:/data \
  -v /opt/digitalflugbuch/data/mqtt:/data/mqtt \
  -v /opt/digitalflugbuch/data/nodered:/data/nodered \
  -v /opt/digitalflugbuch/data/python3:/data/python3 \
  digitalflightlog

Status prüfen:

docker ps

4. Logs überprüfen (optional)
Wenn du sehen möchtest, was im Container passiert, verwende:

docker logs digitalflightlog


