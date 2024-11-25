<h1 align="center">Digitales Flugbuch für Modellflug Vereine</h1>
<h3 align="center">Mit der Software und der Verbindung zu einem Raspberry Pi Zero kann eine digitale Aufzeichnung erstellt werden, die den Anforderungen der aktuellen Verordnung (EU) 2019/947 entspricht.</h3>
<h4 align="center">


Funktionsbeschreibung:

RFID-Erkennung und Nutzerverifizierung: Wenn ein Benutzer seinen RFID-Chip auf das Lesegerät legt, wird die aktuelle Uhrzeit zusammen mit dem Namen des Benutzers aus der Benutzerdatei gespeichert. Falls der Benutzer nicht in der Benutzerdatei existiert, wird eine Fehlermeldung ausgegeben.

Erfassung einer zweiten Aktion: Wenn derselbe Benutzer den RFID-Chip erneut auf das Lesegerät legt, wird eine zweite aktuelle Uhrzeit ermittelt. Anschließend muss der Benutzer die Anzahl der Flüge (bzw. Aktionen) über ein Keypad eingeben.

Datenspeicherung: Das Ergebnis (Benutzername, erste Uhrzeit, zweite Uhrzeit, Anzahl der eingegebenen Flüge) wird in einer Zeile gespeichert.

Vorbereitung: Verzeichnisse erstellen und Berechtigungen setzen:

mkdir -p /opt/digitalflugbuch/data

Laden den Ordner data.trz herunter  und entpacke den Ordner in /opt/digitalflugbuch/data


Berechtigung:
sudo chown -R 1000:1000 /opt/digitalflugbuch/data

Container starten: Führe den oben genannten docker run-Befehl aus.

docker run -d
--name stephanflug_digitalflightlog
--privileged
-p 1880:1880
-p 1883:1883
--restart unless-stopped
--device /dev/gpiomem
--device /dev/spidev0.0
--device /dev/spidev0.1
-v /opt/digitalflugbuch/data:/data
-v /opt/digitalflugbuch/data/mqtt:/data/mqtt
-v /opt/digitalflugbuch/data/nodered:/data/nodered
-v /opt/digitalflugbuch/data/python3:/data/python3
digitalflightlog

Status prüfen:

docker ps

Logs überprüfen (optional) Wenn du sehen möchtest, was im Container passiert, verwende:
docker logs digitalflightlog

</h4>



