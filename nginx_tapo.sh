#!/bin/sh
set -e

NGINX="/usr/prog/nginx/sbin/nginx"
NGINX_CONF="/usr/data/zmod/zmod/.shell/root/nginx/nginx.conf"
BACKUP="/usr/data/config/mod_data/tapo_camera.nginx.conf.bak"
MARK_BEGIN="    # ZMOD_TAPO_CAMERA_BEGIN"
MARK_END="    # ZMOD_TAPO_CAMERA_END"

install_route() {
    [ -f "$NGINX_CONF" ] || { echo "Nginx config not found: $NGINX_CONF" >&2; exit 1; }

    if grep -q "ZMOD_TAPO_CAMERA_BEGIN" "$NGINX_CONF"; then
        echo "Tapo Nginx route already installed"
        return 0
    fi

    cp "$NGINX_CONF" "$BACKUP"

    awk '
    /    server \{/ && !done {
        print
        print "        # ZMOD_TAPO_CAMERA_BEGIN"
        print "        location /tapo/ {"
        print "            postpone_output 0;"
        print "            proxy_buffering off;"
        print "            proxy_ignore_headers X-Accel-Buffering;"
        print "            proxy_http_version 1.1;"
        print "            proxy_set_header Host $http_host;"
        print "            proxy_set_header X-Real-IP $remote_addr;"
        print "            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
        print "            proxy_read_timeout 86400s;"
        print "            proxy_pass http://127.0.0.1:8090/;"
        print "        }"
        print "        # ZMOD_TAPO_CAMERA_END"
        done=1
        next
    }
    { print }
    ' "$NGINX_CONF" > "$NGINX_CONF.tmp"

    mv "$NGINX_CONF.tmp" "$NGINX_CONF"

    if "$NGINX" -t -c "$NGINX_CONF"; then
        "$NGINX" -s reload -c "$NGINX_CONF" 2>/dev/null || true
        echo "Installed /tapo/ Nginx route"
    else
        cp "$BACKUP" "$NGINX_CONF"
        echo "Nginx configuration test failed; restored backup" >&2
        exit 1
    fi
}

remove_route() {
    [ -f "$NGINX_CONF" ] || exit 0

    if [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$NGINX_CONF"
        "$NGINX" -t -c "$NGINX_CONF" && "$NGINX" -s reload -c "$NGINX_CONF" 2>/dev/null || true
        echo "Restored Nginx configuration backup"
        return 0
    fi

    awk '
    /ZMOD_TAPO_CAMERA_BEGIN/ { skip=1 }
    !skip { print }
    /ZMOD_TAPO_CAMERA_END/ { skip=0 }
    ' "$NGINX_CONF" > "$NGINX_CONF.tmp"
    mv "$NGINX_CONF.tmp" "$NGINX_CONF"
    "$NGINX" -t -c "$NGINX_CONF" && "$NGINX" -s reload -c "$NGINX_CONF" 2>/dev/null || true
}

case "${1:-install}" in
    install) install_route ;;
    remove) remove_route ;;
    *) echo "Usage: $0 {install|remove}"; exit 1 ;;
esac
