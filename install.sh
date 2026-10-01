#!/bin/sh

set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

CONFIG_DIR="/root/printer_data/config"
LEGACY_CONF="/usr/data/config/mod_data/tapo_camera.conf"
CONF="$CONFIG_DIR/tapo_camera.conf"

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
PYTHON="/usr/prog/Python-3.8.2/bin/python3"
PYTHON_LD="/usr/prog/Python-3.8.2/lib:/usr/prog/openssl-1.0.2d/lib"
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
chmod 700 "$PLUGIN_DIR/tapo_camera.py" "$SERVICE"

if [ ! -f "$CONF" ]; then
    if [ -f "$LEGACY_CONF" ]; then
        cp "$LEGACY_CONF" "$CONF"
        echo "Migrated existing configuration from $LEGACY_CONF"
    else
        cp "$PLUGIN_DIR/tapo_camera.conf.example" "$CONF"
    fi
    chmod 600 "$CONF"
    echo "Created $CONF"
fi

read_config() {
    awk -v wanted="$1" '
        /^[[:space:]]*#/ || index($0, "=") == 0 { next }
        {
            name = $0
            sub(/=.*/, "", name)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            if (toupper(name) == wanted) {
                value = $0
                sub(/^[^=]*=/, "", value)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                quote = sprintf("%c", 39)
                first = substr(value, 1, 1)
                last = substr(value, length(value), 1)
                if (first == "\"" || first == quote) value = substr(value, 2)
                if (last == "\"" || last == quote) value = substr(value, 1, length(value) - 1)
                print value
                exit
            }
        }
    ' "$CONF"
}

HTTP_PORT="$(read_config HTTP_PORT)"
FPS="$(read_config FPS)"
PUBLIC_HOST="$(read_config HTTP_PUBLIC_HOST)"
ENABLED="$(read_config ENABLED)"

case "$ENABLED" in
    1) CAMERA_ENABLED=true ;;
    0) CAMERA_ENABLED=false ;;
    *)
        echo "ERROR: ENABLED must be 0 or 1 in $CONF" >&2
        exit 1
        ;;
esac

case "$HTTP_PORT" in
    ''|*[!0-9]*)
        echo "ERROR: HTTP_PORT must be a number in $CONF" >&2
        exit 1
        ;;
esac

if [ "$HTTP_PORT" -lt 1 ] || [ "$HTTP_PORT" -gt 65535 ]; then
    echo "ERROR: HTTP_PORT must be between 1 and 65535" >&2
    exit 1
fi

case "$FPS" in
    ''|*[!0-9]*)
        echo "ERROR: FPS must be a number in $CONF" >&2
        exit 1
        ;;
esac

if [ "$FPS" -lt 1 ]; then
    echo "ERROR: FPS must be greater than zero" >&2
    exit 1
fi

case "$PUBLIC_HOST" in
    ''|auto|AUTO)
        if [ ! -x "$PYTHON" ]; then
            echo "ERROR: Python not found: $PYTHON" >&2
            exit 1
        fi
        PUBLIC_HOST="$(LD_LIBRARY_PATH="$PYTHON_LD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            "$PYTHON" -c 'import socket; sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); sock.connect(("192.0.2.1", 9)); print(sock.getsockname()[0]); sock.close()' 2>/dev/null)" || {
            echo "ERROR: Could not determine the printer address. Set HTTP_PUBLIC_HOST in $CONF." >&2
            exit 1
        }
        ;;
esac

case "$PUBLIC_HOST" in
    ''|*[!A-Za-z0-9.-]*)
        echo "ERROR: HTTP_PUBLIC_HOST must be an IPv4 address or hostname" >&2
        exit 1
        ;;
esac

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

TMP_MOONRAKER="$(mktemp "${MOONRAKER_CONF}.tapo_camera.XXXXXX")"
CONTENT_MOONRAKER="$(mktemp "${MOONRAKER_CONF}.tapo_camera.XXXXXX")"
strip_managed_block "$MOONRAKER_CONF" "$CONTENT_MOONRAKER"

TMP_MOONRAKER="$(mktemp "${MOONRAKER_CONF}.tapo_camera.XXXXXX")"
update_manager_path "$CONTENT_MOONRAKER" "$TMP_MOONRAKER"
mv "$TMP_MOONRAKER" "$CONTENT_MOONRAKER"
TMP_MOONRAKER=""

if grep -Fqx "$CAMERA_SECTION" "$CONTENT_MOONRAKER"; then
    echo "ERROR: $CAMERA_SECTION already exists outside the plugin block; leaving it unchanged." >&2
    exit 1
fi

cp -p "$MOONRAKER_CONF" "$TMP_MOONRAKER"
cat "$CONTENT_MOONRAKER" > "$TMP_MOONRAKER"
printf '%s\n%s\nenabled: %s\nservice: ipstream\ntarget_fps: %s\nstream_url: http://%s:%s/\n%s\n' \
    "$MARK_BEGIN" "$CAMERA_SECTION" "$CAMERA_ENABLED" "$FPS" "$PUBLIC_HOST" "$HTTP_PORT" "$MARK_END" >> "$TMP_MOONRAKER"

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
echo "HTTP endpoint: http://$PUBLIC_HOST:$HTTP_PORT/"
if [ "$MOONRAKER_CONF_CHANGED" -eq 1 ]; then
    echo "Moonraker webcam configuration changed. Restart Moonraker from Mainsail to load it."
fi
