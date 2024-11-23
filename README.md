# digitales-Flugbuch
Digitales Flugbuch



Node-RED Installation und Einrichtung
Dieses Dokument beschreibt, wie Sie Node-RED auf einem Raspberry Pi (oder einem anderen Linux-System) installieren, einrichten und verwenden können.

Voraussetzungen
Bevor Sie beginnen, stellen Sie sicher, dass folgende Voraussetzungen erfüllt sind:

Ein Raspberry Pi (oder ein anderes Debian-basiertes Linux-System).
Internetverbindung.
Basiskenntnisse in der Nutzung des Terminals.
Schritt 1: System aktualisieren
Bevor Sie Node-RED installieren, aktualisieren Sie Ihr Betriebssystem:

bash
Code kopieren
sudo apt update
sudo apt upgrade -y
Schritt 2: Node-RED mit Skript installieren
Node-RED bietet ein offizielles Installationsskript, das die Einrichtung von Node.js und Node-RED übernimmt.

Installation
Führen Sie diesen Befehl aus:

bash
Code kopieren
bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)
Was das Skript macht:
Installiert Node.js (falls nicht vorhanden).
Installiert oder aktualisiert Node-RED.
Konfiguriert Node-RED als Systemdienst.
Testen Sie die Installation:
Nach der Installation können Sie Node-RED starten:

bash
Code kopieren
node-red
Öffnen Sie anschließend den Browser und navigieren Sie zu:

arduino
Code kopieren
http://<IP-Adresse>:1880
Ersetzen Sie <IP-Adresse> durch die IP-Adresse Ihres Raspberry Pi.

Schritt 3: Node-RED als Systemdienst einrichten
Damit Node-RED automatisch beim Booten startet, richten Sie es als Systemdienst ein.

Dienst aktivieren:
bash
Code kopieren
sudo systemctl enable nodered.service
sudo systemctl start nodered.service
Status überprüfen:
Prüfen Sie, ob Node-RED erfolgreich läuft:

bash
Code kopieren
sudo systemctl status nodered.service

