#!/bin/bash
set -e

# 1. CGI-Skript installieren
CGI="/usr/lib/cgi-bin/fullpageos_build.sh"
cat > "$CGI" <<'EOF'
#!/bin/bash
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

set -e

LOGFILE="/var/log/fullpageos_build.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

URL_DEFAULT="https://downloads.raspberrypi.org/raspios_lite_armhf_latest"

# POST-Daten einlesen (bis Leerzeile)
POSTDATA=""
while read LINE; do
  [ "$LINE" == "" ] && break
done
read POSTDATA

parse_post() {
  echo "$POSTDATA" | sed -n 's/^url=\(.*\)$/\1/p' | sed 's/%3A/:/g; s/%2F/\//g'
}
IMAGE_URL=$(parse_post)
[ -z "$IMAGE_URL" ] && IMAGE_URL="$URL_DEFAULT"

echo "data: Starte Build von FullPageOS mit URL: $IMAGE_URL"
echo ""

sudo apt update
sudo apt install -y coreutils p7zip-full qemu-user-static git wget

WORKDIR="/opt/fullpageos_build"
sudo mkdir -p "$WORKDIR"
cd "$WORKDIR"

[ ! -d "CustomPiOS" ] && git clone https://github.com/guysoft/CustomPiOS.git
[ ! -d "FullPageOS" ] && git clone https://github.com/guysoft/FullPageOS.git

cd FullPageOS/src/image

echo "data: Lade OS-Image: $IMAGE_URL"
echo ""
wget -c --trust-server-names "$IMAGE_URL"

cd ..

../../CustomPiOS/src/update-custompios-paths

sudo modprobe loop

echo "data: Build startet – das dauert bis zu 1 Stunde auf dem Pi!"
echo ""
sudo bash -x ./build_dist

echo ""
echo "data: Build abgeschlossen! Das fertige Image findest du unter:"
echo "data: $WORKDIR/FullPageOS/src/workspace/"
echo "data: Fertig."
echo ""
EOF

chmod +x "$CGI"

# 2. HTML-Interface anlegen
HTML="/var/www/html/fullpageos_build.html"
cat > "$HTML" <<'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>FullPageOS Build-Addon</title>
  <style>
    body { font-family: Arial,sans-serif; background:#f4f7fc; margin:0; padding:0; }
    .container {
      background:#fff; margin:50px auto; max-width:600px; padding:30px; border-radius:12px;
      box-shadow:0 6px 16px rgba(0,0,0,0.13); text-align:center;
    }
    h1 { font-size:28px; margin-bottom:10px;}
    label, input, button { font-size:16px; margin:10px 0; }
    input[type=text] { width:80%; padding:7px; border-radius:6px; border:1px solid #ccc; }
    button { background:#4CAF50; color:#fff; border:none; border-radius:8px; padding:10px 24px; cursor:pointer;}
    button:hover { background:#388e3c; }
    pre { text-align:left; background:#e8f0fe; padding:10px; border-radius:8px; margin-top:15px; height:250px; overflow:auto; }
  </style>
</head>
<body>
<div class="container">
  <h1>FullPageOS Image bauen</h1>
  <form id="buildForm">
    <label for="url">Download-URL für Raspberry Pi OS Lite:</label><br>
    <input type="text" id="url" name="url"
      value="https://downloads.raspberrypi.org/raspios_lite_armhf_latest" /><br>
    <button type="submit">Build starten</button>
  </form>
  <pre id="log">Status: Noch kein Build gestartet.</pre>
  <a href="index.html">Zurück zur Startseite</a>
</div>

<script>
document.getElementById('buildForm').onsubmit = function(e) {
  e.preventDefault();
  let url = document.getElementById('url').value;
  const log = document.getElementById('log');
  log.textContent = 'Build wird gestartet...\n';

  const xhr = new XMLHttpRequest();
  xhr.open("POST", "/cgi-bin/fullpageos_build.sh", true);
  xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
  xhr.onreadystatechange = function() {
    if (xhr.readyState === 3 || xhr.readyState === 4) {
      log.textContent += xhr.responseText;
      log.scrollTop = log.scrollHeight;
    }
  };
  xhr.send("url=" + encodeURIComponent(url));
};
</script>
</body>
</html>
EOF

# 3. Sudoers-Konfiguration (Sicherheitshinweis: für echtes Web sollte man feiner einstellen!)
SUDOERS_LINE1="www-data ALL=(ALL) NOPASSWD: /sbin/modprobe"
SUDOERS_LINE2="www-data ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get, /usr/bin/git, /usr/bin/wget, /usr/bin/bash, /usr/bin/mkdir"
SUDOERS_LINE3="www-data ALL=(ALL) NOPASSWD: /opt/fullpageos_build/FullPageOS/src/image/build_dist"

for LINE in "$SUDOERS_LINE1" "$SUDOERS_LINE2" "$SUDOERS_LINE3"; do
  if ! grep -qF "$LINE" /etc/sudoers; then
    echo "$LINE" | sudo tee -a /etc/sudoers > /dev/null
  fi
done

# 4. Button in index.html einfügen
INDEX_HTML="/var/www/html/index.html"
LINK='<button type="button" onclick="window.location.href='\''fullpageos_build.html'\''">FullPageOS bauen</button>'
if ! grep -q "fullpageos_build.html" "$INDEX_HTML"; then
  echo "Füge FullPageOS-Button zur index.html hinzu..."
  sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML"
fi

echo ""
echo "Fertig! FullPageOS-Build-Addon wurde installiert."
echo "Öffne im Browser: http://<IP>/fullpageos_build.html"
echo ""
