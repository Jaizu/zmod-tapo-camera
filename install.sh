#!/bin/sh
set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MOD_CONF="/usr/data/config/mod_data"
CONF="$MOD_CONF/tapo_camera.conf"

mkdir -p "$MOD_CONF" /usr/data/logs
chmod 700 "$PLUGIN_DIR/tapo_camera.py" "$PLUGIN_DIR/tapo_camera.sh"

if [ ! -f "$CONF" ]; then
    cp "$PLUGIN_DIR/tapo_camera.conf.example" "$CONF"
    chmod 600 "$CONF"
    echo "Created $CONF"
fi

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
