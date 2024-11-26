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

  
###
1. Vorbereitungen

Aktualisiere das System:
```
sudo apt update
sudo apt upgrade -y
```
2.Installiere grundlegende Pakete:
```
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
```
3. Docker-Repository hinzufügen
```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```
4. Docker installieren
Aktualisiere die Paketquellen und installiere Docker:
```
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
```

5. Docker-Dienst aktivieren
```
sudo systemctl start docker
sudo systemctl enable docker
```

1. Herunterladen des Skripts mit wget
```
wget -O script.sh https://raw.githubusercontent.com/stephanflug/digitales-Flugbuch/main/script.sh
```
2. Ausführbarkeitsrechte setzen
```
chmod +x script.sh
```
3. Skript ausführen
```
./script.sh
```
Beispielablauf:
Das Skript wird heruntergeladen und im aktuellen Verzeichnis gespeichert.
Es wird ausführbar gemacht, sodass du es wie ein Programm starten kannst.
Schließlich wird das Skript ausgeführt, und es erledigt alle im Code definierten Aufgaben.


# Status prüfen:
```
docker ps
```

## Screenshots




## Änderungen

