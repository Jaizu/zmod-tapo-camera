#!/bin/sh

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

PIDFILE="/tmp/tapo_camera.pid"
LOGFILE="/usr/data/logs/tapo_camera.log"

PYTHON="/usr/prog/Python-3.8.2/bin/python3"
PYTHON_LD="/usr/prog/Python-3.8.2/lib:/usr/prog/openssl-1.0.2d/lib"

CONFIG="/root/printer_data/config/tapo_camera.conf"

mkdir -p /usr/data/logs

is_camera_process() {
    [ -r "/proc/$1/cmdline" ] || return 1
    CMDLINE="$(tr '\000' ' ' < "/proc/$1/cmdline" 2>/dev/null)"
    case "$CMDLINE" in
        *"$PLUGIN_DIR/tapo_camera.py"*) return 0 ;;
    esac
    return 1
}

find_camera_pid() {
    if command -v pgrep >/dev/null 2>&1; then
        PID="$(pgrep -f "$PLUGIN_DIR/tapo_camera.py" 2>/dev/null | head -n 1)"
        [ -n "$PID" ] || return 1
        printf '%s\n' "$PID"
        return 0
    fi

    for CMDLINE_FILE in /proc/[0-9]*/cmdline; do
        [ -r "$CMDLINE_FILE" ] || continue
        CMDLINE="$(tr '\000' ' ' < "$CMDLINE_FILE" 2>/dev/null)"
        case "$CMDLINE" in
            *"$PLUGIN_DIR/tapo_camera.py"*)
                CAMERA_PID="${CMDLINE_FILE#/proc/}"
                CAMERA_PID="${CAMERA_PID%/cmdline}"
                printf '%s\n' "$CAMERA_PID"
                return 0
                ;;
        esac
    done
    return 1
}

is_enabled() {
    ENABLED="$(sed -n 's/^[[:space:]]*ENABLED[[:space:]]*=[[:space:]]*//p' "$CONFIG" | head -n 1)"

    [ "$ENABLED" = "1" ]
}

start() {
    if [ ! -f "$CONFIG" ]; then
        cp "$PLUGIN_DIR/tapo_camera.conf.example" "$CONFIG"
        chmod 644 "$CONFIG"
        echo "Created $CONFIG; configure the Tapo camera first."
    fi

    if [ "${TEST_SOURCE:-0}" != "1" ] && ! is_enabled; then
        if [ -n "$(find_camera_pid 2>/dev/null || true)" ]; then
            stop
        fi
        rm -f "$PIDFILE"
        echo "tapo_camera disabled (ENABLED != 1)"
        return 0
    fi

    if [ -f "$PIDFILE" ]; then
        PID="$(cat "$PIDFILE" 2>/dev/null)"
        if is_camera_process "$PID"; then
            echo "tapo_camera already running (PID $PID)"
            return 0
        fi
        rm -f "$PIDFILE"
    fi

    PID="$(find_camera_pid 2>/dev/null || true)"
    if [ -n "$PID" ]; then
        echo "$PID" > "$PIDFILE"
        echo "tapo_camera already running (PID $PID)"
        return 0
    fi

    if [ ! -x "$PYTHON" ]; then
        echo "ERROR: Python not found: $PYTHON"
        return 1
    fi

    export TAPO_CONFIG="$CONFIG"
    export LD_LIBRARY_PATH="$PYTHON_LD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    if [ "${TEST_SOURCE:-0}" = "1" ]; then
        echo "Starting Tapo camera test source"

        TEST_SOURCE=1 \
        "$PYTHON" "$PLUGIN_DIR/tapo_camera.py" >>"$LOGFILE" 2>&1 &

    else
        echo "Starting Tapo camera service"

        "$PYTHON" "$PLUGIN_DIR/tapo_camera.py" >>"$LOGFILE" 2>&1 &
    fi

    echo $! > "$PIDFILE"

    sleep 1

    if ! kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        echo "ERROR: Tapo camera failed to start"
        rm -f "$PIDFILE"
        return 1
    fi

    echo "tapo_camera started (PID $(cat "$PIDFILE"))"
}

stop() {
    if [ -f "$PIDFILE" ]; then
        PID="$(cat "$PIDFILE" 2>/dev/null)"

        if is_camera_process "$PID"; then
            kill "$PID" 2>/dev/null || true
            sleep 1
            if is_camera_process "$PID"; then
                kill -9 "$PID" 2>/dev/null || true
            fi
        fi

        rm -f "$PIDFILE"
    fi

    while PID="$(find_camera_pid 2>/dev/null)"; do
        kill "$PID" 2>/dev/null || true
        sleep 1
        if is_camera_process "$PID"; then
            kill -9 "$PID" 2>/dev/null || true
        fi
    done

    echo "tapo_camera stopped"
}

status() {
    if [ -f "$PIDFILE" ]; then
        PID="$(cat "$PIDFILE" 2>/dev/null)"
        if is_camera_process "$PID"; then
            echo "tapo_camera running (PID $PID)"
            return 0
        fi
    fi

    PID="$(find_camera_pid 2>/dev/null || true)"
    if [ -n "$PID" ]; then
        echo "tapo_camera running (PID $PID)"
        return 0
    fi

    echo "tapo_camera stopped"
    return 1
}

case "${1:-}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
