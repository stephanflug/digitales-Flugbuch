<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Logo/LOGO.jpg?raw=true" alt="Logo" width="200" height="200"/>


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
1. Vorbereitungen nur wenn Docker noch nicht auf dem System installiert wurde sonst weiter mit Postion 3

Aktualisiere das System:
```
sudo apt update
sudo apt upgrade -y
```

Die empfohlene Methode zur Installation von Docker auf einem Raspberry Pi ist die Verwendung des offiziellen Installationsskripts von Docker, das alle notwendigen Repositorys und Schritte berücksichtigt. 
```
curl -fsSL https://get.docker.com -o get-docker.sh
```
```
sudo sh get-docker.sh
```

2. Docker-Dienst aktivieren
```
sudo systemctl start docker
```
```
sudo systemctl enable docker
```
3.Verzeichniss erstellen für script
```
sudo mkdir -p /opt/digitalflugbuch
```
4.Wechsel dann in das Verzeichnis:
```
cd /opt/digitalflugbuch
```


5. Herunterladen des Skripts mit wget
```
sudo wget -O script.sh https://raw.githubusercontent.com/stephanflug/digitales-Flugbuch/main/script.sh
```
6. Anmeldeung als root Benutzer wenn das Passwort noch nicht gesetzt wurde mit sudo passwd root
```
su
```

6. Script ausführen.
```
sudo bash script.sh
```
7.Raspi-Config aufrufen
```
sudo raspi-config
```
Menüoptionen von raspi-config
> Interface Options
>Aktivierung von Schnittstellen wie  I2C, SPI

8.Gerät neustarten
```
sudo reboot
```




Beispielablauf:
Das Skript wird heruntergeladen und im aktuellen Verzeichnis gespeichert.
Es wird ausführbar gemacht, sodass du es wie ein Programm starten kannst.
Schließlich wird das Skript ausgeführt, und es erledigt alle im Code definierten Aufgaben.

9. Status prüfen:
```
docker ps
```

10. Schaltplan Prinzipschema:
 

<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Schaltplan/Hardware_SteckplatineV1.png" alt="Logo" width="800" height="500"/>




### Unterstütze das Büro-Kaffeekonto!

Damit der Kaffee im Büro nie ausgeht, wäre eine kleine Spende super! 💰☕  
Jeder Beitrag hilft, die Kaffeemaschine am Laufen zu halten, damit wir alle produktiv bleiben können!

[**Spende für Kaffee**](https://www.paypal.com/donate/?business=ACU26RPTCA44S&no_recurring=0&item_name=Dieses+Projekt+und+der+Service+kann+nur+durch+eure+Spenden+finanziert+werden.&currency_code=EUR)

Vielen Dank für deine Unterstützung! 🙌

