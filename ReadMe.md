<h1 align="center">Digitales Flugbuch für Modellflug Vereine</h1>
<h3 align="center">Mit der Software und der Verbindung zu einem Raspberry Pi Zero kann eine digitale Aufzeichnung erstellt werden, die den Anforderungen der aktuellen Verordnung (EU) 2019/947 entspricht.</h3>


Funktionsbeschreibung:

RFID-Erkennung und Nutzerverifizierung: Wenn ein Benutzer seinen RFID-Chip auf das Lesegerät legt, wird die aktuelle Uhrzeit zusammen mit dem Namen des Benutzers aus der Benutzerdatei gespeichert. Falls der Benutzer nicht in der Benutzerdatei existiert, wird eine Fehlermeldung ausgegeben.

Erfassung einer zweiten Aktion: Wenn derselbe Benutzer den RFID-Chip erneut auf das Lesegerät legt, wird eine zweite aktuelle Uhrzeit ermittelt. Anschließend muss der Benutzer die Anzahl der Flüge (bzw. Aktionen) über ein Keypad eingeben.

Datenspeicherung: Das Ergebnis (Benutzername, erste Uhrzeit, zweite Uhrzeit, Anzahl der eingegebenen Flüge) wird in einer Zeile gespeichert.







