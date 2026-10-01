#!/bin/sh
set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_DIR="/root/printer_data/config"
LEGACY_CONF="/usr/data/config/mod_data/tapo_camera.conf"
CONF="$CONFIG_DIR/tapo_camera.conf"

mkdir -p "$CONFIG_DIR" /usr/data/logs
chmod 700 "$PLUGIN_DIR/tapo_camera.py" "$PLUGIN_DIR/tapo_camera.sh"

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

# Install a lightweight startup hook when Z-Mod's plugin directory is used.
# The hook is deliberately independent of Klipper configuration.
HOOK="/usr/data/zmod/zmod/.shell/S99tapo_camera"
cat > "$HOOK" <<EOF2
#!/bin/sh
PLUGIN_DIR="$PLUGIN_DIR"
case "\$1" in
    start|restart) "\$PLUGIN_DIR/tapo_camera.sh" start ;;
    stop) "\$PLUGIN_DIR/tapo_camera.sh" stop ;;
esac
EOF2
chmod 755 "$HOOK"

"$PLUGIN_DIR/nginx_tapo.sh" install

echo "tapo_camera installed."
echo "Edit $CONF before starting the service."
echo "Then run: $PLUGIN_DIR/tapo_camera.sh start"
