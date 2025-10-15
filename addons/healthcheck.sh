#!/bin/bash

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

set -x

# CPU-Idle extrahieren: z.B. aus "Cpu(s):  1.2%us,  0.3%sy,  0.0%ni, 98.0%id, ..."
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | sed -n 's/.*, *\([0-9.]*\)%* id.*/\1/p')

# Falls leer, setze auf 0 (um Fehler zu vermeiden)
if [ -z "$CPU_IDLE" ]; then
    CPU_IDLE=0
fi

# CPU-Auslastung berechnen: 100 - CPU_IDLE
CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", 100 - $CPU_IDLE}")

# RAM-Auslastung in MB
RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
RAM_FREE=$(free -m | awk '/Mem:/ {print $4}')

# Speicherplatz Root-Partition in %
DISK_USED=$(df -h / | awk 'NR==2 {print $5}')

# Temperatur (Raspberry Pi spezifisch)
if command -v vcgencmd >/dev/null 2>&1; then
    TEMP=$(vcgencmd measure_temp 2>/dev/null | sed "s/temp=//; s/'C//")
else
    TEMP="N/A"
fi

# JSON-Ausgabe im SSE-Format
echo "data: {\"cpu_usage\": \"$CPU_USAGE\", \"ram_used\": \"$RAM_USED\", \"ram_free\": \"$RAM_FREE\", \"ram_total\": \"$RAM_TOTAL\", \"disk_used\": \"$DISK_USED\", \"temp\": \"$TEMP\"}"
echo ""

echo "data: Systemstatus erfolgreich ermittelt – Script wird nun entfernt..."
echo ""

# Script-Pfad ermitteln und löschen
SCRIPT_PATH="$(realpath "$0")"
rm -f "$SCRIPT_PATH"

exit 0
