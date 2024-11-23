# digitales-Flugbuch
Digitales Flugbuch


1. Raspberry Pi vorbereiten
System aktualisieren
Führen Sie die folgenden Befehle aus, um das Betriebssystem auf den neuesten Stand zu bringen:

Code kopieren
sudo apt update
sudo apt upgrade -y

Node.js installieren oder aktualisieren
Node-RED benötigt eine aktuelle Version von Node.js. Der Installationsskript kümmert sich darum.

bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)

3. Node-RED starten
Node-RED manuell starten Starten Sie Node-RED mit:

Code kopieren
node-red
Der Dienst läuft dann im Vordergrund und zeigt Logs an.

Node-RED als Dienst starten Um Node-RED im Hintergrund laufen zu lassen, starten Sie den Dienst:


Code kopieren
sudo systemctl enable nodered.service
sudo systemctl start nodered.service


Prüfen Sie, ob der Dienst läuft:

Code kopieren
sudo systemctl status nodered.service

4. Zugriff auf Node-RED
Öffnen Sie Ihren Browser auf einem Gerät im gleichen Netzwerk wie der Raspberry Pi.
Geben Sie die IP-Adresse Ihres Raspberry Pi ein, gefolgt von :1880

Code kopieren
http://<IP-Adresse>:1880
Ersetzen Sie <IP-Adresse> durch die tatsächliche IP des Raspberry Pi. Alternativ können Sie http://raspberrypi:1880 verwenden, wenn raspberrypi im Netzwerk aufgelöst wird.

<h3 align="center">A passionate frontend developer from India</h3>

<h3 align="left">Connect with me:</h3>
<p align="left">
</p>




