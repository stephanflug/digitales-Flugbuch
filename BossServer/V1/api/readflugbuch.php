<?php
header('Content-Type: text/html; charset=ISO-8859-1');
?>

<?php
session_start();
if (!isset($_SESSION['user'])) {
    header('Location: login.php');
    exit;
}
?>


<?php
$flugdatenVerzeichnis = "flugdaten";
$flugdatenFiles = glob($flugdatenVerzeichnis . "/flugdaten_*.json");

$flugdaten = [];
foreach ($flugdatenFiles as $filename) {
    $data = json_decode(file_get_contents($filename), true);
    if (is_array($data)) {
        $flugdaten = array_merge($flugdaten, $data);
    }
}

$alleRFIDs = [];
$alleBenutzernamen = [];

foreach ($flugdaten as $entry) {
    if (!empty($entry['rfid'])) {
        $alleRFIDs[] = $entry['rfid'];
    }
    $name = $entry['benutzername'] ?? $entry['name'] ?? null;
    if (!empty($name)) {
        $alleBenutzernamen[] = $name;
    }
}

$alleRFIDs = array_unique($alleRFIDs);
sort($alleRFIDs);

$alleBenutzernamen = array_unique($alleBenutzernamen);
sort($alleBenutzernamen);

$rfidFilter = $_GET['rfid'] ?? '';
$benutzernameFilter = $_GET['benutzername'] ?? '';

if (!empty($rfidFilter) || !empty($benutzernameFilter)) {
    $flugdaten = array_filter($flugdaten, function ($entry) use ($rfidFilter, $benutzernameFilter) {
        $rfidMatch = true;
        $nameMatch = true;

        if (!empty($rfidFilter)) {
            $rfidMatch = isset($entry['rfid']) && $entry['rfid'] === $rfidFilter;
        }

        if (!empty($benutzernameFilter)) {
            $benutzername = $entry['benutzername'] ?? $entry['name'] ?? '';
            $nameMatch = $benutzername === $benutzernameFilter;
        }

        return $rfidMatch && $nameMatch;
    });
}

$flugStatistik = [];
$flugDetailsProBenutzer = [];

foreach ($flugdaten as $entry) {
    $benutzername = $entry['benutzername'] ?? $entry['name'] ?? 'Unbekannt';
    if (!isset($flugStatistik[$benutzername])) {
        $flugStatistik[$benutzername] = 0;
    }
    $flugStatistik[$benutzername]++;
    $flugDetailsProBenutzer[$benutzername][] = [
        'startzeit' => $entry['startzeit'] ?? '',
        'endzeit' => $entry['endzeit'] ?? ''
    ];
}

usort($flugdaten, function ($a, $b) {
    return strtotime($b['startzeit']) - strtotime($a['startzeit']);
});
?>

<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <title>Flugdaten Auswertung</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.5.28/jspdf.plugin.autotable.min.js"></script>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: #f4f4f9;
            margin: 0;
            padding: 0;
        }

        h1, h2 {
            text-align: center;
            color: #333;
        }

        .container {
            width: 90%;
            max-width: 1200px;
            margin: 20px auto;
            padding: 20px;
            background-color: #fff;
            border-radius: 10px;
            box-shadow: 0 0 15px rgba(0, 0, 0, 0.1);
        }

        .filter-form {
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 15px;
            flex-wrap: wrap;
            margin-bottom: 20px;
        }

        .filter-form select,
        .filter-form input[type="submit"] {
            padding: 8px 12px;
            font-size: 14px;
            border-radius: 5px;
            border: 1px solid #ccc;
            background-color: #f9f9f9;
        }

        canvas {
            width: 100%;
            height: auto;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }

        th, td {
            padding: 12px;
            text-align: left;
            border: 1px solid #ddd;
        }

        th {
            background-color: #f2f2f2;
        }

        tbody tr:nth-child(odd) {
            background-color: #f9f9f9;
        }

        @media (max-width: 768px) {
            .filter-form {
                flex-direction: column;
                gap: 10px;
            }

            table, canvas {
                font-size: 12px;
            }

            table th, table td {
                padding: 8px;
            }
        }

        #exportPdfBtn {
            margin: 20px 0;
            padding: 10px 20px;
            background-color: #4CAF50;
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
        }
    </style>
</head>
<body>

<div class="container">
    <h1>Flugdaten Auswertung</h1>

    <button id="exportPdfBtn">Exportieren als PDF</button>

    <div class="filter-form">
        <form method="GET" action="">
            <label for="rfid">RFID:</label>
            <select name="rfid" id="rfid">
                <option value="">-- Alle --</option>
                <?php foreach ($alleRFIDs as $rfid): ?>
                    <option value="<?= htmlspecialchars($rfid) ?>" <?= $rfid === $rfidFilter ? 'selected' : '' ?>>
                        <?= htmlspecialchars($rfid) ?>
                    </option>
                <?php endforeach; ?>
            </select>

            <label for="benutzername">Benutzername:</label>
            <select name="benutzername" id="benutzername">
                <option value="">-- Alle --</option>
                <?php foreach ($alleBenutzernamen as $name): ?>
                    <option value="<?= htmlspecialchars($name) ?>" <?= $name === $benutzernameFilter ? 'selected' : '' ?>>
                        <?= htmlspecialchars($name) ?>
                    </option>
                <?php endforeach; ?>
            </select>

            <input type="submit" value="Filtern">
        </form>
    </div>

    <h2>Fluganzahl pro Benutzer (Gesamtübersicht)</h2>
    <canvas id="gesamtChart" width="400" height="200"></canvas>

    <script>
        const ctx = document.getElementById('gesamtChart').getContext('2d');
        const statistik = <?= json_encode($flugStatistik) ?>;
        const labels = Object.keys(statistik);
        const values = Object.values(statistik);

        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Anzahl Flüge',
                    data: values,
                    backgroundColor: 'rgba(54, 162, 235, 0.6)',
                    borderColor: 'rgba(54, 162, 235, 1)',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        beginAtZero: true
                    }
                }
            }
        });

        document.getElementById('exportPdfBtn').addEventListener('click', () => {
            const { jsPDF } = window.jspdf;
            const doc = new jsPDF();

            doc.setFontSize(18);
            doc.text('Flugdaten Auswertung', 14, 20);

            const canvas = document.getElementById('gesamtChart');
            const imgData = canvas.toDataURL('image/png');
            doc.addImage(imgData, 'PNG', 15, 30, 180, 100);

            doc.setFontSize(12);
            doc.text('Flugdaten Tabelle:', 14, 140);

            doc.autoTable({
                html: 'table',
                startY: 150,
                styles: { fontSize: 8 },
                headStyles: { fillColor: [54, 162, 235] },
                margin: { left: 14, right: 14 }
            });

            const finalY = doc.lastAutoTable.finalY || 160;
            doc.setFontSize(10);
            doc.text('Power by Ebner Stephan', 14, finalY + 10);

            doc.save('Flugdaten_Auswertung.pdf');
        });
    </script>

    <h2>Flugdaten Tabelle</h2>
    <table>
        <thead>
            <tr>
                <th>RFID</th>
                <th>Benutzername</th>
                <th>Startzeit</th>
                <th>Endzeit</th>
                <th>Datum</th>
                <th>Flughöhe (m)</th>
                <th>Luftraumbeobachter</th>
            </tr>
        </thead>
        <tbody>
            <?php if (empty($flugdaten)): ?>
                <tr>
                    <td colspan="7" style="text-align: center;">Keine Daten gefunden</td>
                </tr>
            <?php else: ?>
                <?php foreach ($flugdaten as $entry): ?>
                    <tr>
                        <td><?= htmlspecialchars($entry['rfid'] ?? 'N/A') ?></td>
                        <td><?= htmlspecialchars($entry['benutzername'] ?? $entry['name'] ?? 'N/A') ?></td>
                        <td><?= htmlspecialchars($entry['startzeit'] ?? 'N/A') ?></td>
                        <td><?= htmlspecialchars($entry['endzeit'] ?? 'N/A') ?></td>
                        <td><?= isset($entry['startzeit']) ? date('d.m.Y H:i:s', strtotime($entry['startzeit'])) : 'N/A' ?></td>
                        <td><?= htmlspecialchars($entry['FlughÃ¶he'] ?? 'N/A') ?></td>
                        <td><?= htmlspecialchars($entry['Luftraumbeobachter'] ?? 'N/A') ?></td>
                    </tr>
                <?php endforeach; ?>
            <?php endif; ?>
        </tbody>
    </table>
</div>

</body>
</html>
