#!/bin/bash

LOGFILE="/var/log/wireguard_setup.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

exec 2>&1
set -x

echo "data: Starte Installation von WireGuard..."
echo ""

# 1. WireGuard installieren (ohne resolvconf)
sudo apt update
sudo apt install -y wireguard

# 2. Konfiguration vorbereiten
CONF_PATH="/opt/digitalflugbuch/data/DatenBuch/wg0.conf"
if [ ! -f "$CONF_PATH" ]; then
  echo "data: Erstelle leere WireGuard-Konfiguration..."
  sudo mkdir -p "$(dirname "$CONF_PATH")"
  sudo touch "$CONF_PATH"
  sudo chown www-data:www-data "$CONF_PATH"
  sudo chmod 666 "$CONF_PATH"
fi

# 3. CGI-Skript: control (UNVERÄNDERT)
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

# 4. CGI-Skript: get current config (UNVERÄNDERT)
GET_CONF="/usr/lib/cgi-bin/get_wg_conf.sh"
sudo tee "$GET_CONF" > /dev/null << 'EOF'
#!/bin/bash

#EBST geändert am 19.10.2025
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

# 4b. NEU: CGI-Skript – Minimal-Status (IPv4 / verbunden / RX/TX)
STATUS_CGI="/usr/lib/cgi-bin/wireguard_status.sh"
sudo tee "$STATUS_CGI" > /dev/null << 'EOF'
#!/bin/bash
# WireGuard-Minimalstatus für Webanzeige
# JSON: iface, ipv4, status (verbunden/getrennt), rx_bytes, tx_bytes

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

# Interface vorhanden?
if ! "$IP_BIN" link show "$WG_IF" >/dev/null 2>&1; then
  printf '{"ok":false,"iface":"%s","status":"nicht aktiv","ipv4":"(keine)","rx_bytes":0,"tx_bytes":0}\n' "$WG_IF"
  exit 0
fi

# IPv4-Adresse
ipv4=$("$IP_BIN" -4 -o addr show dev "$WG_IF" 2>/dev/null | awk '{print $4}' | head -n1)
[ -z "$ipv4" ] && ipv4="(keine)"

# Peer-Daten – erst ohne, dann mit sudo (falls Rechte fehlen)
dump="$("$WG_BIN" show "$WG_IF" dump 2>/dev/null || true)"
if [ -z "$dump" ]; then
  dump="$(sudo "$WG_BIN" show "$WG_IF" dump 2>/dev/null || true)"
fi

connected=false
rx_total=0
tx_total=0
if [ -n "$dump" ]; then
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

# 5. HTML-Datei – erweitert um Status & Hintergrund 'flyer.png'
HTML_PATH="/var/www/html/wireguard.html"
sudo tee "$HTML_PATH" > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>WireGuard Steuerung</title>
  <style>
    :root{
      --glass-bg: rgba(255,255,255,0.92);
      --shadow: 0 10px 30px rgba(0,0,0,0.25);
      --brand: #2f7dff;
      --ok: #1aa06d;
      --bad: #cc3333;
    }
    body {
      font-family: Arial, sans-serif;
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: url('flyer.png') no-repeat center center fixed;
      background-size: cover;
      padding: 24px;
    }
    .container {
      background: var(--glass-bg);
      backdrop-filter: blur(4px);
      -webkit-backdrop-filter: blur(4px);
      padding: 28px;
      border-radius: 16px;
      box-shadow: var(--shadow);
      width: min(920px, 100%);
    }
    h1 {
      font-size: 28px;
      margin: 0 0 12px;
    }
    h2 {
      margin: 18px 0 8px;
      font-size: 20px;
    }
    form { margin: 12px 0; }
    .row { display: flex; flex-wrap: wrap; gap: 10px; }
    button {
      background: var(--brand);
      color: #fff;
      padding: 10px 16px;
      border: none;
      border-radius: 10px;
      cursor: pointer;
      font-size: 15px;
      transition: transform .08s ease, opacity .15s ease;
    }
    button:hover { transform: translateY(-1px); opacity: .95; }
    .btn-ok { background: var(--ok); }
    .btn-bad{ background: var(--bad); }
    textarea {
      width: 100%;
      height: 220px;
      font-family: monospace;
      padding: 10px;
      border-radius: 10px;
      border: 1px solid #d8d8d8;
      background: #fff;
      box-sizing: border-box;
    }
    .grid { display:grid; grid-template-columns: 170px 1fr; gap:6px 16px; align-items:center; }
    .pill { display:inline-block; padding:3px 8px; border-radius:999px; font-weight:600; font-size:13px; }
    .pill.ok { background:#e9f7f1; color:#0c7a56; border:1px solid #bfe6d7; }
    .pill.bad{ background:#fdeeee; color:#a52020; border:1px solid #f3c3c3; }
    .mono { font-family: monospace; }
    .footer { margin-top: 18px; font-size: 13px; color: #333; opacity:.9 }
    hr { border: none; border-top: 1px solid rgba(0,0,0,.12); margin: 16px 0; }
    a { color: #0b5cd6; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="container">
    <h1>WireGuard Client Steuerung</h1>

    <!-- STATUS (NEU) -->
    <h2>Status</h2>
    <div class="grid" id="wg-status">
      <div><strong>Interface:</strong></div><div id="st-iface">-</div>
      <div><strong>IPv4:</strong></div><div id="st-ipv4" class="mono">-</div>
      <div><strong>Verbindung:</strong></div><div id="st-state"><span class="pill">-</span></div>
      <div><strong>Traffic:</strong></div><div>RX <span id="st-rx" class="mono">0</span> | TX <span id="st-tx" class="mono">0</span></div>
    </div>
    <div class="row" style="margin:8px 0 12px">
      <button type="button" id="btn-refresh">Status aktualisieren</button>
    </div>

    <hr>

    <!-- Steuerung (dein Original) -->
    <form method="post" action="/cgi-bin/wireguard_control.sh" class="row">
      <button type="submit" name="action" value="start" class="btn-ok">Verbindung aktivieren</button>
      <button type="submit" name="action" value="stop"  class="btn-bad">Verbindung deaktivieren</button>
    </form>

    <h2>Konfiguration bearbeiten</h2>
    <form method="post" action="/cgi-bin/wireguard_control.sh">
      <textarea name="config" placeholder="[Interface] …"></textarea><br>
      <div class="row"><button type="submit" name="action" value="update">Konfiguration speichern</button></div>
    </form>

    <h2>Autostart-Verwaltung</h2>
    <form method="post" action="/cgi-bin/wireguard_control.sh" class="row">
      <button type="submit" name="action" value="autostart-on">Autostart aktivieren</button>
      <button type="submit" name="action" value="autostart-off">Autostart deaktivieren</button>
      <button type="submit" name="action" value="autostart-status">Autostart-Status anzeigen</button>
    </form>

    <hr>
    <div class="footer">
      <a href="index.html" class="back-to-home">Zurück zur Startseite</a>
      <div>Powered by Ebner Stephan · <a href="https://github.com/stephanflug/digitales-Flugbuch/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">MIT-Lizenz</a></div>
    </div>
  </div>

  <script>
  // Konfiguration in Textarea laden (dein Original)
  (function(){
    const ta = document.querySelector('textarea[name="config"]');
    fetch('/cgi-bin/get_wg_conf.sh?ts=' + Date.now())
      .then(r => { if (!r.ok) throw new Error(r.status + ' ' + r.statusText); return r.text(); })
      .then(cfg => ta.value = cfg)
      .catch(err => { console.error('Konfig nicht geladen:', err); ta.value = '# Fehler: ' + err; });
  })();

  function humanBytes(n){ n=Number(n||0); const u=['B','KiB','MiB','GiB','TiB']; let i=0; while(n>=1024&&i<u.length-1){n/=1024;i++;} return n.toFixed(1)+' '+u[i]; }
  function setStatePill(text){
    const wrap = document.getElementById('st-state');
    wrap.innerHTML = '';
    const span = document.createElement('span');
    span.className = 'pill ' + (text === 'verbunden' ? 'ok' : 'bad');
    span.textContent = text;
    wrap.appendChild(span);
  }
  async function loadStatus(){
    try{
      const r = await fetch('/cgi-bin/wireguard_status.sh?ts=' + Date.now());
      if(!r.ok) throw new Error(r.status + ' ' + r.statusText);
      const d = await r.json();
      document.getElementById('st-iface').textContent = d.iface || '-';
      document.getElementById('st-ipv4').textContent  = d.ipv4  || '-';
      setStatePill(d.status || '-');
      document.getElementById('st-rx').textContent = humanBytes(d.rx_bytes||0);
      document.getElementById('st-tx').textContent = humanBytes(d.tx_bytes||0);
    }catch(e){
      console.error('Status-Fehler:', e);
      setStatePill('getrennt');
    }
  }
  document.getElementById('btn-refresh').addEventListener('click', loadStatus);
  loadStatus();
  setInterval(loadStatus, 5000);
  </script>
</body>
</html>
EOF

# 6. Sudoers-Regeln (ERWEITERT um /usr/bin/wg, Rest unverändert)
SUDO_LINE1="www-data ALL=(ALL) NOPASSWD: /usr/bin/wg-quick"
SUDO_LINE2="www-data ALL=(ALL) NOPASSWD: /bin/systemctl"
SUDO_LINE3="www-data ALL=(ALL) NOPASSWD: /usr/bin/wg"

if ! sudo grep -qF "$SUDO_LINE1" /etc/sudoers; then
  echo "$SUDO_LINE1" | sudo tee -a /etc/sudoers > /dev/null
fi
if ! sudo grep -qF "$SUDO_LINE2" /etc/sudoers; then
  echo "$SUDO_LINE2" | sudo tee -a /etc/sudoers > /dev/null
fi
if ! sudo grep -qF "$SUDO_LINE3" /etc/sudoers; then
  echo "$SUDO_LINE3" | sudo tee -a /etc/sudoers > /dev/null
fi

# 7. Button auf index.html hinzufügen (UNVERÄNDERT)
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''wireguard.html'\''">WireGuard</button>'
if [ -f "$INDEX_HTML" ] && ! grep -q "wireguard.html" "$INDEX_HTML"; then
  echo "data: Füge WireGuard-Link zur index.html hinzu..."
  sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML"
fi

# 8. systemd-Service für Autostart (UNVERÄNDERT)
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
