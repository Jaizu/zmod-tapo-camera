#!/bin/sh
set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

CONFIG_DIR="/root/printer_data/config"
CONF="$CONFIG_DIR/tapo_camera.conf"

POWER_ON="/usr/data/config/mod_data/power_on.sh"
POWER_ON_BACKUP="/usr/data/config/mod_data/power_on.sh.tapo_camera.orig"

MARK_BEGIN="# ZMOD_TAPO_CAMERA_BEGIN"
MARK_END="# ZMOD_TAPO_CAMERA_END"

SERVICE="$PLUGIN_DIR/tapo_camera.sh"

echo "Stopping Tapo camera..."
"$SERVICE" stop 2>/dev/null || true

#
# Restore the original power_on.sh.
#
if [ -f "$POWER_ON_BACKUP" ]; then
    echo "Restoring original power_on.sh..."
    cp "$POWER_ON_BACKUP" "$POWER_ON"
    chmod 755 "$POWER_ON"
    rm -f "$POWER_ON_BACKUP"
elif [ -f "$POWER_ON" ]; then
    #
    # Fallback for installations where the backup is unavailable.
    # Remove only our marked block.
    #
    TMP="${POWER_ON}.tmp"

    awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
        $0 == begin { skip=1; next }
        $0 == end {
            skip=0
            next
        }
        !skip { print }
    ' "$POWER_ON" > "$TMP"

    mv "$TMP" "$POWER_ON"
    chmod 755 "$POWER_ON"
fi

#
# Remove Nginx integration.
#
"$PLUGIN_DIR/nginx_tapo.sh" uninstall 2>/dev/null || true

#
# Remove configuration.
#
rm -f "$CONF"

echo "Removing plugin files..."

#
# The script is running from inside the plugin directory, so
# remove everything except this script after the cleanup has completed.
#
cd /
rm -rf "$PLUGIN_DIR"

echo
echo "tapo_camera uninstalled."