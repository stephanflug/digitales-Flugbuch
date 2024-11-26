<div align="center" width="100%">
    <img src="./frontend/public/icon.svg" width="128" alt="" />
</div>

# Digitales Flugbuch für Modellflug Vereine

Mit der Software und der Verbindung zu einem Raspberry Pi Zero kann eine digitale Aufzeichnung erstellt werden, die den Anforderungen der aktuellen Verordnung (EU) 2019/947 entspricht.


## ⭐ Features

- 🧑‍💼 RFID-Erkennung und Nutzerverifizierung: Wenn ein Benutzer seinen RFID-Chip auf das Lesegerät legt, wird die aktuelle Uhrzeit    zusammen mit dem Namen des Benutzers aus der Benutzerdatei gespeichert. 
- ⌨️ Falls der Benutzer nicht in der Benutzerdatei existiert, wird eine Fehlermeldung ausgegeben.



## 🔧 Vorbereitung: 

Benötigte Hardware
     - ✅ Raspberry Pi 3 oder höher oder Raspberry Pi Zero
     - ✅ Speicherkarte (microSD) Kapazität: Mindestens 16 GB, idealerweise 32 GB oder mehr.
     - ✅ Ein stabiles und ausreichend starkes Netzteil.
     - ✅ Ein Gehäuse 
     - ✅ RFID-Modul MFRC522
     - ✅ 16-Tasten-Keypad (4x4) mit I2c
     - ✅ 1602 LCD-Display mit I2C-Modul
     - ✅ RFID-Tags oder -Karten

  
### Vorbereitung: 
```
#Verzeichnisse erstellen und Berechtigungen setzen:

mkdir -p /opt/digitalflugbuch/data

#Laden den Ordner data.trz herunter und entpacke den Ordner in /opt/digitalflugbuch/data

#Berechtigung

sudo chown -R 1000:1000 /opt/digitalflugbuch/data


#Container starten:

docker run -d --name digitalflugbuch --privileged -p 1880:1880 -p 1883:1883 --restart unless-stopped --device /dev/gpiomem --device /dev/spidev0.0 --device /dev/spidev0.1 -v /opt/digitalflugbuch/data:/data -v /opt/digitalflugbuch/data/mqtt:/data/mqtt -v /opt/digitalflugbuch/data/nodered:/data/nodered -v /opt/digitalflugbuch/data/python3:/data/python3 stephanflug/iotsw:V1

# Start the server
docker compose up -d

# Status prüfen:
docker ps


```


## Screenshots




## Änderungen

