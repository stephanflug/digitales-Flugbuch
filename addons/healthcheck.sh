#!/bin/bash

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

# CPU-Idle aus top holen und CPU-Auslastung berechnen mit awk
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk -F'id,' '{ split($1,a,","); sub(".* ", "", a[2]); print a[2] }' | tr -d ' ')
CPU_USAGE=$(awk "BEGIN {printf \"%.1f\", 100 - $CPU_IDLE}")

# RAM-Auslastung in MB
RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
RAM_FREE=$(free -m | awk '/Mem:/ {print $4}')

# Speicherplatz Root-Partition in %
DISK_USED=$(df -h / | awk 'NR==2 {print $5}')

# Temperatur (Raspberry Pi spezifisch), ohne Fehler bei fehlendem vcgencmd
if command -v vcgencmd >/dev/null 2>&1; then
    TEMP=$(vcgencmd measure_temp 2>/dev/null | sed "s/temp=//; s/'C//")
else
    TEMP="N/A"
fi

echo "data: {\"cpu_usage\": \"$CPU_USAGE\", \"ram_used\": \"$RAM_USED\", \"ram_free\": \"$RAM_FREE\", \"ram_total\": \"$RAM_TOTAL\", \"disk_used\": \"$DISK_USED\", \"temp\": \"$TEMP\"}"
echo ""
