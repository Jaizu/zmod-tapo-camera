# Shared helpers for the Tapo camera plugin. Sourced by the other scripts;
# expects PLUGIN_DIR to be set by the caller.

# Z-Mod runs Moonraker chrooted in /usr/data/.mod/.zmod, where /root/printer_data/config
# is the same directory as /usr/data/config (the one Mainsail shows). Outside the chroot
# (power_on.sh, Klipper) /root/printer_data/config is a different, hidden directory, so
# the configuration lives in /usr/data/config, which is the same path on both sides.
CONFIG_DIR="/usr/data/config"
CONF="$CONFIG_DIR/tapo_camera.conf"
# Older versions used these; the first one found is migrated when $CONF is missing.
LEGACY_CONFS="/root/printer_data/config/tapo_camera.conf /usr/data/config/mod_data/tapo_camera.conf"

GO2RTC="$PLUGIN_DIR/bin/go2rtc"
RUN_DIR="/tmp/tapo_camera"
GO2RTC_CONF="$RUN_DIR/go2rtc.yaml"
PIDFILE="$RUN_DIR/supervisor.pid"
LOGFILE="/usr/data/logs/tapo_camera.log"

# Only used for on-demand snapshots (/api/frame.jpeg); live video is not transcoded.
FFMPEG="/usr/prog/ffmpeg-4.0.2/bin/ffmpeg"
FFMPEG_LD="/usr/prog/ffmpeg-4.0.2/lib:/usr/prog/x264/lib"

PYTHON="/usr/prog/Python-3.8.2/bin/python3"
PYTHON_LD="/usr/prog/Python-3.8.2/lib:/usr/prog/openssl-1.0.2d/lib"

STREAM_NAME="tapo"

# ensure_config: create $CONF from a legacy copy or the example when it is missing.
ensure_config() {
    [ -f "$CONF" ] && return 0
    mkdir -p "$CONFIG_DIR"
    for _legacy in $LEGACY_CONFS; do
        if [ -f "$_legacy" ]; then
            cp "$_legacy" "$CONF"
            chmod 600 "$CONF"
            echo "Migrated configuration from $_legacy to $CONF"
            return 0
        fi
    done
    cp "$PLUGIN_DIR/tapo_camera.conf.example" "$CONF"
    chmod 600 "$CONF"
    echo "Created $CONF; configure the Tapo camera first."
}

# read_config KEY [DEFAULT]: value of KEY in $CONF, unquoted; DEFAULT when unset or empty.
read_config() {
    _value=""
    if [ -f "$CONF" ]; then
        _value="$(awk -v wanted="$1" '
            /^[[:space:]]*#/ || index($0, "=") == 0 { next }
            {
                name = $0
                sub(/=.*/, "", name)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
                if (toupper(name) == wanted) {
                    value = $0
                    sub(/^[^=]*=/, "", value)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                    quote = sprintf("%c", 39)
                    first = substr(value, 1, 1)
                    last = substr(value, length(value), 1)
                    if (first == "\"" || first == quote) value = substr(value, 2)
                    if (last == "\"" || last == quote) value = substr(value, 1, length(value) - 1)
                    print value
                    exit
                }
            }
        ' "$CONF")"
    fi
    if [ -z "$_value" ]; then
        _value="${2:-}"
    fi
    printf '%s\n' "$_value"
}

# urlencode STRING: percent-encode everything except RFC 3986 unreserved characters.
urlencode() {
    printf '%s' "$1" | awk '
        BEGIN {
            for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
            safe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        }
        {
            if (NR > 1) printf "%%0A"
            n = length($0)
            for (i = 1; i <= n; i++) {
                c = substr($0, i, 1)
                if (index(safe, c)) printf "%s", c
                else printf "%%%02X", ord[c]
            }
        }
    '
}

# is_number VALUE: true for a non-empty string of digits.
is_number() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

# detect_public_host: IPv4 address of the interface holding the default route.
detect_public_host() {
    _addr=""
    if command -v ip >/dev/null 2>&1; then
        _addr="$(ip -4 route get 192.0.2.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
    fi
    if [ -z "$_addr" ] && [ -x "$PYTHON" ]; then
        _addr="$(LD_LIBRARY_PATH="$PYTHON_LD${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            "$PYTHON" -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("192.0.2.1", 9)); print(s.getsockname()[0]); s.close()' 2>/dev/null)"
    fi
    [ -n "$_addr" ] || return 1
    printf '%s\n' "$_addr"
}

# public_host: HTTP_PUBLIC_HOST from the config, auto-detected when "auto" or empty.
public_host() {
    _phost="$(read_config HTTP_PUBLIC_HOST auto)"
    case "$_phost" in
        auto|AUTO) _phost="$(detect_public_host)" || return 1 ;;
    esac
    case "$_phost" in
        ''|*[!A-Za-z0-9.-]*) return 1 ;;
    esac
    printf '%s\n' "$_phost"
}
