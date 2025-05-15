#!/bin/bash

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

# CPU-Auslastung (Idle aus top, Nutzung berechnen)
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/")
CPU_USAGE=$(echo "100 - $CPU_IDLE" | bc)

# RAM-Auslastung in MB
RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
RAM_FREE=$(free -m | awk '/Mem:/ {print $4}')

# Speicherplatz Root-Partition in %
DISK_USED=$(df -h / | awk 'NR==2 {print $5}')

# Temperatur (Raspberry Pi spezifisch)
TEMP=$(vcgencmd measure_temp 2>/dev/null | sed 's/temp=//; s/\'C//')

if [ -z "$TEMP" ]; then
    TEMP="N/A"
fi

# Ausgabe im SSE-Format (einmalig)
echo "data: {\"cpu_usage\": \"$CPU_USAGE\", \"ram_used\": \"$RAM_USED\", \"ram_free\": \"$RAM_FREE\", \"ram_total\": \"$RAM_TOTAL\", \"disk_used\": \"$DISK_USED\", \"temp\": \"$TEMP\"}"
echo ""
