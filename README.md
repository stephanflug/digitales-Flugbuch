<h1 align="left">Digitales Flugbuch</h1>

###

<p align="left">Komplette Anleitung der Installation</p>

###

<h2 align="left">Node-RED Installation und Einrichtung</h2>

###

<p align="left">Dieses Dokument beschreibt, wie Sie Node-RED auf einem Raspberry Pi (oder einem anderen Linux-System) installieren, einrichten und verwenden können.</p>

###

<p align="left">Voraussetzungen<br>Bevor Sie beginnen, stellen Sie sicher, dass folgende Voraussetzungen erfüllt sind:<br><br>Ein Raspberry Pi (oder ein anderes Debian-basiertes Linux-System).<br>Internetverbindung.<br>Basiskenntnisse in der Nutzung des Terminals</p>

###

<h3 align="left">Schritt 1: System aktualisieren<br>Bevor Sie Node-RED installieren, aktualisieren Sie Ihr Betriebssystem:</h3>

###

<p align="left">sudo apt update<br>sudo apt upgrade -y</p>

###

<h3 align="left">Schritt 2: Node-RED mit Skript installieren</h3>

###

<p align="left">Node-RED bietet ein offizielles Installationsskript, das die Einrichtung von Node.js und Node-RED übernimmt.</p>

###

<p align="left">bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)</p>

###

<h3 align="left">Testen Sie die Installation:<br>Nach der Installation können Sie Node-RED starten:</h3>

###

<p align="left">node-red</p>

###

<p align="left">Öffnen Sie anschließend den Browser und navigieren Sie zu: http://<IP-Adresse>:1880</p>

###

<h3 align="left">Schritt 3: Node-RED als Systemdienst einrichten<br>Damit Node-RED automatisch beim Booten startet, richten Sie es als Systemdienst ein.</h3>

###

<p align="left">sudo systemctl enable nodered.service<br>sudo systemctl start nodered.service</p>

###

<p align="left">Status überprüfen:<br>Prüfen Sie, ob Node-RED erfolgreich läuft:</p>

###

<p align="left">sudo systemctl status nodered.service</p>

###

<h3 align="left">Schritt 7: Updates</h3>

###

<p align="left">bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)</p>

###
