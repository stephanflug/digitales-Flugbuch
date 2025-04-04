Beschreibung der beiden Codes:
Code 1: Login-System für den Zugriff auf Flugdaten
Der erste Code stellt eine Login-Seite für den Zugriff auf eine Webseite zur Verfügung, die vermutlich Flugdaten analysiert. Er nutzt PHP, um Benutzeranmeldungen zu verarbeiten und die Session sicher zu gestalten.

Wichtige Funktionen:

Sichere Session-Verwaltung: Der Code startet eine Session und stellt sicher, dass diese nach der Anmeldung eine neue ID erhält, um eine mögliche Entführung der Session zu verhindern. Zudem wird sichergestellt, dass die Cookies nur über HTTPS gesendet werden und JavaScript keinen Zugriff darauf hat.

Benutzeranmeldung: Der Benutzer gibt seinen Benutzernamen und sein Passwort ein. Der Code überprüft die Eingaben gegen eine vordefinierte Liste von Benutzern ($users), die in einer externen Datei (users.php) gespeichert ist.

Fehlermeldung: Bei einer falschen Anmeldung wird eine Fehlermeldung angezeigt.

HTML-Struktur:

Ein Login-Formular fragt den Benutzer nach seinem Benutzernamen und Passwort.

Wenn die Anmeldung erfolgreich ist, wird der Benutzer zur Seite readflugbuch.php weitergeleitet, um Flugdaten anzusehen. Bei einem Fehler wird eine Fehlermeldung auf der Seite angezeigt.

Code 2: Flugdaten Auswertung und Filterung
Der zweite Code stellt eine Seite zur Auswertung und Filterung von Flugdaten bereit, die in JSON-Dateien gespeichert sind. Es enthält ein Skript, das es Benutzern ermöglicht, Flugdaten anzuzeigen, zu filtern und statistisch auszuwerten.

Wichtige Funktionen:

Zugriffsprüfung: Der Code überprüft zu Beginn, ob der Benutzer angemeldet ist, indem er nach einer aktiven Session sucht. Falls keine Anmeldung vorliegt, wird der Benutzer zum Login weitergeleitet.

Datenquelle: Flugdaten werden aus JSON-Dateien (flugdaten/flugdaten_*.json) geladen und in ein Array ($flugdaten) integriert. Dabei werden RFID- und Benutzernamen-Filter auf die Daten angewendet, wenn entsprechende Parameter in der URL gesetzt sind.

Datenanalyse: Der Code erstellt eine Übersicht der Flüge pro Benutzer und zeigt die Gesamtzahl der Flüge jedes Benutzers an. Auch detaillierte Fluginformationen wie Startzeit, Endzeit und Flughöhe werden angezeigt.

Grafische Darstellung: Mit Hilfe von Chart.js wird eine Balkengrafik erzeugt, die die Anzahl der Flüge pro Benutzer darstellt.

PDF-Export: Die Benutzer können die angezeigten Daten (einschließlich der Grafik) als PDF exportieren.

HTML-Struktur:

Ein Formular zur Filterung der Daten nach RFID und Benutzernamen ermöglicht eine detaillierte Anzeige von Flugdaten.

Eine Tabelle listet alle Flugdaten auf, mit Informationen wie RFID, Benutzername, Start- und Endzeit, Datum und Flughöhe.

Eine Schaltfläche ermöglicht das Exportieren der Daten als PDF-Datei, einschließlich der Flugdaten und der erstellten Grafik.

Zusammenfassung:
Code 1 sorgt für eine sichere Anmeldung und leitet den Benutzer zu einer Webseite weiter, die Flugdaten anzeigt.

Code 2 bietet eine detaillierte Analyse der Flugdaten, einschließlich Filteroptionen, grafischer Darstellung und Exportmöglichkeiten der Daten als PDF.

Diese beiden Codes arbeiten zusammen, wobei der erste für den sicheren Zugriff sorgt und der zweite die Datenanalyse und -darstellung übernimmt.
