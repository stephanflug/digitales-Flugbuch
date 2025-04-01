<p align="center">
  <img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Logo/Flyer.jpg?raw=true" alt="Logo" width="500" height="500"/>
</p>


<div align="center" width="100%">
    <img src="./frontend/public/icon.svg" width="128" alt="" />
</div>

# Digitales Flugbuch für Modellflug Vereine

Mit der Software und der Verbindung zu einem Raspberry Pi Zero kann eine digitale Aufzeichnung erstellt werden, die den Anforderungen der aktuellen Verordnung (EU) 2019/947 entspricht.Für Österreich und Deutschland(kann man unter Einstellungen festlegen)

## Kontakt  
Bei Fragen können Sie mich gerne per E-Mail erreichen:  
📧 [steuerung@gmx.at](mailto:steuerung@gmx.at)


## ⭐ Features

- 🧑‍💼 RFID-Erkennung und Nutzerverifizierung: Wenn ein Benutzer seinen RFID-Chip auf das Lesegerät legt, wird die aktuelle Uhrzeit    zusammen mit dem Namen des Benutzers aus der Benutzerdatei gespeichert. 
- ⌨️ Falls der Benutzer nicht in der Benutzerdatei existiert, wird eine Fehlermeldung ausgegeben.

## ⭐ NEU!
Neu ab der Version 2.8.Ein fertiges Flugbuch Images.Einfach herunterladen und auf die SD-Karte speichern. Achte dabei unbedingt auf die Installationsanleitung!
<a href="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Installation/Flugbuch%20Images/Anleitung_Flugbuch_Images.pdf
" target="_blank">Anleitung</a>



## ⭐ Möglichkeiten: 
    -Flugbuch-Auswertung direkt auf dem Gerät
    -Möglichkeit, das gesamte Flugbuch zu löschen
    -Flugbuch Einträge bearbeiten
    -Flugbuch-Ausgabe im JSON-Format
    -Flugbuch export in CSV
    -Systeminformationen anzeigen
    -Mail versand
    -Browser Zugang für die Verwaltung
    -Serviceebene direkt auf dem Gerät
    -MQTT
    -MFSD Schnitstelle
    -Kann auch ohne Internet betrieben werden(Nur wenn eine RTC Batterie verbaut wurde)
    -Backup und Restore
    -Viewer Dashboard für eine externen Anzeige via Browser

## 🔧 Vorbereitung: 
```
Benötigte Hardware
- ✅ Raspberry Pi 3 oder höher oder Raspberry Pi 2 Zero
- ✅ Speicherkarte (microSD) Kapazität: Mindestens 16 GB, idealerweise 32 GB oder mehr.
- ✅ Ein stabiles und ausreichend starkes Netzteil.
- ✅ Ein Gehäuse 
- ✅ Einen Kühlkörper für den Prozessor.
- ✅ RFID-Modul MFRC522
- ✅ 16-Tasten-Keypad (4x4) mit I2c
- ✅ 1602 LCD-Display mit I2C-Modul
- ✅ RFID-Tags oder -Karten
- ✅ RTC Batterie für den offline Modus(nur wenn das Gerät kein Internet hat)
```
Voraussetzungen: Vorinstallation eines Linux-Betriebssystems für den Raspberry Pi Zero
Für die Nutzung dieses Projekts wird ein Raspberry Pi Zero W2 (oder kompatibles Modell) benötigt, auf dem bereits ein Linux-Betriebssystem vorinstalliert ist. Die gängigste Wahl ist Raspberry Pi OS, aber auch andere Linux-basierte Systeme sind möglich, solange sie mit dem Raspberry Pi kompatibel sind.

Was benötigt wird:
Raspberry Pi Zero W2 (oder kompatible Version)
Vorinstalliertes Linux-Betriebssystem auf der SD-Karte
Empfohlene Version: Raspberry Pi OS Lite oder Raspberry Pi OS Desktop
Weitere Linux-Distributionen wie Ubuntu MATE, DietPi oder Arch Linux sind ebenfalls möglich.
Vorbereitungen:
Betriebssystem installieren:

Wenn noch kein Betriebssystem auf dem Raspberry Pi installiert ist, laden Sie Raspberry Pi Imager herunter, um das Betriebssystem Ihrer Wahl auf eine SD-Karte zu installieren.
Eine Schritt-für-Schritt-Anleitung zum Installieren von Raspberry Pi OS finden Sie in der offiziellen Raspberry Pi-Dokumentation.
Raspberry Pi einrichten:

Stecken Sie die SD-Karte in den Raspberry Pi, verbinden Sie das Gerät mit einem Monitor, einer Tastatur und einer Maus, und starten Sie den Raspberry Pi.
Stellen Sie sicher, dass das Betriebssystem korrekt läuft und der Raspberry Pi mit dem Internet verbunden ist (z. B. über WLAN oder Ethernet).
Hinweis:
Ohne ein vorinstalliertes Linux-Betriebssystem ist der Raspberry Pi nicht in der Lage, mit diesem Projekt zu arbeiten. Bitte stellen Sie sicher, dass das Betriebssystem korrekt installiert und betriebsbereit ist, bevor Sie fortfahren.

Installation:  <a href="https://github.com/stephanflug/digitales-Flugbuch/tree/main/Installation" target="_blank">Betriebsystem auf SD Karte</a>

###
1. Vorbereitungen nur wenn Docker noch nicht auf dem System installiert wurde sonst weiter mit Postion 3
###  
Als Video ansehen:    <a href="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Installation/Neuinstallation/Video/InstallationVideoFlugBuchsoftware.mp4" target="_blank">Video</a>

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


5a. Herunterladen des Skripts mit wget mit Raspberry Pi 3/4/5 Zero 2W oder höher: Prozessor ARMV7
```
sudo wget -O script.sh https://raw.githubusercontent.com/stephanflug/digitales-Flugbuch/main/script_armv7.sh
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
sudo docker ps
```

10. Danach können Sie die Verwaltungsseite öffnen.
```
Startseite url:http://<IPAdresse>:1880/home
```

11 Schaltplan Prinzipschema:   <a href="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Schaltplan/BelegungsaufstellungV1.0.pdf" target="_blank">Belegungsaufstellung</a>

11a Version 1 mit RFID RC522 
<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Schaltplan/Hardware_SteckplatineV1.png" alt="Logo" width="800" height="500"/>

11b Version 1B mit RFID RC522 + RTC
<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Schaltplan/Hardware_SteckplatineV1B.png" alt="Logo" width="800" height="500"/>

11c Version 2 mit RFID PN532 + (RTC muss man nicht ausführen wenn das Gerät Internet Zugang hat)
<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Schaltplan/Hardware_SteckplatineV2.png" alt="Logo" width="800" height="500"/>



12. Zugriff via Browser: Weitere Bilder Hier: <a href="https://github.com/stephanflug/digitales-Flugbuch/tree/main/Bilder/Webbedienung" target="_blank">Bilder</a>


<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Bilder/Webbedienung/Startseite.jpg" alt="Logo" width="800" height="500"/>

13. Video vom fertigen Gerät:
[![YouTube-Video](https://img.youtube.com/vi/2yrWCz5p4jw/hqdefault.jpg)](https://www.youtube.com/shorts/2yrWCz5p4jw)

➡️ **[Video in neuem Tab öffnen](https://www.youtube.com/shorts/2yrWCz5p4jw)**  




###
1.1 Neues Update einspielen

1.2 Wechsel in das Verzeichnis:
```
cd /opt/digitalflugbuch
```
1.3 Herunterladen des Skripts
```
sudo wget -O update_script.sh https://raw.githubusercontent.com/stephanflug/digitales-Flugbuch/main/update_script_armv7.sh
```
1.4  Anmeldeung als root Benutzer
```
su
```

1.5. Script ausführen.
```
sudo bash update_script.sh
```
1.6.Gerät neustarten
```
sudo reboot
```


### Unterstütze das Büro-Kaffeekonto!

Damit der Kaffee im Büro nie ausgeht, wäre eine kleine Spende super! 💰☕  
Jeder Beitrag hilft, die Kaffeemaschine am Laufen zu halten, damit wir alle produktiv bleiben können!

[**Spende für Kaffee**](https://www.paypal.com/donate/?business=ACU26RPTCA44S&no_recurring=0&item_name=Dieses+Projekt+und+der+Service+kann+nur+durch+eure+Spenden+finanziert+werden.&currency_code=EUR)

Vielen Dank für deine Unterstützung! 🙌

