#!/bin/sh
set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

USER_CONFIG_DIR="/usr/data/config/mod_data"
CONF="/root/printer_data/config/tapo_camera.conf"

MOONRAKER_CONF="$USER_CONFIG_DIR/user.moonraker.conf"
MOONRAKER_CREATED="$MOONRAKER_CONF.tapo_camera.created"
POWER_ON="$USER_CONFIG_DIR/power_on.sh"
POWER_ON_BACKUP="$POWER_ON.tapo_camera.orig"
POWER_ON_CREATED="$POWER_ON.tapo_camera.created"

MARK_BEGIN="# ZMOD_TAPO_CAMERA_BEGIN"
MARK_END="# ZMOD_TAPO_CAMERA_END"
MOONRAKER_CONFIG_CHANGED=0
TMP=""
CONTENT=""

cleanup() {
    [ -z "$TMP" ] || rm -f "$TMP"
    [ -z "$CONTENT" ] || rm -f "$CONTENT"
}

trap cleanup 0

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

echo "Stopping Tapo camera..."
if [ -x "$PLUGIN_DIR/tapo_camera.sh" ]; then
    "$PLUGIN_DIR/tapo_camera.sh" stop
fi

if [ -f "$MOONRAKER_CONF" ] && grep -Fqx "$MARK_BEGIN" "$MOONRAKER_CONF"; then
    TMP="$(mktemp "${MOONRAKER_CONF}.tapo_camera.XXXXXX")"
    CONTENT="$(mktemp "${MOONRAKER_CONF}.tapo_camera.XXXXXX")"
    strip_managed_block "$MOONRAKER_CONF" "$CONTENT"

    if [ -f "$MOONRAKER_CREATED" ] && ! awk 'NF { found=1 } END { exit !found }' "$CONTENT"; then
        rm -f "$MOONRAKER_CONF"
        MOONRAKER_CONFIG_CHANGED=1
    else
        cp -p "$MOONRAKER_CONF" "$TMP"
        cat "$CONTENT" > "$TMP"
        if ! cmp -s "$MOONRAKER_CONF" "$TMP"; then
            mv "$TMP" "$MOONRAKER_CONF"
            MOONRAKER_CONFIG_CHANGED=1
        fi
    fi
    rm -f "$MOONRAKER_CREATED"
    rm -f "$TMP" "$CONTENT"
    TMP=""
    CONTENT=""
elif [ -f "$MOONRAKER_CREATED" ]; then
    rm -f "$MOONRAKER_CREATED"
fi

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
    if grep -Fqx "$MARK_BEGIN" "$POWER_ON"; then
        TMP="$(mktemp "${POWER_ON}.tapo_camera.XXXXXX")"
        CONTENT="$(mktemp "${POWER_ON}.tapo_camera.XXXXXX")"
        strip_managed_block "$POWER_ON" "$CONTENT"
        cp -p "$POWER_ON" "$TMP"
        cat "$CONTENT" > "$TMP"
        mv "$TMP" "$POWER_ON"
        rm -f "$CONTENT"
        TMP=""
        CONTENT=""
    fi
fi

rm -f "$CONF"

echo "Removing plugin files..."
cd /
rm -rf "$PLUGIN_DIR"

echo
echo "tapo_camera uninstalled."
if [ "$MOONRAKER_CONFIG_CHANGED" -eq 1 ]; then
    echo "Moonraker webcam configuration removed. Restart Moonraker from Mainsail to apply it."
fi
echo "Nginx was not modified."
