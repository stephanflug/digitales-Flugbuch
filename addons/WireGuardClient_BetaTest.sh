#!/bin/bash
# Datei: /usr/local/bin/wireguard_setup_full.sh
# Beschreibung: Installiert WireGuard + Weboberfläche + CGI-Steuerung
# Getestet unter Debian / Raspberry Pi OS (lighttpd)

LOGFILE="/var/log/wireguard_setup.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""
set -x

echo "data: Starte Installation von WireGuard..."
echo ""

# 1. WireGuard installieren
sudo apt update
sudo apt install -y wireguard

# 2. Konfigurationsdatei vorbereiten
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
if [ ! -f "$CONF_PATH" ]; then
  echo "data: Erstelle leere WireGuard-Konfiguration..."
  sudo mkdir -p "$(dirname "$CONF_PATH")"
  sudo touch "$CONF_PATH"
  sudo chown www-data:www-data "$CONF_PATH"
  sudo chmod 666 "$CONF_PATH"
fi

# 3. CGI: control.sh
CGI_SCRIPT="/usr/lib/cgi-bin/wireguard_control.sh"
sudo tee "$CGI_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
echo "Content-type: text/html"
echo ""

WG_CONF="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
POST_DATA=$(cat)

urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

DECODED=$(urldecode "$POST_DATA")
ACTION=$(printf '%s\n' "$DECODED" | sed -n 's/.*action=\([^&]*\).*/\1/p')
CONFIG_CONTENT="${DECODED#*config=}"
CONFIG_CONTENT="${CONFIG_CONTENT%%&action=*}"

html_response() {
  cat <<HTML
<html>
  <body>
    <h2>$1</h2>
    <pre style="background:#f0f0f0;padding:10px;border-radius:4px;">$2</pre>
    <a href="/wireguard.html">Zur&uuml;ck zur Startseite</a>
  </body>
</html>
HTML
}

case "$ACTION" in
  start)
    OUTPUT=$(sudo wg-quick up "$WG_CONF" 2>&1)
    RET=$?
    if [ $RET -eq 0 ]; then
      html_response "WireGuard aktiviert." "$OUTPUT"
    else
      html_response "Fehler beim Starten von WireGuard (Code $RET):" "$OUTPUT"
    fi
    ;;
  stop)
    OUTPUT=$(sudo wg-quick down "$WG_CONF" 2>&1)
    RET=$?
    if [ $RET -eq 0 ]; then
      html_response "WireGuard deaktiviert." "$OUTPUT"
    else
      html_response "Fehler beim Stoppen von WireGuard (Code $RET):" "$OUTPUT"
    fi
    ;;
  update)
    if [ -n "$CONFIG_CONTENT" ]; then
      OUTPUT=$(printf '%s\n' "$CONFIG_CONTENT" | sudo tee "$WG_CONF" 2>&1)
      sudo chmod 666 "$WG_CONF"
      html_response "Konfiguration gespeichert." "$OUTPUT"
    else
      html_response "Keine Konfigurationsdaten übermittelt." ""
    fi
    ;;
  autostart-on)
    OUTPUT=$(sudo systemctl enable wg-custom.service 2>&1)
    html_response "Autostart aktiviert." "$OUTPUT"
    ;;
  autostart-off)
    OUTPUT=$(sudo systemctl disable wg-custom.service 2>&1)
    html_response "Autostart deaktiviert." "$OUTPUT"
    ;;
  autostart-status)
    OUTPUT=$(systemctl is-enabled wg-custom.service 2>&1)
    html_response "Autostart-Status:" "$OUTPUT"
    ;;
  *)
    html_response "Unbekannte Aktion: '$ACTION'." ""
    ;;
esac
EOF
sudo chmod +x "$CGI_SCRIPT"

# 4. CGI: get_wg_conf.sh
GET_CONF="/usr/lib/cgi-bin/get_wg_conf.sh"
sudo tee "$GET_CONF" > /dev/null << 'EOF'
#!/bin/bash
# CGI-Skript zum Auslesen der aktuellen WireGuard-Konfiguration
WG_CONF="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"

echo "Content-Type: text/plain; charset=utf-8"
echo "Cache-Control: no-cache, no-store, must-revalidate"
echo "Pragma: no-cache"
echo "Expires: 0"
echo ""

if [ ! -f "$WG_CONF" ]; then
  echo "# FEHLER: $WG_CONF existiert nicht."
  exit 0
fi
if [ ! -r "$WG_CONF" ]; then
  echo "# FEHLER: Keine Leserechte für $WG_CONF (Benutzer: $(whoami))"
  exit 0
fi
cat "$WG_CONF"
exit 0
EOF
sudo chmod +x "$GET_CONF"

# 4b. CGI: wireguard_status.sh (neu und stabil)
#!/bin/bash
# WireGuard-Minimalstatus für Webanzeige
# Gibt JSON mit IP, Status (verbunden/aus) und Traffic aus.

set -e
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WG_IF="wg0"
WG_BIN="$(command -v wg || echo /usr/bin/wg)"
IP_BIN="$(command -v ip || echo /usr/sbin/ip)"

echo "Content-Type: application/json; charset=utf-8"
echo "Cache-Control: no-cache, no-store, must-revalidate"
echo "Pragma: no-cache"
echo "Expires: 0"
echo ""

# Prüfen ob Interface existiert
if ! "$IP_BIN" link show "$WG_IF" >/dev/null 2>&1; then
  printf '{"ok":false,"iface":"%s","status":"nicht aktiv"}\n' "$WG_IF"
  exit 0
fi

# IPv4-Adresse auslesen
ipv4=$("$IP_BIN" -4 -o addr show dev "$WG_IF" 2>/dev/null | awk '{print $4}' | head -n1)
[ -z "$ipv4" ] && ipv4="(keine)"

# Peer-Daten holen
dump="$(sudo "$WG_BIN" show "$WG_IF" dump 2>/dev/null || true)"

# Standardwerte
connected=false
rx_total=0
tx_total=0

if [ -n "$dump" ]; then
  # Zeilen ab Zeile 2 (Peers)
  while IFS=$'\t' read -r pub psk endpoint allowed_ips latest_hs rx tx keepalive rest; do
    # Handshake jünger als 180s → verbunden
    if [ -n "$latest_hs" ] && [ "$latest_hs" -gt 0 ]; then
      hs_ago=$(( $(date +%s) - latest_hs ))
      if [ "$hs_ago" -lt 180 ]; then connected=true; fi
    fi
    rx_total=$((rx_total + rx))
    tx_total=$((tx_total + tx))
  done < <(printf '%s\n' "$dump" | tail -n +2)
fi

status_text=$($connected && echo "verbunden" || echo "getrennt")

printf '{'
printf '"ok":true,'
printf '"iface":"%s",' "$WG_IF"
printf '"ipv4":"%s",' "$ipv4"
printf '"status":"%s",' "$status_text"
printf '"rx_bytes":%s,' "$rx_total"
printf '"tx_bytes":%s' "$tx_total"
printf '}\n'

EOF
sudo chmod 755 "$STATUS_CGI"

# 5. HTML: wireguard.html
HTML_PATH="/var/www/html/wireguard.html"
sudo tee "$HTML_PATH" > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>WireGuard Steuerung</title>
<style>
body{font-family:Arial,sans-serif;background-color:#f4f7fc;margin:0;padding:0;display:flex;justify-content:center;align-items:center;height:100vh;}
.container{background-color:#fff;padding:30px;border-radius:12px;box-shadow:0 6px 16px rgba(0,0,0,0.15);max-width:800px;width:100%;text-align:center;}
button{background-color:#4CAF50;color:#fff;padding:10px 20px;border:none;border-radius:8px;cursor:pointer;font-size:16px;margin:5px;transition:0.3s;}
button:hover{background-color:#45a049;transform:scale(1.05);}
textarea{width:100%;height:200px;font-family:monospace;padding:10px;border-radius:8px;border:1px solid #ccc;margin-top:10px;}
</style>
</head>
<body>
<div class="container">
<h1>WireGuard Client Steuerung</h1>

<form method="post" action="/cgi-bin/wireguard_control.sh">
<button type="submit" name="action" value="start">Verbindung aktivieren</button>
<button type="submit" name="action" value="stop">Verbindung deaktivieren</button>
</form>

<form method="post" action="/cgi-bin/wireguard_control.sh">
<h2>Konfiguration bearbeiten</h2>
<textarea name="config" placeholder="[Interface] …"></textarea><br>
<button type="submit" name="action" value="update">Konfiguration speichern</button>
</form>

<form method="post" action="/cgi-bin/wireguard_control.sh">
<h2>Autostart-Verwaltung</h2>
<button type="submit" name="action" value="autostart-on">Autostart aktivieren</button>
<button type="submit" name="action" value="autostart-off">Autostart deaktivieren</button>
<button type="submit" name="action" value="autostart-status">Autostart-Status anzeigen</button>
</form>

<a href="index.html">Zur&uuml;ck zur Startseite</a>

<hr style="margin:24px 0;border:none;border-top:1px solid #ddd">
<h2>WireGuard-Status</h2>
<div id="wg-status" style="text-align:left; margin:0 auto; max-width:680px;">
<div><b>Interface:</b> <span id="st-iface">-</span></div>
<div><b>Status:</b> <span id="st-state">-</span></div>
<div><b>Adresse(n) v4:</b> <span id="st-v4">-</span></div>
<div><b>Adresse(n) v6:</b> <span id="st-v6">-</span></div>
<div><b>Peers:</b></div>
<div id="st-peers" style="font-family:monospace; background:#f7f7f7; padding:10px; border-radius:8px; white-space:pre-wrap;">(lade…)</div>
<button type="button" id="btn-refresh-status" style="margin-top:10px;">Status aktualisieren</button>
</div>

<div class="footer-note">Powered by Ebner Stephan</div>
</div>

<script>
const ta=document.querySelector('textarea[name="config"]');
fetch('/cgi-bin/get_wg_conf.sh?ts='+Date.now())
.then(r=>{if(!r.ok)throw new Error(r.status+' '+r.statusText);return r.text();})
.then(cfg=>ta.value=cfg)
.catch(err=>{console.error('Konfig nicht geladen:',err);ta.value='# Fehler: '+err;});

function humanBytes(n){n=Number(n||0);const u=['B','KiB','MiB','GiB'];let i=0;while(n>=1024&&i<u.length-1){n/=1024;i++;}return n.toFixed(1)+' '+u[i];}
function humanAgo(s){s=Number(s||0);if(s<0)return'n/a';if(s<60)return s+'s';if(s<3600)return Math.floor(s/60)+'m';if(s<86400)return Math.floor(s/3600)+'h';return Math.floor(s/86400)+'d';}

function renderStatus(d){
document.getElementById('st-iface').textContent=d.iface||'-';
document.getElementById('st-state').textContent=d.state||'-';
document.getElementById('st-v4').textContent=(d.addresses_v4||[]).join(', ')||'-';
document.getElementById('st-v6').textContent=(d.addresses_v6||[]).join(', ')||'-';
const box=document.getElementById('st-peers');
if(!d.ok){box.textContent='Fehler: '+(d.error||'unbekannt');return;}
if(!d.peers||d.peers.length===0){box.textContent='(keine Peers)';return;}
const lines=d.peers.map(p=>[
`Peer:        ${p.public_key}`,
`Endpoint:    ${p.endpoint}`,
`Allowed IPs: ${p.allowed_ips}`,
`Handshake:   ${humanAgo(p.latest_handshake_ago)}`,
`Traffic:     RX ${humanBytes(p.transfer_rx)} | TX ${humanBytes(p.transfer_tx)}`,
`Keepalive:   ${p.persistent_keepalive}`,
''].join('\n'));
box.textContent=lines.join('\n');
}

async function loadStatus(){
try{
const r=await fetch('/cgi-bin/wireguard_status.sh?ts='+Date.now());
if(!r.ok)throw new Error(r.status+' '+r.statusText);
renderStatus(await r.json());
}catch(e){
console.error('Status-Fehler:',e);
renderStatus({ok:false,error:String(e),iface:'wg0'});
}
}

document.getElementById('btn-refresh-status').addEventListener('click',loadStatus);
loadStatus();
setInterval(loadStatus,5000);
</script>
</body></html>
EOF

# 6. Sudoers
SUDO_LINE1="www-data ALL=(ALL) NOPASSWD: /usr/bin/wg-quick"
SUDO_LINE2="www-data ALL=(ALL) NOPASSWD: /bin/systemctl"
if ! sudo grep -qF "$SUDO_LINE1" /etc/sudoers; then echo "$SUDO_LINE1" | sudo tee -a /etc/sudoers > /dev/null; fi
if ! sudo grep -qF "$SUDO_LINE2" /etc/sudoers; then echo "$SUDO_LINE2" | sudo tee -a /etc/sudoers > /dev/null; fi

# 7. index.html Link hinzufügen
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''wireguard.html'\''">WireGuard</button>'
if ! grep -q "wireguard.html" "$INDEX_HTML"; then
  echo "data: Füge WireGuard-Link zur index.html hinzu..."
  sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML"
fi

# 8. systemd Service
SERVICE_FILE="/etc/systemd/system/wg-custom.service"
if [ ! -f "$SERVICE_FILE" ]; then
  echo "data: Erstelle systemd-Service für WireGuard Autostart..."
  sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=WireGuard VPN (custom config)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/wg-quick up /opt/digitalflugbuch/data/DatenBuch/wg0.conf
ExecStop=/usr/bin/wg-quick down /opt/digitalflugbuch/data/DatenBuch/wg0.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable wg-custom.service
fi

echo ""
echo "data: Fertig! Öffne im Browser: http://<IP>/wireguard.html"
echo ""
