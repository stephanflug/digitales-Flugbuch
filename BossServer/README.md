
# **Flugdaten Auswertungs- und Login-System**

Dieses Projekt umfasst zwei wesentliche Komponenten: ein sicheres **Login-System** und eine **Flugdaten-Auswertungsseite**. Die Benutzer können sich anmelden, um auf Flugdaten zuzugreifen und diese zu analysieren. 

## **Code 1: Login-System**

Das Login-System gewährleistet einen sicheren Zugriff auf die Flugdaten. Benutzer müssen sich mit einem Benutzernamen und Passwort anmelden, bevor sie auf die Auswertungsseite zugreifen können. 

### **Funktionen:**
- **Sichere Session-Verwaltung:** 
  - Erneuert die Session-ID nach dem Login, um Session-Hijacking zu verhindern.
  - Stellt sicher, dass die Cookies nur über HTTPS gesendet werden und JavaScript nicht darauf zugreifen kann.
- **Benutzerauthentifizierung:** 
  - Überprüft Benutzernamen und Passwort gegen eine vordefinierte Liste in einer externen Datei (`users.php`).
  - Bei erfolgreichem Login wird der Benutzer zur Seite mit den Flugdaten weitergeleitet. Bei Fehlern wird eine Fehlermeldung angezeigt.
- **Responsives Design:** 
  - Ein benutzerfreundliches Login-Formular, das auf allen Geräten gut aussieht.

### **Verwendete Technologien:**
- PHP für die Server-seitige Logik.
- HTML, CSS für das Frontend.

---

## **Code 2: Flugdaten Auswertung und Filterung**

Nach dem erfolgreichen Login können Benutzer Flugdaten einsehen, filtern und analysieren. Diese Seite bietet eine detaillierte Auswertung der Flugdaten, basierend auf RFID und Benutzernamen.

### **Funktionen:**
- **Zugriffsprüfung:** 
  - Stellt sicher, dass nur angemeldete Benutzer auf die Auswertungsseite zugreifen können.
- **Datenanalyse:** 
  - Flugdaten werden aus mehreren JSON-Dateien geladen und zusammengeführt.
  - Eine statistische Auswertung zeigt die Anzahl der Flüge pro Benutzer.
  - Detaillierte Informationen zu jedem Flug wie Startzeit, Endzeit und Flughöhe werden angezeigt.
- **Filterfunktionen:** 
  - Ermöglicht das Filtern der Flugdaten nach **RFID** und **Benutzernamen**.
- **Grafische Darstellung:** 
  - **Chart.js** wird verwendet, um die Anzahl der Flüge pro Benutzer in einer interaktiven Balkengrafik darzustellen.
- **PDF-Export:** 
  - Die Möglichkeit, die Flugdaten und die erstellte Grafik als PDF herunterzuladen.

### **Verwendete Technologien:**
- PHP für die Backend-Logik.
- **Chart.js** für die Erstellung interaktiver Diagramme.
- **jsPDF** für den Export von Daten als PDF.

---

## **Technische Details und Anforderungen**

### **Sicherheitsvorkehrungen im Login:**
- **Session-Hijacking-Schutz:** 
  - Das Session-Cookie ist **HTTPOnly** und wird nur über **HTTPS** gesendet.
  - **Session-Regenerierung** sorgt dafür, dass die Session-ID nach der Anmeldung geändert wird.
  
### **Flugdatenverarbeitung:**
- Die Flugdaten werden aus Dateien im JSON-Format geladen und aufbereitet.
- **RFID- und Benutzernamenfilter:** 
  - Ermöglicht das gezielte Filtern von Flugdaten basierend auf RFID und Benutzernamen.
  
### **Datenvisualisierung:**
- Mit **Chart.js** werden Flugdrafiken erstellt, um die Verteilung der Flüge übersichtlich darzustellen.
- Die Tabelle zeigt detaillierte Fluginformationen, einschließlich **Flughöhe** und **Luftraumbeobachter**.

---
