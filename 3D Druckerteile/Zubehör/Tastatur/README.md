# Tastatur-Abdeckung für 4x4 Matrix-Keypad

Dieses Verzeichnis enthält eine 3D-druckbare Abdeckung für eine 4x4 Matrix-Tastatur. Die Abdeckung ist als Zubehör für das digitale Flugbuch gedacht und kann zur sauberen Montage eines 16-Tasten-Keypads verwendet werden.

## Dateien

| Datei | Beschreibung |
|---|---|
| [`Tastatur Abdeckung.stl`](./Tastatur%20Abdeckung.stl) | STL-Datei für den 3D-Druck der Tastatur-Abdeckung. |
| [`4x4_Keypad_Tastatur_Datenblatt_AZ-Delivery_Vertriebs_GmbH.pdf`](./4x4_Keypad_Tastatur_Datenblatt_AZ-Delivery_Vertriebs_GmbH.pdf) | Datenblatt des verwendeten 4x4 Matrix-Keypads mit technischen Daten, Pinout und Anschlussbeispielen. |

### Anschlussbelegung

| Alter Anschluss / Steuerung | Neue 4x4-Tastatur |
|---:|---:|
| 1 | 5 |
| 2 | 6 |
| 3 | 7 |
| 4 | 8 |
| 5 | 1 |
| 6 | 2 |
| 7 | 3 |
| 8 | 4 |



## Verwendungszweck

Die Abdeckung dient dazu, das 4x4 Keypad mechanisch sauber in ein Gehäuse oder Bedienfeld zu integrieren

## Montage

1. STL-Datei im Slicer öffnen.
2. Druckausrichtung und Skalierung prüfen.
3. Abdeckung drucken.
4. Druckteil entgraten und Passform mit dem Keypad testen.
5. Keypad einsetzen und mechanisch befestigen.
6. Anschlussleitungen gemäß Pinout oder eigenem Schaltplan verbinden.
7. Funktionstest jeder Taste durchführen.

## Sicherheitshinweise

- Vor dem Anschluss Spannungsversorgung trennen.
- Keine GPIO-Pins des Raspberry Pi mit 5 V oder 24 V beaufschlagen.
- Pinout vor dem Einschalten prüfen.
- Kurzschlüsse durch offene Kontakte oder falsch gesteckte Leitungen vermeiden.
