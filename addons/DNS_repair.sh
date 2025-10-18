#!/bin/bash
# Datei: /usr/local/bin/fix_dns.sh
# Zweck: DNS reparieren (resolvconf entfernen, resolv.conf setzen, optional dhcpcd persistieren)
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

say "Fertig."
exit 0
