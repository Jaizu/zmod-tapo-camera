#!/bin/sh
set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
chmod 700 "$PLUGIN_DIR/tapo_camera.py" "$PLUGIN_DIR/tapo_camera.sh"

# Reinstall the startup hook without replacing the user's configuration.
"$PLUGIN_DIR/install.sh"

echo "tapo_camera updated."
