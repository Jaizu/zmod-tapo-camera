#!/bin/sh

set -e

ZMOD_ROOT="/usr/data/.mod/.zmod"

NGINX="/usr/data/zmod/zmod/.shell/root/nginx/nginx"
NGINX_TEMPLATE="/usr/data/zmod/zmod/.shell/root/nginx/nginx.conf"

# This is /root/nginx/nginx.conf from inside the ZMod chroot.
NGINX_CONF_HOST="/usr/data/.mod/.zmod/root/nginx/nginx.conf"
NGINX_CONF_CHROOT="/root/nginx/nginx.conf"

TAPO_BACKUP="/usr/data/config/mod_data/tapo_camera.nginx.conf.bak"

install_route() {
    [ -f "$NGINX_TEMPLATE" ] || {
        echo "ZMod Nginx template not found: $NGINX_TEMPLATE" >&2
        exit 1
    }

    mkdir -p \
        /usr/data/.mod/.zmod/root/nginx/client-body \
        /usr/data/.mod/.zmod/root/nginx/proxy

    # If the route is already present in the template, do not add it again.
    if grep -q "ZMOD_TAPO_CAMERA_BEGIN" "$NGINX_TEMPLATE"; then
        echo "Tapo Nginx route already installed in template"
    else
        cp "$NGINX_TEMPLATE" "$TAPO_BACKUP"

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
        ' "$NGINX_TEMPLATE" > "$NGINX_TEMPLATE.tmp"

        mv "$NGINX_TEMPLATE.tmp" "$NGINX_TEMPLATE"

        echo "Added /tapo/ route to ZMod Nginx template"
    fi

    # Match the way ZMod generates the active configuration.
    CLIENT="fluidd"

    if [ -f /opt/config/mod_data/web.conf ]; then
        . /opt/config/mod_data/web.conf
    fi

    sed \
        -e "s/fluidd/${CLIENT}/g" \
        -e "s/mainsail/${CLIENT}/g" \
        "$NGINX_TEMPLATE" > "$NGINX_CONF_HOST"

    # Nginx lives inside the ZMod chroot.
    if chroot "$ZMOD_ROOT" "$NGINX" \
        -t \
        -c "$NGINX_CONF_CHROOT" \
        -e /usr/data/config/mod_data/log/nginx.log
    then
        echo "Nginx configuration test passed"

        chroot "$ZMOD_ROOT" "$NGINX" \
            -s reload \
            -c "$NGINX_CONF_CHROOT" \
            2>/dev/null || true

        echo "Installed /tapo/ Nginx route"
    else
        echo "Nginx configuration test failed; restoring template backup" >&2

        if [ -f "$TAPO_BACKUP" ]; then
            cp "$TAPO_BACKUP" "$NGINX_TEMPLATE"
        fi

        sed \
            -e "s/fluidd/${CLIENT}/g" \
            -e "s/mainsail/${CLIENT}/g" \
            "$NGINX_TEMPLATE" > "$NGINX_CONF_HOST"

        exit 1
    fi
}

remove_route() {
    [ -f "$NGINX_TEMPLATE" ] || exit 0

    if ! grep -q "ZMOD_TAPO_CAMERA_BEGIN" "$NGINX_TEMPLATE"; then
        echo "Tapo Nginx route is not installed"
        exit 0
    fi

    awk '
    /ZMOD_TAPO_CAMERA_BEGIN/ {
        skip=1
        next
    }

    /ZMOD_TAPO_CAMERA_END/ {
        skip=0
        next
    }

    !skip {
        print
    }
    ' "$NGINX_TEMPLATE" > "$NGINX_TEMPLATE.tmp"

    mv "$NGINX_TEMPLATE.tmp" "$NGINX_TEMPLATE"

    CLIENT="fluidd"

    if [ -f /opt/config/mod_data/web.conf ]; then
        . /opt/config/mod_data/web.conf
    fi

    sed \
        -e "s/fluidd/${CLIENT}/g" \
        -e "s/mainsail/${CLIENT}/g" \
        "$NGINX_TEMPLATE" > "$NGINX_CONF_HOST"

    if chroot "$ZMOD_ROOT" "$NGINX" \
        -t \
        -c "$NGINX_CONF_CHROOT" \
        -e /usr/data/config/mod_data/log/nginx.log
    then
        chroot "$ZMOD_ROOT" "$NGINX" \
            -s reload \
            -c "$NGINX_CONF_CHROOT" \
            2>/dev/null || true

        echo "Removed /tapo/ Nginx route"
    else
        echo "Nginx configuration test failed while removing route" >&2
        exit 1
    fi
}

case "${1:-install}" in
    install)
        install_route
        ;;
    remove)
        remove_route
        ;;
    *)
        echo "Usage: $0 {install|remove}"
        exit 1
        ;;
esac
