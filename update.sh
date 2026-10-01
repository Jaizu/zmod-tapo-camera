#!/bin/sh
set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
"$PLUGIN_DIR/install.sh"
exec "$PLUGIN_DIR/install.sh"
