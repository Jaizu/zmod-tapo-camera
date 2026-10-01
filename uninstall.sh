#!/bin/sh
PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONF="/usr/data/config/mod_data/tapo_camera.conf"
HOOK="/usr/data/zmod/zmod/.shell/S99tapo_camera"

"$PLUGIN_DIR/tapo_camera.sh" stop 2>/dev/null || true
"$PLUGIN_DIR/nginx_tapo.sh" remove 2>/dev/null || true
rm -f "$HOOK"
# Keep the user's camera configuration so reinstalling does not lose credentials.
echo "tapo_camera service stopped and startup hook removed."
echo "Configuration retained at $CONF"
