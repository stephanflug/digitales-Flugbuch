#!/bin/bash
# Datei: /usr/local/bin/fix_dns.sh
# Zweck: DNS reparieren (resolvconf entfernen, resolv.conf setzen, optional dhcpcd persistieren)
#        + Optionaler Fallback-Schutz via NetworkManager-Dispatcher (99-fix-dns)
# Ausgabe: Server-Sent Events (SSE) + Selbstlöschung am Ende

# --- SSE Header ---
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

# --- Debug/Fehler ---
exec 2>&1
set -euo pipefail
set -x

say() { echo "data: $*"; echo ""; }

SCRIPT_PATH="$(realpath "$0")"

# --- bei Ende: ggf. selbst entfernen ---
trap '
  rc=$?
  if [ $rc -eq 0 ]; then
    say "DNS-Fix abgeschlossen – Script wird nun entfernt..."
    rm -f "'"$SCRIPT_PATH"'"
  else
    say "FEHLER (Exit-Code $rc) – Script bleibt zur Analyse erhalten: '"$SCRIPT_PATH"'"
  fi
  exit $rc
' EXIT

say "Starte DNS-Reparatur…"

# 1) resolvconf sauber entfernen (falls installiert)
if dpkg -s resolvconf >/dev/null 2>&1; then
  say "Entferne resolvconf…"
  sudo apt-get purge -y resolvconf || true
else
  say "resolvconf ist nicht installiert – überspringe."
fi

# 2) /etc/resolv.conf neu schreiben (vorherigen Inhalt/Symlink entfernen)
say "Setze /etc/resolv.conf auf funktionierende Nameserver…"
sudo rm -f /etc/resolv.conf
echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null

# 3) Optional: persistente DNS für dhcpcd (nur wenn Dienst vorhanden)
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^dhcpcd\.service'; then
  if ! grep -q '^\s*interface\s\+wlan0' /etc/dhcpcd.conf 2>/dev/null || \
     ! grep -q '^\s*static\s\+domain_name_servers=' /etc/dhcpcd.conf 2>/dev/null; then
    say "Hinterlege DNS persistent in /etc/dhcpcd.conf (wlan0)…"
    sudo bash -c 'cat >>/etc/dhcpcd.conf <<EOF

# DNS fest für WLAN (vom fix_dns.sh gesetzt)
interface wlan0
static domain_name_servers=1.1.1.1 8.8.8.8
EOF'
    sudo systemctl restart dhcpcd || true
  else
    say "Persistente DNS in /etc/dhcpcd.conf bereits vorhanden – überspringe."
  fi
else
  say "dhcpcd-Dienst nicht gefunden – persistente Ablage wird übersprungen."
fi

# 4) Status zeigen
say "Aktueller Inhalt von /etc/resolv.conf:"
while IFS= read -r line; do
  echo "data: $line"
done < <(cat /etc/resolv.conf)
echo ""

# 5) Funktionstest: Namensauflösung + HTTPS
say "Teste Namensauflösung (api.github.com)…"
if getent hosts api.github.com >/dev/null 2>&1; then
  say "OK: DNS-Auflösung funktioniert."
else
  say "WARNUNG: DNS-Auflösung fehlgeschlagen. Prüfe Router/AP oder Firewalls."
fi

say "Teste HTTPS-Verbindung zu api.github.com…"
if curl -4 -sS https://api.github.com/ >/dev/null 2>&1; then
  say "OK: HTTPS erreichbar."
else
  say "WARNUNG: HTTPS-Test fehlgeschlagen. Prüfe Internetzugang/Firewall/Proxy."
fi

# 6) OPTIONALER FALLBACK-SCHUTZ: NM-Dispatcher-Hook anlegen
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^NetworkManager\.service'; then
  say "Installiere NetworkManager-Dispatcher-Fallback (99-fix-dns)…"
  sudo mkdir -p /etc/NetworkManager/dispatcher.d
  sudo tee /etc/NetworkManager/dispatcher.d/99-fix-dns >/dev/null <<'EOF'
#!/bin/bash
# Fallback: Wenn eine Verbindung hochkommt, aber /etc/resolv.conf keine nameserver enthält,
# setze sofort funktionierende DNS (Cloudflare + Google).
IFACE="$1"
STATE="$2"
if [ "$STATE" = "up" ]; then
  if ! grep -Eq '^\s*nameserver\s+\S+' /etc/resolv.conf 2>/dev/null; then
    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
  fi
fi
EOF
  sudo chmod +x /etc/NetworkManager/dispatcher.d/99-fix-dns
  # Dispatcher aktiv (Teil von NetworkManager) – NM kurz neu starten, damit Hook greift
  sudo systemctl restart NetworkManager || true
  say "Dispatcher-Fallback aktiv. DNS wird nach Verbindungsaufbau automatisch abgesichert."
else
  say "NetworkManager nicht gefunden – Dispatcher-Fallback wird übersprungen."
fi

say "Fertig."
exit 0
