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



