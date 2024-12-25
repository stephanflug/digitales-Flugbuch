<?php
header('Content-Type: text/html; charset=ISO-8859-1');
?>


<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Flugbuch Auswertung</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f4f4f4;
        }
        h1 {
            color: #333;
            text-align: center;
        }
        .container {
            width: 80%;
            margin: 0 auto;
            background-color: #fff;
            padding: 20px;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 30px;
            background-color: #fafafa;
        }
        table, th, td {
            border: 1px solid #ddd;
        }
        th, td {
            padding: 10px;
            text-align: left;
        }
        th {
            background-color: #f4f4f4;
        }
        td a {
            color: #1a73e8;
            text-decoration: none;
        }
        td a:hover {
            text-decoration: underline;
        }
        .chart-container {
            width: 100%;
            max-width: 800px;
            margin: 0 auto;
        }
        canvas {
            max-width: 100%;
        }
        .no-files {
            text-align: center;
            color: red;
        }
        .month-container {
            margin-bottom: 30px;
            border: 2px solid #ddd;
            padding: 15px;
            border-radius: 8px;
            background-color: #f9f9f9;
        }
        .month-header {
            font-size: 1.2em;
            font-weight: bold;
            color: #333;
            margin-bottom: 10px;
        }
    </style>
</head>
<body>

<h1>Flugbuch Auswertung</h1>

<div class="container">
    <?php
    // Fehleranzeige aktivieren (falls notwendig)
    ini_set('display_errors', 1);
    error_reporting(E_ALL);// Verzeichnis mit den Logdateien
$logVerzeichnis = '/var/www/vereinMuster/addons/flugbuch/';
$dateiformat = 'flugbuch_*.log.txt';

// Alle Logdateien im Verzeichnis suchen
$logdateien = glob($logVerzeichnis . $dateiformat);

// Array f r die Monatsunterteilung
$monate = [];
$flugDaten = []; // Diese Datenstruktur wird f r die Grafik genutzt

//  berpr fen, ob Logdateien gefunden wurden
if ($logdateien) {
    // Dateien nach  nderungszeit sortieren (neueste zuerst)
    usort($logdateien, function($a, $b) {
        return filemtime($b) - filemtime($a);  // Sortieren nach  nderungszeit
    });

    foreach ($logdateien as $datei) {
        // Den Dateinamen extrahieren
        $dateiname = basename($datei);

        // Jahr und Monat aus dem Dateinamen extrahieren
        preg_match('/flugbuch_(\d{4})-(\d{2})/', $dateiname, $matches);
        $jahr = $matches[1] ?? '';
        $monat = $matches[2] ?? '';

        $monatKey = "$jahr-$monat";  // Schl ssel f r die Monatsunterteilung

        // Dateiinhalt lesen
        $daten = file($datei, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

        foreach ($daten as $zeile) {
            // Zeile parsen und relevante Daten extrahieren
            preg_match('/RFID:(\d+):\s([^:]+):/', $zeile, $rfidMatch); // RFID und Pilot
            preg_match('/Startzeit:(.*?)\s"Ende:/', $zeile, $startMatch); // Startzeit
            preg_match('/Ende:(.*?)\s"Fluganzahl:/', $zeile, $endeMatch); // Endzeit
            preg_match('/Fluganzahl:(\d+)/', $zeile, $flugMatch); // Fluganzahl

            $rfid = $rfidMatch[1] ?? 'Unbekannt';
            $pilot = $rfidMatch[2] ?? 'Unbekannt';
            $startzeit = isset($startMatch[1]) ? trim($startMatch[1]) : 'Unbekannt';
            $endzeit = isset($endeMatch[1]) ? trim($endeMatch[1]) : 'Unbekannt';
            $fluganzahl = isset($flugMatch[1]) ? (int)$flugMatch[1] : 0;

            // Flugdaten pro Pilot sammeln
            if (!isset($monate[$monatKey][$pilot])) {
                $monate[$monatKey][$pilot] = [
                    'rfid' => $rfid,
                    'fluganzahl' => 0,
                    'details' => [],
                ];
            }
            $monate[$monatKey][$pilot]['fluganzahl'] += $fluganzahl;
            $monate[$monatKey][$pilot]['details'][] = [
                'startzeit' => $startzeit,
                'endzeit' => $endzeit,
                'fluganzahl' => $fluganzahl
            ];

            // Daten f r die Grafik sammeln
            if (!isset($flugDaten[$pilot])) {
                $flugDaten[$pilot] = 0;
            }
            $flugDaten[$pilot] += $fluganzahl;
        }
    }

    // Anzeige der Logdateien nach Monat gruppiert
    foreach ($monate as $monatKey => $piloten) {
        echo "<div class='month-container'>";
        echo "<div class='month-header'>Monat: " . date("F Y", strtotime($monatKey . "-01")) . "</div>";

        // Tabelle f r die Logdateien des jeweiligen Monats
        echo "<table>";
        echo "<thead><tr><th>Pilot</th><th>RFID</th><th>Details</th><th>Gesamtfluganzahl</th></tr></thead><tbody>";

        // Anzeige f r jeden Pilot im Monat
        foreach ($piloten as $pilot => $info) {
            echo "<tr>";
            echo "<td>$pilot</td>";
            echo "<td>{$info['rfid']}</td>";

            // Details f r jeden Eintrag des Piloten
            $details = "";
            foreach ($info['details'] as $detail) {
                $details .= "Startzeit: {$detail['startzeit']} | Endzeit: {$detail['endzeit']} | Fluganzahl: {$detail['fluganzahl']}<br>";
            }
            echo "<td>$details</td>";

            // Gesamtfluganzahl des Piloten
            echo "<td>{$info['fluganzahl']}</td>";
            echo "</tr>";
        }

        echo "</tbody></table>";
        echo "</div>";
    }
} else {
    echo "<p class='no-files'>Keine Logdateien gefunden.</p>";
}
    ?>

    <div class="chart-container">
        <h2>Fluganzahl pro Pilot</h2>
        <canvas id="flugbuchChart"></canvas>
    </div>

</div>

<script>
// Daten f r die Grafik vorbereiten
const labels = <?php echo json_encode(array_keys($flugDaten)); ?>;
const values = <?php echo json_encode(array_values($flugDaten)); ?>;

// Chart.js Grafik erstellen
const ctx = document.getElementById('flugbuchChart').getContext('2d');
new Chart(ctx, {
    type: 'bar', // oder 'line', 'pie', etc.
    data: {
        labels: labels,
        datasets: [{
            label: 'Fluganzahl pro Pilot',
            data: values,
            backgroundColor: 'rgba(75, 192, 192, 0.2)',
            borderColor: 'rgba(75, 192, 192, 1)',
            borderWidth: 1
        }]
    },
    options: {
        responsive: true,
        plugins: {
            legend: {
                display: true
            }
        },
        scales: {
            y: {
                beginAtZero: true
            }
        }
    }
});
</script>
</body>
</html>

