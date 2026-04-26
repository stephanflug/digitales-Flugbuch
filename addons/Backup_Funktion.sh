#!/bin/bash

LOGFILE="/var/log/external_backup_setup.log"
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
echo ""

set -x

echo "data: Starte Installation der Externen Backup Funktion..."
echo ""

CONFIG_DIR="/opt/digitalflugbuch/data/DatenBuch"
CONFIG_FILE="$CONFIG_DIR/externe_backup.conf"
STATUS_FILE="$CONFIG_DIR/externe_backup_status.conf"

BACKUP_RUNNER="/usr/local/bin/external_backup_run.sh"
APPLY_TIMER="/usr/local/bin/external_backup_apply_timer.sh"

GET_CONF="/usr/lib/cgi-bin/get_external_backup_conf.sh"
STATUS_CGI="/usr/lib/cgi-bin/external_backup_status.sh"
CONTROL_CGI="/usr/lib/cgi-bin/external_backup_control.sh"

HTML_PATH="/var/www/html/externe_backup.html"
INDEX_HTML="/var/www/html/index.html"

SERVICE_FILE="/etc/systemd/system/external-backup.service"
SUDOERS_FILE="/etc/sudoers.d/external-backup"

# 1. Pakete installieren
echo "data: Installiere benötigte Pakete (lftp)..."
echo ""
sudo apt update
sudo apt install -y lftp

# 2. Verzeichnisse anlegen
echo "data: Erstelle Konfigurationsverzeichnis..."
echo ""
sudo mkdir -p "$CONFIG_DIR"

# 3. Standard-Konfiguration anlegen
if [ ! -f "$CONFIG_FILE" ]; then
  echo "data: Erstelle Standard-Konfiguration..."
  echo ""
  sudo tee "$CONFIG_FILE" > /dev/null <<'EOF'
PROTOCOL=sftp
HOST=
PORT=22
USERNAME=
PASSWORD=
REMOTE_DIR=/backup
REMOTE_FILE_PREFIX=DatenBuchBackup
MAX_BACKUPS=10
ON_CALENDAR=daily
FTP_PASSIVE=yes
SFTP_STRICT_HOSTKEY=no
EOF
fi

sudo chown root:www-data "$CONFIG_FILE"
sudo chmod 660 "$CONFIG_FILE"

# 4. Standard-Statusdatei anlegen
if [ ! -f "$STATUS_FILE" ]; then
  sudo tee "$STATUS_FILE" > /dev/null <<'EOF'
LAST_RUN=-
LAST_RESULT=-
LAST_MESSAGE=Noch kein Backup ausgeführt.
LAST_FILE=-
LAST_SIZE_BYTES=0
EOF
fi

sudo chown root:www-data "$STATUS_FILE"
sudo chmod 664 "$STATUS_FILE"

# 5. Backup-Runner anlegen
echo "data: Erstelle Backup-Runner..."
echo ""
sudo tee "$BACKUP_RUNNER" > /dev/null <<'EOF'
#!/bin/bash
set -u

CONFIG_FILE="/opt/digitalflugbuch/data/DatenBuch/externe_backup.conf"
STATUS_FILE="/opt/digitalflugbuch/data/DatenBuch/externe_backup_status.conf"
TMP_DIR="/tmp/externe_backup"
SOURCE_DIR="/opt/digitalflugbuch/data/DatenBuch"

mkdir -p "$TMP_DIR"

cfg_get() {
  local key="$1"
  local file="$2"
  grep -m1 "^${key}=" "$file" 2>/dev/null | cut -d= -f2-
}

write_status() {
  local result="$1"
  local message="$2"
  local file="$3"
  local size="$4"

  cat > "$STATUS_FILE" <<STATUS
LAST_RUN=$(date '+%Y-%m-%d %H:%M:%S')
LAST_RESULT=$result
LAST_MESSAGE=$message
LAST_FILE=$file
LAST_SIZE_BYTES=$size
STATUS

  chown root:www-data "$STATUS_FILE" 2>/dev/null || true
  chmod 664 "$STATUS_FILE" 2>/dev/null || true
}

fail_exit() {
  local msg="$1"
  local file="${2:--}"
  local size="${3:-0}"
  echo "Fehler: $msg"
  write_status "FEHLER" "$msg" "$file" "$size"
  exit 1
}

escape_lftp() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

[ -f "$CONFIG_FILE" ] || fail_exit "Konfigurationsdatei fehlt: $CONFIG_FILE"
[ -d "$SOURCE_DIR" ] || fail_exit "Quellverzeichnis existiert nicht: $SOURCE_DIR"

PROTOCOL="$(cfg_get PROTOCOL "$CONFIG_FILE")"
HOST="$(cfg_get HOST "$CONFIG_FILE")"
PORT="$(cfg_get PORT "$CONFIG_FILE")"
USERNAME="$(cfg_get USERNAME "$CONFIG_FILE")"
PASSWORD="$(cfg_get PASSWORD "$CONFIG_FILE")"
REMOTE_DIR="$(cfg_get REMOTE_DIR "$CONFIG_FILE")"
REMOTE_FILE_PREFIX="$(cfg_get REMOTE_FILE_PREFIX "$CONFIG_FILE")"
MAX_BACKUPS="$(cfg_get MAX_BACKUPS "$CONFIG_FILE")"
FTP_PASSIVE="$(cfg_get FTP_PASSIVE "$CONFIG_FILE")"
SFTP_STRICT_HOSTKEY="$(cfg_get SFTP_STRICT_HOSTKEY "$CONFIG_FILE")"

[ -z "$PROTOCOL" ] && fail_exit "PROTOCOL ist leer."
[ -z "$HOST" ] && fail_exit "HOST ist leer."
[ -z "$USERNAME" ] && fail_exit "USERNAME ist leer."

[ -z "$REMOTE_FILE_PREFIX" ] && REMOTE_FILE_PREFIX="DatenBuchBackup"
[ -z "$MAX_BACKUPS" ] && MAX_BACKUPS="10"
[ -z "$REMOTE_DIR" ] && REMOTE_DIR="/"

if ! [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]]; then
  fail_exit "MAX_BACKUPS muss eine Zahl größer oder gleich 0 sein."
fi

case "$PROTOCOL" in
  ftp)
    [ -z "$PORT" ] && PORT="21"
    ;;
  sftp)
    [ -z "$PORT" ] && PORT="22"
    ;;
  *)
    fail_exit "Ungültiges Protokoll: $PROTOCOL"
    ;;
esac

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REMOTE_FILE="${REMOTE_FILE_PREFIX}_${TIMESTAMP}.tar"
REMOTE_TMP_FILE="${REMOTE_FILE}.uploading"
ARCHIVE_PATH="$TMP_DIR/$REMOTE_FILE"

echo "Erstelle Archiv: $ARCHIVE_PATH"
tar -cf "$ARCHIVE_PATH" -C "/opt/digitalflugbuch/data" "DatenBuch" || fail_exit "Archiv konnte nicht erstellt werden."

SIZE_BYTES="$(stat -c %s "$ARCHIVE_PATH" 2>/dev/null || echo 0)"

if [ "$REMOTE_DIR" = "/" ] || [ "$REMOTE_DIR" = "." ] || [ -z "$REMOTE_DIR" ]; then
  REMOTE_DIR="/"
  REMOTE_PREP='cd "/"'
  REMOTE_TARGET="/$REMOTE_FILE"
else
  REMOTE_DIR_ESC="$(escape_lftp "$REMOTE_DIR")"
  REMOTE_PREP=$(cat <<PREP
set cmd:fail-exit no
mkdir -p "$REMOTE_DIR_ESC"
set cmd:fail-exit yes
cd "$REMOTE_DIR_ESC"
PREP
)
  REMOTE_TARGET="$REMOTE_DIR/$REMOTE_FILE"
fi

if [ "$FTP_PASSIVE" = "no" ]; then
  LFTP_PASSIVE="false"
else
  LFTP_PASSIVE="true"
fi

if [ "$SFTP_STRICT_HOSTKEY" = "yes" ]; then
  SFTP_AUTO_CONFIRM="false"
else
  SFTP_AUTO_CONFIRM="true"
fi

LFTP_USER_ESC="$(escape_lftp "$USERNAME")"
LFTP_PASS_ESC="$(escape_lftp "$PASSWORD")"
LFTP_HOST_ESC="$(escape_lftp "$HOST")"
LFTP_ARCHIVE_ESC="$(escape_lftp "$ARCHIVE_PATH")"
LFTP_REMOTE_TMP_ESC="$(escape_lftp "$REMOTE_TMP_FILE")"
LFTP_REMOTE_FILE_ESC="$(escape_lftp "$REMOTE_FILE")"
LFTP_PREFIX_ESC="$(escape_lftp "$REMOTE_FILE_PREFIX")"

UPLOAD_SCRIPT="$(mktemp)"

cat > "$UPLOAD_SCRIPT" <<LFTP
set cmd:fail-exit yes
set net:timeout 20
set net:max-retries 2
set xfer:clobber yes
set ftp:passive-mode $LFTP_PASSIVE
set ssl:verify-certificate no
set sftp:auto-confirm $SFTP_AUTO_CONFIRM
open -u "$LFTP_USER_ESC","$LFTP_PASS_ESC" "$PROTOCOL://$LFTP_HOST_ESC:$PORT"
$REMOTE_PREP
put "$LFTP_ARCHIVE_ESC" -o "$LFTP_REMOTE_TMP_ESC"
set cmd:fail-exit no
rm "$LFTP_REMOTE_FILE_ESC"
set cmd:fail-exit yes
mv "$LFTP_REMOTE_TMP_ESC" "$LFTP_REMOTE_FILE_ESC"
bye
LFTP

echo "Lade Backup hoch nach $PROTOCOL://$HOST:$PORT$REMOTE_TARGET"
if ! lftp -f "$UPLOAD_SCRIPT"; then
  rm -f "$UPLOAD_SCRIPT" "$ARCHIVE_PATH"
  fail_exit "Upload fehlgeschlagen." "$REMOTE_TARGET" "$SIZE_BYTES"
fi

rm -f "$UPLOAD_SCRIPT"

PURGED_COUNT=0

if [ "$MAX_BACKUPS" -gt 0 ]; then
  LIST_SCRIPT="$(mktemp)"

  cat > "$LIST_SCRIPT" <<LFTP
set cmd:fail-exit no
set ftp:passive-mode $LFTP_PASSIVE
set ssl:verify-certificate no
set sftp:auto-confirm $SFTP_AUTO_CONFIRM
open -u "$LFTP_USER_ESC","$LFTP_PASS_ESC" "$PROTOCOL://$LFTP_HOST_ESC:$PORT"
$REMOTE_CD
cls -1 "${LFTP_PREFIX_ESC}"_*.tar
bye
LFTP

  mapfile -t REMOTE_FILES < <(
    lftp -f "$LIST_SCRIPT" 2>/dev/null \
      | sed '/^[[:space:]]*$/d' \
      | LC_ALL=C sort
  )

  rm -f "$LIST_SCRIPT"

  FILE_COUNT="${#REMOTE_FILES[@]}"

  if [ "$FILE_COUNT" -gt "$MAX_BACKUPS" ]; then
    TO_DELETE=$((FILE_COUNT - MAX_BACKUPS))
    DELETE_SCRIPT="$(mktemp)"

    {
      echo "set cmd:fail-exit yes"
      echo "set ftp:passive-mode $LFTP_PASSIVE"
      echo "set ssl:verify-certificate no"
      echo "set sftp:auto-confirm $SFTP_AUTO_CONFIRM"
      printf 'open -u "%s","%s" "%s://%s:%s"\n' "$LFTP_USER_ESC" "$LFTP_PASS_ESC" "$PROTOCOL" "$LFTP_HOST_ESC" "$PORT"
      echo "$REMOTE_CD"
      for ((i=0; i<TO_DELETE; i++)); do
        printf 'rm "%s"\n' "$(escape_lftp "${REMOTE_FILES[$i]}")"
      done
      echo "bye"
    } > "$DELETE_SCRIPT"

    if lftp -f "$DELETE_SCRIPT"; then
      PURGED_COUNT="$TO_DELETE"
    fi

    rm -f "$DELETE_SCRIPT"
  fi
fi

rm -f "$ARCHIVE_PATH"

MESSAGE="Backup erfolgreich hochgeladen: $REMOTE_FILE"
if [ "$PURGED_COUNT" -gt 0 ]; then
  MESSAGE="$MESSAGE. $PURGED_COUNT alte Sicherung(en) gelöscht."
fi

write_status "OK" "$MESSAGE" "$REMOTE_TARGET" "$SIZE_BYTES"
echo "$MESSAGE"
exit 0
EOF
sudo chmod 755 "$BACKUP_RUNNER"

# 6. Timer-Steuerung anlegen
echo "data: Erstelle Timer-Steuerung..."
echo ""
sudo tee "$APPLY_TIMER" > /dev/null <<'EOF'
#!/bin/bash
set -e

CONFIG_FILE="/opt/digitalflugbuch/data/DatenBuch/externe_backup.conf"
TIMER_FILE="/etc/systemd/system/external-backup.timer"

cfg_get() {
  local key="$1"
  grep -m1 "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2-
}

ACTION="${1:-write}"
ON_CALENDAR="$(cfg_get ON_CALENDAR)"
[ -z "$ON_CALENDAR" ] && ON_CALENDAR="daily"

cat > "$TIMER_FILE" <<TIMER
[Unit]
Description=Automatisches externes Backup

[Timer]
OnCalendar=$ON_CALENDAR
Persistent=true
RandomizedDelaySec=60
Unit=external-backup.service

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload

case "$ACTION" in
  enable)
    systemctl enable --now external-backup.timer
    ;;
  disable)
    systemctl disable --now external-backup.timer
    ;;
  write)
    ;;
  restart)
    systemctl restart external-backup.timer
    ;;
  *)
    echo "Unbekannte Aktion: $ACTION"
    exit 1
    ;;
esac

echo "Timer-Konfiguration geschrieben. OnCalendar=$ON_CALENDAR"
EOF
sudo chmod 755 "$APPLY_TIMER"

# 7. systemd Service anlegen
echo "data: Erstelle systemd-Service..."
echo ""
sudo tee "$SERVICE_FILE" > /dev/null <<'EOF'
[Unit]
Description=Externes Backup Upload
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/external_backup_run.sh
User=root
Group=root
EOF

sudo systemctl daemon-reload

# 8. CGI: Konfiguration lesen
echo "data: Erstelle CGI für Konfiguration..."
echo ""
sudo tee "$GET_CONF" > /dev/null <<'EOF'
#!/bin/bash

CONFIG_FILE="/opt/digitalflugbuch/data/DatenBuch/externe_backup.conf"

echo "Content-Type: text/plain; charset=utf-8"
echo "Cache-Control: no-cache, no-store, must-revalidate"
echo "Pragma: no-cache"
echo "Expires: 0"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
  cat <<CFG
PROTOCOL=sftp
HOST=
PORT=22
USERNAME=
PASSWORD=
REMOTE_DIR=/backup
REMOTE_FILE_PREFIX=DatenBuchBackup
MAX_BACKUPS=10
ON_CALENDAR=daily
FTP_PASSIVE=yes
SFTP_STRICT_HOSTKEY=no
CFG
  exit 0
fi

while IFS= read -r line; do
  case "$line" in
    PASSWORD=*)
      echo "PASSWORD="
      ;;
    *)
      echo "$line"
      ;;
  esac
done < "$CONFIG_FILE"
EOF
sudo chmod 755 "$GET_CONF"

# 9. CGI: Status
echo "data: Erstelle CGI für Status..."
echo ""
sudo tee "$STATUS_CGI" > /dev/null <<'EOF'
#!/bin/bash

CONFIG_FILE="/opt/digitalflugbuch/data/DatenBuch/externe_backup.conf"
STATUS_FILE="/opt/digitalflugbuch/data/DatenBuch/externe_backup_status.conf"

cfg_get() {
  local key="$1"
  local file="$2"
  grep -m1 "^${key}=" "$file" 2>/dev/null | cut -d= -f2-
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; :a;N;$!ba;s/\n/ /g'
}

PROTOCOL="$(cfg_get PROTOCOL "$CONFIG_FILE")"
HOST="$(cfg_get HOST "$CONFIG_FILE")"
REMOTE_DIR="$(cfg_get REMOTE_DIR "$CONFIG_FILE")"
REMOTE_FILE_PREFIX="$(cfg_get REMOTE_FILE_PREFIX "$CONFIG_FILE")"
MAX_BACKUPS="$(cfg_get MAX_BACKUPS "$CONFIG_FILE")"
ON_CALENDAR="$(cfg_get ON_CALENDAR "$CONFIG_FILE")"

LAST_RUN="$(cfg_get LAST_RUN "$STATUS_FILE")"
LAST_RESULT="$(cfg_get LAST_RESULT "$STATUS_FILE")"
LAST_MESSAGE="$(cfg_get LAST_MESSAGE "$STATUS_FILE")"
LAST_FILE="$(cfg_get LAST_FILE "$STATUS_FILE")"
LAST_SIZE_BYTES="$(cfg_get LAST_SIZE_BYTES "$STATUS_FILE")"

TIMER_ENABLED="$(sudo /bin/systemctl is-enabled external-backup.timer 2>/dev/null || true)"
TIMER_ACTIVE="$(sudo /bin/systemctl is-active external-backup.timer 2>/dev/null || true)"

AUTO_MODE="deaktiviert"
if [ "$TIMER_ENABLED" = "enabled" ]; then
  AUTO_MODE="aktiviert"
fi

echo "Content-Type: application/json; charset=utf-8"
echo "Cache-Control: no-cache, no-store, must-revalidate"
echo "Pragma: no-cache"
echo "Expires: 0"
echo ""

printf '{'
printf '"ok":true,'
printf '"protocol":"%s",' "$(json_escape "${PROTOCOL:-}")"
printf '"host":"%s",' "$(json_escape "${HOST:-}")"
printf '"remote_dir":"%s",' "$(json_escape "${REMOTE_DIR:-}")"
printf '"remote_file_prefix":"%s",' "$(json_escape "${REMOTE_FILE_PREFIX:-}")"
printf '"max_backups":"%s",' "$(json_escape "${MAX_BACKUPS:-0}")"
printf '"on_calendar":"%s",' "$(json_escape "${ON_CALENDAR:-}")"
printf '"last_run":"%s",' "$(json_escape "${LAST_RUN:--}")"
printf '"last_result":"%s",' "$(json_escape "${LAST_RESULT:--}")"
printf '"last_message":"%s",' "$(json_escape "${LAST_MESSAGE:--}")"
printf '"last_file":"%s",' "$(json_escape "${LAST_FILE:--}")"
printf '"last_size_bytes":"%s",' "$(json_escape "${LAST_SIZE_BYTES:-0}")"
printf '"timer_enabled":"%s",' "$(json_escape "${TIMER_ENABLED:-unknown}")"
printf '"timer_active":"%s",' "$(json_escape "${TIMER_ACTIVE:-unknown}")"
printf '"auto_mode":"%s"' "$(json_escape "$AUTO_MODE")"
printf '}\n'
EOF
sudo chmod 755 "$STATUS_CGI"

# 10. CGI: Steuerung
echo "data: Erstelle CGI für Steuerung..."
echo ""
sudo tee "$CONTROL_CGI" > /dev/null <<'EOF'
#!/bin/bash

CONFIG_FILE="/opt/digitalflugbuch/data/DatenBuch/externe_backup.conf"

echo "Content-type: text/html; charset=utf-8"
echo ""

POST_DATA="$(cat)"

urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

get_param() {
  local key="$1"
  local raw
  raw="$(printf '%s' "$POST_DATA" | tr '&' '\n' | sed -n "s/^${key}=//p" | head -n1)"
  urldecode "$raw"
}

cfg_get() {
  local key="$1"
  grep -m1 "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2-
}

clean_value() {
  printf '%s' "$1" | tr -d '\r' | tr '\n' ' '
}

html_response() {
  local title="$1"
  local body="$2"
  cat <<HTML
<html>
  <head>
    <meta charset="UTF-8">
    <title>Externe Backup Funktion</title>
  </head>
  <body style="font-family:Arial,sans-serif;background:#f5f5f5;padding:24px;">
    <div style="max-width:920px;margin:0 auto;background:#fff;padding:24px;border-radius:16px;box-shadow:0 10px 30px rgba(0,0,0,.15);">
      <h2>$title</h2>
      <pre style="background:#f0f0f0;padding:12px;border-radius:10px;white-space:pre-wrap;">$body</pre>
      <a href="/externe_backup.html">Zurück zur Backup-Seite</a>
    </div>
  </body>
</html>
HTML
}

apply_timer_after_save() {
  if sudo /bin/systemctl is-enabled external-backup.timer >/dev/null 2>&1; then
    sudo /usr/local/bin/external_backup_apply_timer.sh restart >/dev/null 2>&1 || true
  else
    sudo /usr/local/bin/external_backup_apply_timer.sh write >/dev/null 2>&1 || true
  fi
}

save_config() {
  local EXISTING_PASSWORD PROTOCOL HOST PORT USERNAME PASSWORD REMOTE_DIR REMOTE_FILE_PREFIX MAX_BACKUPS ON_CALENDAR FTP_PASSIVE SFTP_STRICT_HOSTKEY

  EXISTING_PASSWORD="$(cfg_get PASSWORD)"

  PROTOCOL="$(clean_value "$(get_param protocol)")"
  HOST="$(clean_value "$(get_param host)")"
  PORT="$(clean_value "$(get_param port)")"
  USERNAME="$(clean_value "$(get_param username)")"
  PASSWORD="$(clean_value "$(get_param password)")"
  REMOTE_DIR="$(clean_value "$(get_param remote_dir)")"
  REMOTE_FILE_PREFIX="$(clean_value "$(get_param remote_file_prefix)")"
  MAX_BACKUPS="$(clean_value "$(get_param max_backups)")"
  ON_CALENDAR="$(clean_value "$(get_param on_calendar)")"
  FTP_PASSIVE="$(clean_value "$(get_param ftp_passive)")"
  SFTP_STRICT_HOSTKEY="$(clean_value "$(get_param sftp_strict_hostkey)")"

  [ -z "$PROTOCOL" ] && PROTOCOL="sftp"
  [ -z "$REMOTE_DIR" ] && REMOTE_DIR="/backup"
  [ -z "$REMOTE_FILE_PREFIX" ] && REMOTE_FILE_PREFIX="DatenBuchBackup"
  [ -z "$MAX_BACKUPS" ] && MAX_BACKUPS="10"
  [ -z "$ON_CALENDAR" ] && ON_CALENDAR="daily"
  [ -z "$FTP_PASSIVE" ] && FTP_PASSIVE="yes"
  [ -z "$SFTP_STRICT_HOSTKEY" ] && SFTP_STRICT_HOSTKEY="no"

  if [ -z "$PORT" ]; then
    if [ "$PROTOCOL" = "ftp" ]; then
      PORT="21"
    else
      PORT="22"
    fi
  fi

  if ! [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]]; then
    MAX_BACKUPS="10"
  fi

  if [ -z "$PASSWORD" ]; then
    PASSWORD="$EXISTING_PASSWORD"
  fi

  mkdir -p "$(dirname "$CONFIG_FILE")"

  cat > "$CONFIG_FILE" <<CFG
PROTOCOL=$PROTOCOL
HOST=$HOST
PORT=$PORT
USERNAME=$USERNAME
PASSWORD=$PASSWORD
REMOTE_DIR=$REMOTE_DIR
REMOTE_FILE_PREFIX=$REMOTE_FILE_PREFIX
MAX_BACKUPS=$MAX_BACKUPS
ON_CALENDAR=$ON_CALENDAR
FTP_PASSIVE=$FTP_PASSIVE
SFTP_STRICT_HOSTKEY=$SFTP_STRICT_HOSTKEY
CFG

  chown root:www-data "$CONFIG_FILE"
  chmod 660 "$CONFIG_FILE"
}

masked_config() {
  sed 's/^PASSWORD=.*/PASSWORD=********/' "$CONFIG_FILE" 2>/dev/null
}

ACTION="$(clean_value "$(get_param action)")"

case "$ACTION" in
  save)
    save_config
    apply_timer_after_save
    html_response "Konfiguration gespeichert." "$(masked_config)"
    ;;

  backup-now)
    save_config
    apply_timer_after_save
    OUTPUT="$(sudo /usr/local/bin/external_backup_run.sh 2>&1)"
    RET=$?
    if [ $RET -eq 0 ]; then
      html_response "Backup erfolgreich ausgeführt." "$OUTPUT"
    else
      html_response "Fehler beim Backup (Code $RET)." "$OUTPUT"
    fi
    ;;

  auto-enable)
    save_config
    OUTPUT="$(sudo /usr/local/bin/external_backup_apply_timer.sh enable 2>&1)"
    RET=$?
    if [ $RET -eq 0 ]; then
      html_response "Automatik aktiviert." "$OUTPUT"
    else
      html_response "Fehler beim Aktivieren der Automatik (Code $RET)." "$OUTPUT"
    fi
    ;;

  auto-disable)
    save_config
    OUTPUT="$(sudo /usr/local/bin/external_backup_apply_timer.sh disable 2>&1)"
    RET=$?
    if [ $RET -eq 0 ]; then
      html_response "Automatik deaktiviert." "$OUTPUT"
    else
      html_response "Fehler beim Deaktivieren der Automatik (Code $RET)." "$OUTPUT"
    fi
    ;;

  auto-status)
    ENABLED="$(sudo /bin/systemctl is-enabled external-backup.timer 2>&1 || true)"
    ACTIVE="$(sudo /bin/systemctl is-active external-backup.timer 2>&1 || true)"
    html_response "Automatik-Status" "is-enabled: $ENABLED
is-active:  $ACTIVE"
    ;;

  *)
    html_response "Unbekannte Aktion." "Aktion: $ACTION"
    ;;
esac
EOF
sudo chmod 755 "$CONTROL_CGI"

# 11. HTML-Oberfläche
echo "data: Erstelle HTML-Oberfläche..."
echo ""
sudo tee "$HTML_PATH" > /dev/null <<'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Externe Backup Funktion</title>
  <style>
    :root{
      --glass-bg: rgba(255,255,255,0.92);
      --shadow: 0 10px 30px rgba(0,0,0,0.25);
      --brand: #2f7dff;
      --ok: #1aa06d;
      --bad: #cc3333;
      --muted: #666;
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
      width: min(980px, 100%);
    }
    h1 { font-size: 28px; margin: 0 0 12px; }
    h2 { margin: 18px 0 8px; font-size: 20px; }
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
    .grid {
      display:grid;
      grid-template-columns: 220px 1fr;
      gap:10px 16px;
      align-items:center;
    }
    input, select {
      width: 100%;
      padding: 10px;
      border-radius: 10px;
      border: 1px solid #d8d8d8;
      background: #fff;
      box-sizing: border-box;
      font-size: 15px;
    }
    .pill {
      display:inline-block;
      padding:3px 8px;
      border-radius:999px;
      font-weight:600;
      font-size:13px;
    }
    .pill.ok { background:#e9f7f1; color:#0c7a56; border:1px solid #bfe6d7; }
    .pill.bad{ background:#fdeeee; color:#a52020; border:1px solid #f3c3c3; }
    .mono { font-family: monospace; }
    .muted { color: var(--muted); font-size: 13px; }
    .footer { margin-top: 18px; font-size: 13px; color: #333; opacity:.9 }
    hr { border: none; border-top: 1px solid rgba(0,0,0,.12); margin: 16px 0; }
    a { color: #0b5cd6; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Externe Backup Funktion</h1>

    <h2>Status</h2>
    <div class="grid" id="backup-status">
      <div><strong>Protokoll:</strong></div><div id="st-protocol">-</div>
      <div><strong>Server:</strong></div><div id="st-host" class="mono">-</div>
      <div><strong>Zielverzeichnis:</strong></div><div id="st-target-dir" class="mono">-</div>
      <div><strong>Datei-Präfix:</strong></div><div id="st-prefix" class="mono">-</div>
      <div><strong>Max. Backups:</strong></div><div id="st-max-backups" class="mono">-</div>
      <div><strong>Automatik:</strong></div><div id="st-auto"><span class="pill">-</span></div>
      <div><strong>Zeitplan:</strong></div><div id="st-calendar" class="mono">-</div>
      <div><strong>Letzter Lauf:</strong></div><div id="st-run">-</div>
      <div><strong>Ergebnis:</strong></div><div id="st-result"><span class="pill">-</span></div>
      <div><strong>Meldung:</strong></div><div id="st-message">-</div>
      <div><strong>Letzte Datei:</strong></div><div id="st-file" class="mono">-</div>
      <div><strong>Größe:</strong></div><div id="st-size" class="mono">0 B</div>
    </div>

    <div class="row" style="margin:8px 0 12px">
      <button type="button" id="btn-refresh">Status aktualisieren</button>
    </div>

    <hr>

    <h2>Backup-Konfiguration</h2>
    <form method="post" action="/cgi-bin/external_backup_control.sh">
      <div class="grid">
        <div><label for="protocol"><strong>Protokoll</strong></label></div>
        <div>
          <select name="protocol" id="protocol">
            <option value="sftp">SFTP</option>
            <option value="ftp">FTP</option>
          </select>
        </div>

        <div><label for="host"><strong>Server / Host</strong></label></div>
        <div><input type="text" name="host" id="host" placeholder="z. B. backup.meinserver.de" /></div>

        <div><label for="port"><strong>Port</strong></label></div>
        <div><input type="text" name="port" id="port" placeholder="22 oder 21" /></div>

        <div><label for="username"><strong>Benutzername</strong></label></div>
        <div><input type="text" name="username" id="username" /></div>

        <div><label for="password"><strong>Passwort</strong></label></div>
        <div>
          <input type="password" name="password" id="password" placeholder="leer lassen = gespeichertes Passwort beibehalten" />
          <div class="muted">Das gespeicherte Passwort wird aus Sicherheitsgründen nicht angezeigt.</div>
        </div>

        <div><label for="remote_dir"><strong>Zielverzeichnis am Server</strong></label></div>
        <div><input type="text" name="remote_dir" id="remote_dir" placeholder="/backup" /></div>

        <div><label for="remote_file_prefix"><strong>Datei-Präfix</strong></label></div>
        <div>
          <input type="text" name="remote_file_prefix" id="remote_file_prefix" placeholder="DatenBuchBackup" />
          <div class="muted">Der Dateiname wird automatisch mit Datum und Uhrzeit ergänzt, z. B. DatenBuchBackup_20260426_031500.tar</div>
        </div>

        <div><label for="max_backups"><strong>Max. Anzahl Backups</strong></label></div>
        <div>
          <input type="number" name="max_backups" id="max_backups" min="0" placeholder="10" />
          <div class="muted">Wenn die Anzahl überschritten wird, werden die ältesten Backups automatisch gelöscht. 0 = keine automatische Löschung.</div>
        </div>

        <div><label for="on_calendar"><strong>Automatik-Zeitplan</strong></label></div>
        <div>
          <input type="text" name="on_calendar" id="on_calendar" placeholder="z. B. daily oder *-*-* 03:00:00" />
          <div class="muted">systemd OnCalendar, z. B. daily, hourly oder *-*-* 03:00:00</div>
        </div>

        <div><label for="ftp_passive"><strong>FTP Passivmodus</strong></label></div>
        <div>
          <select name="ftp_passive" id="ftp_passive">
            <option value="yes">Ja</option>
            <option value="no">Nein</option>
          </select>
        </div>

        <div><label for="sftp_strict_hostkey"><strong>SFTP Hostkey-Prüfung strikt</strong></label></div>
        <div>
          <select name="sftp_strict_hostkey" id="sftp_strict_hostkey">
            <option value="no">Nein</option>
            <option value="yes">Ja</option>
          </select>
        </div>
      </div>

      <div class="row" style="margin-top:16px;">
        <button type="submit" name="action" value="save">Konfiguration speichern</button>
        <button type="submit" name="action" value="backup-now" class="btn-ok">Backup jetzt starten</button>
        <button type="submit" name="action" value="auto-enable">Automatik aktivieren</button>
        <button type="submit" name="action" value="auto-disable" class="btn-bad">Automatik deaktivieren</button>
        <button type="submit" name="action" value="auto-status">Automatik-Status anzeigen</button>
      </div>
    </form>

    <hr>
    <div class="footer">
      <a href="index.html" class="back-to-home">Zurück zur Startseite</a>
      <div>Powered by Ebner Stephan · <a href="https://github.com/stephanflug/digitales-Flugbuch/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">MIT-Lizenz</a></div>
    </div>
  </div>

  <script>
    const fieldMap = {
      PROTOCOL: 'protocol',
      HOST: 'host',
      PORT: 'port',
      USERNAME: 'username',
      PASSWORD: 'password',
      REMOTE_DIR: 'remote_dir',
      REMOTE_FILE_PREFIX: 'remote_file_prefix',
      MAX_BACKUPS: 'max_backups',
      ON_CALENDAR: 'on_calendar',
      FTP_PASSIVE: 'ftp_passive',
      SFTP_STRICT_HOSTKEY: 'sftp_strict_hostkey'
    };

    function humanBytes(n){
      n = Number(n || 0);
      const u = ['B','KiB','MiB','GiB','TiB'];
      let i = 0;
      while(n >= 1024 && i < u.length - 1){
        n /= 1024;
        i++;
      }
      return n.toFixed(1) + ' ' + u[i];
    }

    function setPill(targetId, text, okValues){
      const wrap = document.getElementById(targetId);
      wrap.innerHTML = '';
      const span = document.createElement('span');
      const ok = okValues.includes(String(text).toLowerCase());
      span.className = 'pill ' + (ok ? 'ok' : 'bad');
      span.textContent = text || '-';
      wrap.appendChild(span);
    }

    async function loadConfig() {
      try {
        const r = await fetch('/cgi-bin/get_external_backup_conf.sh?ts=' + Date.now());
        if (!r.ok) throw new Error(r.status + ' ' + r.statusText);
        const txt = await r.text();

        txt.split(/\r?\n/).forEach(line => {
          if (!line || line.startsWith('#') || !line.includes('=')) return;
          const idx = line.indexOf('=');
          const key = line.slice(0, idx).trim();
          const value = line.slice(idx + 1);
          const fieldName = fieldMap[key];
          if (!fieldName) return;
          const el = document.querySelector('[name="' + fieldName + '"]');
          if (el) el.value = value;
        });
      } catch (err) {
        console.error('Konfiguration konnte nicht geladen werden:', err);
      }
    }

    async function loadStatus() {
      try {
        const r = await fetch('/cgi-bin/external_backup_status.sh?ts=' + Date.now());
        if (!r.ok) throw new Error(r.status + ' ' + r.statusText);
        const d = await r.json();

        document.getElementById('st-protocol').textContent = d.protocol || '-';
        document.getElementById('st-host').textContent = d.host || '-';
        document.getElementById('st-target-dir').textContent = d.remote_dir || '-';
        document.getElementById('st-prefix').textContent = d.remote_file_prefix || '-';
        document.getElementById('st-max-backups').textContent = d.max_backups || '-';
        document.getElementById('st-calendar').textContent = d.on_calendar || '-';
        document.getElementById('st-run').textContent = d.last_run || '-';
        document.getElementById('st-message').textContent = d.last_message || '-';
        document.getElementById('st-file').textContent = d.last_file || '-';
        document.getElementById('st-size').textContent = humanBytes(d.last_size_bytes || 0);

        setPill('st-auto', d.auto_mode || '-', ['aktiviert']);
        setPill('st-result', d.last_result || '-', ['ok']);
      } catch (err) {
        console.error('Status konnte nicht geladen werden:', err);
        setPill('st-auto', 'unbekannt', []);
        setPill('st-result', 'Fehler', []);
      }
    }

    document.getElementById('btn-refresh').addEventListener('click', loadStatus);
    loadConfig();
    loadStatus();
    setInterval(loadStatus, 5000);
  </script>
</body>
</html>
EOF

# 12. Sudoers-Regeln
echo "data: Erstelle sudoers-Regeln..."
echo ""
sudo tee "$SUDOERS_FILE" > /dev/null <<'EOF'
www-data ALL=(ALL) NOPASSWD: /usr/local/bin/external_backup_run.sh
www-data ALL=(ALL) NOPASSWD: /usr/local/bin/external_backup_apply_timer.sh
www-data ALL=(ALL) NOPASSWD: /bin/systemctl
EOF
sudo chmod 440 "$SUDOERS_FILE"

# 13. Standard-Timer schreiben
echo "data: Schreibe Standard-Timer..."
echo ""
sudo /usr/local/bin/external_backup_apply_timer.sh write

# 14. Button auf index.html hinzufügen
LINK='<button type="button" onclick="window.location.href='\''externe_backup.html'\''">Externe Backup Funktion</button>'

if [ -f "$INDEX_HTML" ] && ! grep -q "externe_backup.html" "$INDEX_HTML"; then
  echo "data: Füge Link zur index.html hinzu..."
  echo ""
  sudo sed -i "/<div class=\"button-container\">/,/<\/div>/ {
    /<\/div>/ i \\        $LINK
  }" "$INDEX_HTML"
fi

echo ""
echo "data: Fertig! Öffne im Browser: http://<IP>/externe_backup.html"
echo ""
