#!/bin/sh

set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$PLUGIN_DIR/lib.sh"

USER_CONFIG_DIR="/usr/data/config/mod_data"
MOONRAKER_CONF="$USER_CONFIG_DIR/user.moonraker.conf"
MOONRAKER_CREATED="$MOONRAKER_CONF.tapo_camera.created"

POWER_ON="$USER_CONFIG_DIR/power_on.sh"
POWER_ON_BACKUP="$POWER_ON.tapo_camera.orig"
POWER_ON_CREATED="$POWER_ON.tapo_camera.created"

MARK_BEGIN="# ZMOD_TAPO_CAMERA_BEGIN"
MARK_END="# ZMOD_TAPO_CAMERA_END"
CAMERA_SECTION="[webcam Tapo C210]"
UPDATE_MANAGER_SECTION="[update_manager tapo_camera]"
SERVICE="$PLUGIN_DIR/tapo_camera.sh"
MOONRAKER_CONF_CHANGED=0
TMP_POWER=""
CONTENT_POWER=""
TMP_MOONRAKER=""
CONTENT_MOONRAKER=""

cleanup() {
    [ -z "$TMP_POWER" ] || rm -f "$TMP_POWER"
    [ -z "$CONTENT_POWER" ] || rm -f "$CONTENT_POWER"
    [ -z "$TMP_MOONRAKER" ] || rm -f "$TMP_MOONRAKER"
    [ -z "$CONTENT_MOONRAKER" ] || rm -f "$CONTENT_MOONRAKER"
}

trap cleanup 0

mkdir -p "$CONFIG_DIR" /usr/data/logs "$USER_CONFIG_DIR"
# Git tracks these as executable; make sure a checkout without modes still works.
# 755 keeps the tracked mode, so the plugin repository is not reported as dirty.
chmod 755 "$SERVICE" "$GO2RTC"

ensure_config

ENABLED="$(read_config ENABLED 0)"
FPS="$(read_config FPS 15)"
API_PORT="$(read_config API_PORT 1984)"
ASPECT_RATIO="$(read_config ASPECT_RATIO 16:9)"

case "$ENABLED" in
    1) CAMERA_ENABLED=true ;;
    0) CAMERA_ENABLED=false ;;
    *)
        echo "ERROR: ENABLED must be 0 or 1 in $CONF" >&2
        exit 1
        ;;
esac

if ! is_number "$API_PORT" || [ "$API_PORT" -lt 1 ] || [ "$API_PORT" -gt 65535 ]; then
    echo "ERROR: API_PORT must be between 1 and 65535 in $CONF" >&2
    exit 1
fi

if ! is_number "$FPS" || [ "$FPS" -lt 1 ]; then
    echo "ERROR: FPS must be a number greater than zero in $CONF" >&2
    exit 1
fi

case "$ASPECT_RATIO" in
    *[!0-9:]*|'')
        echo "ERROR: ASPECT_RATIO must look like 16:9 in $CONF" >&2
        exit 1
        ;;
esac

PUBLIC_HOST="$(public_host)" || {
    echo "ERROR: Could not determine the printer address. Set HTTP_PUBLIC_HOST in $CONF." >&2
    exit 1
}

strip_managed_block() {
    awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
        $0 == begin {
            inside=1
            next
        }
        $0 == end && inside {
            inside=0
            next
        }
        !inside { print }
        END {
            if (inside) {
                print "ERROR: unterminated ZMOD_TAPO_CAMERA block" > "/dev/stderr"
                exit 2
            }
        }
    ' "$1" > "$2"
}

update_manager_path() {
    awk -v section="$UPDATE_MANAGER_SECTION" -v path="$PLUGIN_DIR" '
        /^\[[^]]+\][[:space:]]*$/ {
            in_section = ($0 == section)
        }
        in_section && /^[[:space:]]*path[[:space:]]*:/ {
            print "path: " path
            next
        }
        { print }
    ' "$1" > "$2"
}

if [ ! -f "$MOONRAKER_CONF" ]; then
    if [ -e "$MOONRAKER_CONF" ]; then
        echo "ERROR: $MOONRAKER_CONF exists but is not a regular file." >&2
        exit 1
    fi
    : > "$MOONRAKER_CONF"
    chmod 644 "$MOONRAKER_CONF"
    touch "$MOONRAKER_CREATED"
fi

CONTENT_MOONRAKER="$(mktemp "${MOONRAKER_CONF}.tapo_camera.XXXXXX")"
strip_managed_block "$MOONRAKER_CONF" "$CONTENT_MOONRAKER"

TMP_MOONRAKER="$(mktemp "${MOONRAKER_CONF}.tapo_camera.XXXXXX")"
update_manager_path "$CONTENT_MOONRAKER" "$TMP_MOONRAKER"
mv "$TMP_MOONRAKER" "$CONTENT_MOONRAKER"
TMP_MOONRAKER="$(mktemp "${MOONRAKER_CONF}.tapo_camera.XXXXXX")"

if grep -Fqx "$CAMERA_SECTION" "$CONTENT_MOONRAKER"; then
    echo "ERROR: $CAMERA_SECTION already exists outside the plugin block; leaving it unchanged." >&2
    exit 1
fi

BASE_URL="http://$PUBLIC_HOST:$API_PORT/api"
cp -p "$MOONRAKER_CONF" "$TMP_MOONRAKER"
cat "$CONTENT_MOONRAKER" > "$TMP_MOONRAKER"
cat >> "$TMP_MOONRAKER" <<EOF
$MARK_BEGIN
$CAMERA_SECTION
enabled: $CAMERA_ENABLED
service: webrtc-go2rtc
target_fps: $FPS
aspect_ratio: $ASPECT_RATIO
stream_url: $BASE_URL/ws?src=$STREAM_NAME
snapshot_url: $BASE_URL/frame.jpeg?src=$STREAM_NAME
$MARK_END
EOF

if cmp -s "$MOONRAKER_CONF" "$TMP_MOONRAKER"; then
    rm -f "$TMP_MOONRAKER"
else
    mv "$TMP_MOONRAKER" "$MOONRAKER_CONF"
    MOONRAKER_CONF_CHANGED=1
fi
TMP_MOONRAKER=""

if [ ! -e "$POWER_ON" ]; then
    if [ -f "$POWER_ON_BACKUP" ]; then
        cp -p "$POWER_ON_BACKUP" "$POWER_ON"
    else
        printf '#!/bin/sh\n#Enter Poweron code here\n' > "$POWER_ON"
        chmod 755 "$POWER_ON"
        touch "$POWER_ON_CREATED"
    fi
fi

if [ ! -f "$POWER_ON" ]; then
    echo "ERROR: $POWER_ON exists but is not a regular file." >&2
    exit 1
fi

if [ ! -f "$POWER_ON_BACKUP" ] && [ ! -f "$POWER_ON_CREATED" ]; then
    cp -p "$POWER_ON" "$POWER_ON_BACKUP"
fi

TMP_POWER="$(mktemp "${POWER_ON}.tapo_camera.XXXXXX")"
CONTENT_POWER="$(mktemp "${POWER_ON}.tapo_camera.XXXXXX")"
strip_managed_block "$POWER_ON" "$CONTENT_POWER"
cp -p "$POWER_ON" "$TMP_POWER"
cat "$CONTENT_POWER" > "$TMP_POWER"
printf '%s\n"%s" start\n%s\n' "$MARK_BEGIN" "$SERVICE" "$MARK_END" >> "$TMP_POWER"

if cmp -s "$POWER_ON" "$TMP_POWER"; then
    rm -f "$TMP_POWER"
else
    mv "$TMP_POWER" "$POWER_ON"
fi
TMP_POWER=""

echo "Restarting Tapo camera..."
"$SERVICE" restart

echo

echo "Configuration: $CONF"
echo "Stream (WebRTC): $BASE_URL/ws?src=$STREAM_NAME"
echo "Snapshot: $BASE_URL/frame.jpeg?src=$STREAM_NAME"
if [ "$MOONRAKER_CONF_CHANGED" -eq 1 ]; then
    echo "Moonraker webcam configuration changed. Reboot the printer (or restart Moonraker) to load it."
fi
