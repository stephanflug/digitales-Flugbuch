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
oder auch auf dieser Seite [Flugbuch](https://flugbuch.gltdienst.home64.de))


## ⭐ Features

- 🧑‍💼 RFID-Erkennung und Nutzerverifizierung: Wenn ein Benutzer seinen RFID-Chip auf das Lesegerät legt, wird die aktuelle Uhrzeit    zusammen mit dem Namen des Benutzers aus der Benutzerdatei gespeichert. 
- ⌨️ Falls der Benutzer nicht in der Benutzerdatei existiert, wird eine Fehlermeldung ausgegeben.

## ⭐ NEU!

### 🖥️ Flugbuch Cloud Server Panel (Windows) – ab Version 3.9.0

Mit Version **v3.9.0** steht ein neues **Flugbuch Cloud Server Panel für Windows** zur Verfügung.  
Das Panel läuft lokal auf einem Windows-Rechner (z. B. im Vereinsheim) und verbindet sich automatisch mit dem Vereinsflugbuch in der Flugbuch Cloud. Der volle Funktionsumfang des Flugbuchs steht direkt zur Verfügung.

👉 Release-Details:  
https://github.com/stephanflug/digitales-Flugbuch/releases

---

### 🔎 RFID Chip Scanner (Windows & Android)

Zusätzlich zum Flugbuch stehen einfache Hilfstools zum Auslesen der UID von RFID-/NFC-Chips zur Verfügung:

- 🖥️ Windows-Tool für USB-RFID-Lesegeräte  
- 📱 Android-App für NFC-fähige Smartphones  

Die Tools lesen ausschließlich die UID des Chips aus, zeigen sie direkt an und arbeiten vollständig eigenständig.  
Die UID kann im Flugbuch zur eindeutigen Zuordnung von Nutzerchips verwendet werden.

👉 [Zum RFID Chip Scanner](./Tool%20Software/RFID%20Chip%20Scanner/README.md)

---

### 💾 Flugbuch Basic Image

Ein fertiges **Flugbuch Basic Image** steht zum Download bereit.  
Einfach herunterladen und auf die SD-Karte speichern.  
**Bitte unbedingt die Installationsanleitung beachten.**

👉 [Installationsanleitung (PDF)](https://github.com/stephanflug/digitales-Flugbuch/tree/main/Dokumentation/Installation/Flugbuch%20Images)
👉 [Flugbuch Basic Image herunterladen](https://github.com/stephanflug/digitales-Flugbuch/releases)
---

### 📈 Altitude Sensor (ab Version 3.5)

Ab Version **3.5** steht die **Altitude-Sensor-Funktion** zur Verfügung.

👉 [Anleitung (PDF)](https://github.com/stephanflug/digitales-Flugbuch/blob/main/Dokumentation/FlugBuch/RFID%20Flugbuch/Altitude%20Sensor%20beim%20Flugbuch%20einbindenV1.0.pdf)  
👉 Altitude Sensor Projekt: https://github.com/stephanflug/AltitudeSensor


---

### 🧪 Aktuelle getestete Geräte

- ✅ **Pi Zero W2** – getestet  
- ✅ **Pi 3B** – getestet  
- 🔄 **Pi 4** – getestet  
- ⏳ **Pi 5** – getestet


## ⭐ Möglichkeiten:
    -Keinen Cloudzwang
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
    -Rest-API Schnitstelle die Flugbuchdaten zu übermitteln
    -Ab der 3.5 Version ist es jetzt möglich einen Altitude Sensor zu verwenden.
    -Bossserver Funktionen.Eine externe Betriebsaufzeichnung auf dem Vereinsserver.
    -VPN Zugang direkt zum Gerät via Flugbuch Cloud Server oder Verein eigenen Server
    -Integration in Areoclub Flugbuch Online
    
<p align="center">
  <img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Bilder/TopologieFlugbuch.png?raw=true" alt="Logo" width="700" height="700"/>
</p>


## 🔧 Vorbereitung: 
```
Benötigte Hardware
- ✅ Raspberry Pi 3 oder höher oder Raspberry Pi 2 Zero. Vereine über 30 User sollten einen Pi 4 verwenden.
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
## 🚀 Schnellstart

Verwenden Sie das bereits vorbereitete Image – das spart Zeit und schont die Nerven.

👉 [**Installation: Betriebssystem auf SD-Karte**](https://github.com/stephanflug/digitales-Flugbuch/releases)
👉 [**Doko: Betriebssystem auf SD-Karte**](https://github.com/stephanflug/digitales-Flugbuch/blob/main/Dokumentation/Installation/Flugbuch%20Images/Anleitung_Flugbuch_Images.pdf)  

## 🛠️ Alternative Installation auf einem eigenen Raspberry Pi

Wenn Sie das fertige Image nicht verwenden möchten, können Sie die Software auch manuell auf einem selbst eingerichteten Raspberry Pi installieren.

### ✅ Voraussetzungen

- **Hardware:** Raspberry Pi Zero W2 (oder kompatibles Modell)
- **Betriebssystem:** Vorinstalliertes Linux auf der SD-Karte  
  - **Empfohlen:** Raspberry Pi OS Lite oder Raspberry Pi OS Desktop  
  - **Alternativen:** Ubuntu MATE, DietPi, Arch Linux (sofern kompatibel mit Raspberry Pi)
  -  Speichermedium (SD-Karte) Hochwertige SD-Karte (z. B. SanDisk High Endurance oder Samsung Pro Endurance).

### 📦 Vorbereitung

#### 1. Betriebssystem installieren

Falls noch kein Betriebssystem installiert ist:

- Laden Sie den [**Raspberry Pi Imager**](https://www.raspberrypi.com/software/) herunter.
- Wählen Sie ein geeignetes Linux-Betriebssystem (z. B. Raspberry Pi OS).
- Installieren Sie es auf die SD-Karte.

👉 Eine Schritt-für-Schritt-Anleitung finden Sie in der [offiziellen Raspberry Pi-Dokumentation](https://www.raspberrypi.com/documentation/computers/getting-started.html).

#### 2. Raspberry Pi einrichten

- SD-Karte in den Raspberry Pi einlegen
- Monitor, Tastatur und Maus anschließen
- Gerät starten und überprüfen, ob das System korrekt läuft
- Internetverbindung sicherstellen (WLAN oder Ethernet)

> ⚠️ **Hinweis:** Ohne ein vorinstalliertes Linux-Betriebssystem kann dieses Projekt nicht ausgeführt werden. Bitte stellen Sie sicher, dass das System korrekt installiert und betriebsbereit ist, bevor Sie fortfahren.


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

11a Version 1 mit RFID RC522 (alte Version. Empfehlung:Bei Neuinstallation Version 2 zu verwenden)
<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Schaltplan/Hardware_SteckplatineV1.png" alt="Logo" width="800" height="500"/>

11b Version 1B mit RFID RC522 + RTC
<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Schaltplan/Hardware_SteckplatineV1B.png" alt="Logo" width="800" height="500"/>

11c Version 2 mit RFID PN532 + (RTC muss man nicht ausführen wenn das Gerät Internet Zugang hat)
<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Schaltplan/Hardware_SteckplatineV2.png" alt="Logo" width="800" height="500"/>



12. Zugriff via Browser: Weitere Bilder Hier: <a href="https://github.com/stephanflug/digitales-Flugbuch/tree/main/Bilder/Webbedienung" target="_blank">Bilder</a>


<img src="https://github.com/stephanflug/digitales-Flugbuch/blob/main/Bilder/Webbedienung/Startseite.jpg" alt="Logo" width="800" height="500"/>

13. Videos:
<a href="https://www.youtube.com/shorts/2yrWCz5p4jw" target="_blank" rel="noopener noreferrer">
    <img src="https://img.youtube.com/vi/2yrWCz5p4jw/hqdefault.jpg" alt="YouTube Video" width="320">
</a>

<a href="https://youtu.be/VoY1FuDAuMs" target="_blank" rel="noopener noreferrer">
    <img src="https://img.youtube.com/vi/VoY1FuDAuMs/hqdefault.jpg" alt="YouTube Video" width="320">
</a>

<a href="https://youtube.com/shorts/nOOInCLnYMw" target="_blank" rel="noopener noreferrer">
    <img src="https://img.youtube.com/vi/nOOInCLnYMw/hqdefault.jpg" alt="YouTube Video" width="320">
</a>

<a href="https://youtube.com/shorts/AbHP6MEdS38" target="_blank" rel="noopener noreferrer">
    <img src="https://img.youtube.com/vi/AbHP6MEdS38/hqdefault.jpg" alt="YouTube Video" width="320">
</a>





###
1.1 Neues Update einspielen

Hinweis: Wenn Sie bereits das fertige Image verwenden, müssen Sie lediglich die IP-Adresse des Geräts in den Browser eingeben. Sie gelangen dann direkt zur Grundkonfiguration, in der Sie im Menü den Punkt „Flugbuch-Update“ finden.
Diese Schritte sind in diesem Fall nicht mehr erforderlich.

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


### ☕ Unterstütze das Büro-Kaffeekonto!

Damit der Kaffee im Büro nie ausgeht und die Entwicklung weiter auf Hochtouren läuft, freuen wir uns über eine kleine Unterstützung. ☕💻

Jeder Beitrag hilft dabei, die Kaffeemaschine am Laufen zu halten und sorgt für genügend Energie für neue Ideen, Funktionen und Updates.

[![PayPal](https://img.shields.io/badge/PayPal-Kaffee%20spendieren-0070BA?logo=paypal\&logoColor=white)](https://paypal.me/stephanflug)

**☕ [Kaffee via PayPal spendieren](https://paypal.me/stephanflug)**

Vielen Dank für deine Unterstützung! ❤️


