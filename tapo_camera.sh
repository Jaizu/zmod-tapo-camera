#!/bin/sh

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PIDFILE="/tmp/tapo_camera.pid"
LOGFILE="/usr/data/logs/tapo_camera.log"
PYTHON="/usr/prog/Python-3.8.2/bin/python3"
PYTHON_LD="/usr/prog/Python-3.8.2/lib:/usr/prog/openssl-1.0.2d/lib"
CONFIG="/root/printer_data/config/tapo_camera.conf"

mkdir -p /usr/data/logs /usr/data/config/mod_data

start() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        echo "tapo_camera already running (PID $(cat "$PIDFILE"))"
        return 0
    fi
    if [ ! -f "$CONFIG" ]; then
        cp "$PLUGIN_DIR/tapo_camera.conf.example" "$CONFIG"
        chmod 644 "$CONFIG"
        echo "Created $CONFIG; configure the Tapo camera first."
    fi
    export TAPO_CONFIG="$CONFIG"
    export LD_LIBRARY_PATH="$PYTHON_LD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [ "${TEST_SOURCE:-0}" = "1" ]; then
        echo "Starting Tapo camera test source"
        TEST_SOURCE=1 "$PYTHON" "$PLUGIN_DIR/tapo_camera.py" >>"$LOGFILE" 2>&1 &
    else
        echo "Starting Tapo camera service"
        "$PYTHON" "$PLUGIN_DIR/tapo_camera.py" >>"$LOGFILE" 2>&1 &
    fi
    echo $! > "$PIDFILE"
}

stop() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE" 2>/dev/null)
        kill "$PID" 2>/dev/null || true
        sleep 1
        kill -9 "$PID" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi
    # Kill only children belonging to this plugin if the wrapper PID disappeared.
    pkill -f "$PLUGIN_DIR/tapo_camera.py" 2>/dev/null || true
}

status() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        echo "tapo_camera running (PID $(cat "$PIDFILE"))"
        return 0
    fi
    echo "tapo_camera stopped"
    return 1
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    status) status ;;
    *) echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
