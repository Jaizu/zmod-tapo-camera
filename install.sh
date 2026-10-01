#!/bin/sh

set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

CONFIG_DIR="/root/printer_data/config"
LEGACY_CONF="/usr/data/config/mod_data/tapo_camera.conf"
CONF="$CONFIG_DIR/tapo_camera.conf"

POWER_ON="/usr/data/config/mod_data/power_on.sh"
POWER_ON_BACKUP="/usr/data/config/mod_data/power_on.sh.tapo_camera.orig"
POWER_ON_CREATED="/usr/data/config/mod_data/power_on.sh.tapo_camera.created"

MARK_BEGIN="# ZMOD_TAPO_CAMERA_BEGIN"
MARK_END="# ZMOD_TAPO_CAMERA_END"

SERVICE="$PLUGIN_DIR/tapo_camera.sh"

mkdir -p "$CONFIG_DIR" /usr/data/logs "$(dirname "$POWER_ON")"

chmod 700 "$PLUGIN_DIR/tapo_camera.py" "$PLUGIN_DIR/tapo_camera.sh"
chmod 755 "$PLUGIN_DIR/nginx_tapo.sh"

#
# Configuration
#

if [ ! -f "$CONF" ]; then
    if [ -f "$LEGACY_CONF" ]; then
        cp "$LEGACY_CONF" "$CONF"
        echo "Migrated existing configuration from $LEGACY_CONF"
    else
        cp "$PLUGIN_DIR/tapo_camera.conf.example" "$CONF"
    fi

    echo "Created $CONF"
fi

chmod 644 "$CONF"

#
# Nginx
#

"$PLUGIN_DIR/nginx_tapo.sh" install

#
# power_on.sh
#

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
    echo "ERROR: $POWER_ON exists but is not a regular file."
    exit 1
fi

#
# Keep the original user file so uninstall can restore it.
#

if [ ! -f "$POWER_ON_BACKUP" ] && [ ! -f "$POWER_ON_CREATED" ]; then
    cp -p "$POWER_ON" "$POWER_ON_BACKUP"
fi

#
# Remove an old Tapo block if one exists.
# This makes installation idempotent.
#

TMP="$(mktemp "${POWER_ON}.tapo_camera.XXXXXX")"
CONTENT="$(mktemp "${POWER_ON}.tapo_camera.XXXXXX")"
trap 'rm -f "$TMP" "$CONTENT"' 0

awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
    $0 == begin && !inside {
        inside=1
        block=$0 ORS
        next
    }

    inside {
        block=block $0 ORS
        if ($0 == end) {
            inside=0
            block=""
        }
        next
    }

    { print }

    END {
        if (inside) {
            printf "%s", block
        }
    }
' "$POWER_ON" > "$CONTENT"

cp -p "$POWER_ON" "$TMP"
cat "$CONTENT" > "$TMP"

#
# Add our startup hook.
#

printf '\n%s\n"%s" start\n\n%s\n' "$MARK_BEGIN" "$SERVICE" "$MARK_END" >> "$TMP"
mv "$TMP" "$POWER_ON"

#
# Start the service now.
#

echo "Starting Tapo camera..."

"$SERVICE" start

echo
echo "tapo_camera installed."
echo "Configuration: $CONF"
echo "HTTP endpoint: http://<printer-ip>:8090/"
echo "Mainsail endpoint: http://<printer-ip>/tapo/"
