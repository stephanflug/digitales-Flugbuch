#!/bin/bash
# Datei: /usr/local/bin/wireguard_setup_minimal.sh
# Zweck: WireGuard + Web-UI (Minimalstatus: IPv4/Verbunden/Traffic) installieren

set -e
LOGFILE="/var/log/wireguard_setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""
set -x

# ------------------------------------------------------------
# 0) Basis
# ------------------------------------------------------------
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
CGI_DIR="/usr/lib/cgi-bin"
WEB_DIR="/var/www/html"
STATUS_CGI="$CGI_DIR/wireguard_status.sh"
GETCONF_CGI="$CGI_DIR/get_wg_conf.sh"
HTML_PATH="$WEB_DIR/wireguard.html"

echo "data: Installiere Pakete..."
sudo apt-get update
sudo apt-get install -y wireguard lighttpd curl ca-certificates

# Lighttpd: CGI für .sh sicherheitshalber aktivieren
if [ ! -f /etc/lighttpd/conf-enabled/10-cgi.conf ]; then
  sudo lighttpd-enable-mod cgi
  sudo tee /etc/lighttpd/conf-enabled/10-cgi.conf >/dev/null <<'CFG'
cgi.assign = ( ".sh" => "/bin/bash" )
alias.url  += ( "/cgi-bin/" => "/usr/lib/cgi-bin/" )
CFG
  sudo systemctl reload lighttpd
fi

# ------------------------------------------------------------
# 1) Konfigurationsdatei vorbereiten
# ------------------------------------------------------------
if [ ! -f "$CONF_PATH" ]; then
  echo "data: Erstelle leere WireGuard-Konfiguration..."
  sudo mkdir -p "$(dirname "$CONF_PATH")"
  echo -e "# Beispiel:\n# [Interface]\n# Address = 10.6.0.2/32\n# PrivateKey = <KEY>\n# DNS = 1.1.1.1\n#\n# [Peer]\n# PublicKey = <SERVER_PUBKEY>\n# AllowedIPs = 0.0.0.0/0\n# Endpoint = server.example.com:51820\n# PersistentKeepalive = 25" | sudo tee "$CONF_PATH" >/dev/null
  sudo chown www-data:www-data "$CONF_PATH"
  sudo chmod 666 "$CONF_PATH"
fi

# ------------------------------------------------------------
# 2) CGI: Konfiguration ausgeben
# ------------------------------------------------------------
sudo tee "$GETCONF_CGI" >/dev/null <<'EOF'
#!/bin/bash
# Gibt die aktuelle WireGuard-Konfiguration als Text aus
set -e
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
EOF
sudo chmod 755 "$GETCONF_CGI"

# ------------------------------------------------------------
# 3) CGI: Minimaler Status (IPv4/Verbunden/Traffic)
# ------------------------------------------------------------
sudo tee "$STATUS_CGI" >/dev/null <<'EOF'
#!/bin/bash
# WireGuard-Minimalstatus für Webanzeige
# Ausgabe: JSON mit iface, ipv4, status (verbunden/getrennt), rx_bytes, tx_bytes

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

# Existiert das Interface?
if ! "$IP_BIN" link show "$WG_IF" >/dev/null 2>&1; then
  printf '{"ok":false,"iface":"%s","status":"nicht aktiv"}\n' "$WG_IF"
  exit 0
fi

# IPv4-Adresse ermitteln
ipv4=$("$IP_BIN" -4 -o addr show dev "$WG_IF" 2>/dev/null | awk '{print $4}' | head -n1)
[ -z "$ipv4" ] && ipv4="(keine)"

# wg dump lesen; mit sudo, falls ohne Rechte
dump="$("$WG_BIN" show "$WG_IF" dump 2>/dev/null || true)"
if [ -z "$dump" ]; then
  dump="$(sudo "$WG_BIN" show "$WG_IF" dump 2>/dev/null || true)"
fi

connected=false
rx_total=0
tx_total=0

if [ -n "$dump" ]; then
  # Zeile 1 ist Interface-Header; Peers ab Zeile 2
  while IFS=$'\t' read -r pub psk endpoint allowed_ips latest_hs rx tx keepalive rest; do
    if [ -n "$latest_hs" ] && [ "$latest_hs" -gt 0 ] 2>/dev/null; then
      now=$(date +%s)
      hs_ago=$(( now - latest_hs ))
      if [ "$hs_ago" -lt 180 ]; then connected=true; fi
    fi
    rx_total=$(( rx_total + (${rx:-0}) ))
    tx_total=$(( tx_total + (${tx:-0}) ))
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

# ------------------------------------------------------------
# 4) HTML-Seite mit Minimal-Status
# ------------------------------------------------------------
sudo tee "$HTML_PATH" >/dev/null <<'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>WireGuard Status</title>
<style>
body{font-family:Arial,sans-serif;background:#f4f7fc;margin:0;padding:24px;}
.container{background:#fff;max-width:860px;margin:0 auto;padding:24px;border-radius:12px;box-shadow:0 6px 16px rgba(0,0,0,.12);}
h1{margin:0 0 16px;}
button{background:#4CAF50;border:none;color:#fff;padding:10px 18px;border-radius:8px;cursor:pointer;font-size:15px}
button:hover{background:#45a049}
pre,textarea{width:100%;box-sizing:border-box}
.status-grid{display:grid;grid-template-columns:170px 1fr;gap:6px 16px;align-items:center}
.mono{font-family:monospace}
.note{color:#666;font-size:13px;margin-top:10px}
</style>
</head>
<body>
<div class="container">
  <h1>WireGuard-Status</h1>
  <hr>

  <div class="status-grid">
    <div><b>Interface:</b></div><div id="st-iface">-</div>
    <div><b>IPv4:</b></div><div id="st-ipv4" class="mono">-</div>
    <div><b>Status:</b></div><div id="st-status">-</div>
    <div><b>Traffic:</b></div><div>RX <span id="st-rx" class="mono">0</span> | TX <span id="st-tx" class="mono">0</span></div>
  </div>

  <p class="note">Aktualisierung alle 5 Sekunden.</p>
  <p><button id="btn-refresh">Status aktualisieren</button></p>

  <hr style="margin:20px 0">

  <h2>Aktuelle Konfiguration</h2>
  <textarea id="cfg" rows="12" readonly placeholder="Konfiguration wird geladen..."></textarea>
  <p class="note">Datei: /opt/digitalflugbuch/data/DatenBuch/wg0.conf</p>

  <p><a href="index.html">Zurück zur Startseite</a></p>
</div>

<script>
function humanBytes(n){n=Number(n||0);const u=['B','KiB','MiB','GiB','TiB'];let i=0;while(n>=1024&&i<u.length-1){n/=1024;i++;}return n.toFixed(1)+' '+u[i];}

async function loadStatus(){
  try{
    const r = await fetch('/cgi-bin/wireguard_status.sh?ts='+Date.now());
    if(!r.ok) throw new Error(r.status+' '+r.statusText);
    const d = await r.json();
    document.getElementById('st-iface').textContent = d.iface||'-';
    document.getElementById('st-ipv4').textContent  = d.ipv4||'-';
    document.getElementById('st-status').textContent= d.status||'-';
    document.getElementById('st-rx').textContent = humanBytes(d.rx_bytes||0);
    document.getElementById('st-tx').textContent = humanBytes(d.tx_bytes||0);
  }catch(e){
    console.error(e);
  }
}

async function loadConfig(){
  try{
    const r = await fetch('/cgi-bin/get_wg_conf.sh?ts='+Date.now());
    document.getElementById('cfg').value = await r.text();
  }catch(e){
    document.getElementById('cfg').value = '# Fehler: '+e;
  }
}

document.getElementById('btn-refresh').addEventListener('click', loadStatus);
loadStatus(); loadConfig();
setInterval(loadStatus, 5000);
</script>
</body>
</html>
EOF

# ------------------------------------------------------------
# 5) sudoers (wg lesen + wg-quick/systemctl steuern)
# ------------------------------------------------------------
echo "data: Ergänze sudoers..."
S1="www-data ALL=(ALL) NOPASSWD: /usr/bin/wg"
S2="www-data ALL=(ALL) NOPASSWD: /usr/bin/wg-quick"
S3="www-data ALL=(ALL) NOPASSWD: /bin/systemctl"
sudo grep -qF "$S1" /etc/sudoers || echo "$S1" | sudo tee -a /etc/sudoers >/dev/null
sudo grep -qF "$S2" /etc/sudoers || echo "$S2" | sudo tee -a /etc/sudoers >/dev/null
sudo grep -qF "$S3" /etc/sudoers || echo "$S3" | sudo tee -a /etc/sudoers >/dev/null

# ------------------------------------------------------------
# 6) Autostart (optional)
# ------------------------------------------------------------
SERVICE_FILE="/etc/systemd/system/wg-custom.service"
if [ ! -f "$SERVICE_FILE" ]; then
  echo "data: Erstelle systemd-Service für WireGuard Autostart..."
  sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=WireGuard VPN (custom config)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/wg-quick up $CONF_PATH
ExecStop=/usr/bin/wg-quick down $CONF_PATH
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable wg-custom.service
fi

# ------------------------------------------------------------
# 7) Link auf Startseite (optional, falls vorhanden)
# ------------------------------------------------------------
INDEX_HTML="$WEB_DIR/index.html"
LINK='<button type="button" onclick="window.location.href='\''wireguard.html'\''">WireGuard</button>'
if [ -f "$INDEX_HTML" ] && ! grep -q "wireguard.html" "$INDEX_HTML"; then
  echo "data: Füge Link in index.html ein..."
  sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML" || true
fi

echo ""
echo "data: Fertig! Seite: http://<IP>/wireguard.html"
echo ""
