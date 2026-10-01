#!/bin/sh
set -e

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$PLUGIN_DIR/install.sh"
