#!/bin/sh
set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

CONFIG_DIR="/root/printer_data/config"
CONF="$CONFIG_DIR/tapo_camera.conf"

POWER_ON="/usr/data/config/mod_data/power_on.sh"
POWER_ON_BACKUP="/usr/data/config/mod_data/power_on.sh.tapo_camera.orig"
POWER_ON_CREATED="/usr/data/config/mod_data/power_on.sh.tapo_camera.created"

MARK_BEGIN="# ZMOD_TAPO_CAMERA_BEGIN"
MARK_END="# ZMOD_TAPO_CAMERA_END"

SERVICE="$PLUGIN_DIR/tapo_camera.sh"

echo "Stopping Tapo camera..."

"$SERVICE" stop

"$PLUGIN_DIR/nginx_tapo.sh" uninstall

#
# Restore the original power_on.sh if the plugin backed it up.
#

if [ -f "$POWER_ON_BACKUP" ]; then
    echo "Restoring original power_on.sh..."

    cp -p "$POWER_ON_BACKUP" "$POWER_ON"
    rm -f "$POWER_ON_BACKUP" "$POWER_ON_CREATED"

elif [ -f "$POWER_ON_CREATED" ]; then
    echo "Removing power_on.sh created by tapo_camera..."
    rm -f "$POWER_ON" "$POWER_ON_CREATED"
elif [ -f "$POWER_ON" ]; then
    if grep -Fqx "$MARK_BEGIN" "$POWER_ON" && grep -Fqx "$MARK_END" "$POWER_ON"; then
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
        mv "$TMP" "$POWER_ON"
    fi
fi

rm -f "$CONF"

echo "Removing plugin files..."

cd /
rm -rf "$PLUGIN_DIR"

echo
echo "tapo_camera uninstalled."
