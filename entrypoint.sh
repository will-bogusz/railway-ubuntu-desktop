#!/bin/bash
# Boot: seed the home volume, then run Xvnc (KasmVNC, loopback, no auth of its
# own) with XFCE, and nginx on $PORT with basic auth dev:$PASSWORD in front.
# /healthz is open and only answers once Xvnc's HTTP server does. Exits when
# either process dies so Railway's restart policy acts. Never prints a secret.
set -euo pipefail

HOME_DIR=/home/dev
PORT="${PORT:-8080}"
VNC_PORT=6901
DISPLAY_NUM=1
RES="${RESOLUTION:-1440x900}"

fail() { echo "desktop: $*" >&2; sleep 3; exit 1; }
[ -n "${PASSWORD:-}" ] || fail "PASSWORD is empty. Set it in the service's Variables tab (the template generates one) and redeploy."
case "$PORT" in ''|*[!0-9]*) fail "PORT must be a number, got '$PORT'";; esac
case "$RES" in [0-9]*x[0-9]*) ;; *) fail "RESOLUTION must look like 1440x900, got '$RES'";; esac

# --- home volume -----------------------------------------------------------
mkdir -p "$HOME_DIR"
if [ ! -e "$HOME_DIR/.bashrc" ]; then
  cp -a /etc/skel/. "$HOME_DIR"/
  find "$HOME_DIR" -mindepth 1 -maxdepth 1 -not -name lost+found -exec chown -R dev:dev {} +
fi
chown dev:dev "$HOME_DIR"; chmod 0750 "$HOME_DIR"
install -d -o dev -g dev -m 0700 "$HOME_DIR/.vnc"
install -o dev -g dev -m 0755 /etc/devbox/xstartup "$HOME_DIR/.vnc/xstartup"
# Firefox in a container: no sandboxed snap, but keep its own crash reporter quiet.
install -d -o dev -g dev -m 0755 "$HOME_DIR/.config"
# KasmVNC insists on a user password file even with SecurityTypes None.
echo "$PASSWORD" | setpriv --reuid=dev --regid=dev --init-groups vncpasswd -u dev -w -f "$HOME_DIR/.kasmpasswd" >/dev/null 2>&1 || true
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"

# --- environment for the desktop session -----------------------------------
: > /run/desktop-env
while IFS= read -r -d '' entry; do
  name="${entry%%=*}"; value="${entry#*=}"
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
  case "$name" in PASSWORD|HOME|PATH|PWD|OLDPWD|SHLVL|_|USER|LOGNAME|SHELL|TERM|HOSTNAME|DEBIAN_FRONTEND|DISPLAY) continue;; esac
  printf 'export %s=%q\n' "$name" "$value" >> /run/desktop-env
done < <(env -0)
install -o root -g dev -m 0640 /run/desktop-env /etc/profile.d/10-railway-env.sh
rm -f /run/desktop-env

if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
  ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime; echo "$TZ" > /etc/timezone
fi

# --- nginx: $PORT -> Xvnc websocket/http on loopback ------------------------
printf 'dev:%s\n' "$(openssl passwd -6 "$PASSWORD")" > /run/desktop.htpasswd
chown root:www-data /run/desktop.htpasswd; chmod 0640 /run/desktop.htpasswd
cat > /run/desktop-nginx.conf <<NGX
user www-data;
worker_processes 1;
pid /run/desktop-nginx.pid;
error_log /dev/stderr warn;
events { worker_connections 256; }
http {
  access_log off;
  server_tokens off;
  map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }
  server {
    listen 0.0.0.0:${PORT} default_server;
    server_name _;
    client_max_body_size 0;
    location = /healthz {
      proxy_pass http://127.0.0.1:${VNC_PORT}/;
      proxy_http_version 1.1;
      proxy_read_timeout 5s;
    }
    location / {
      auth_basic "desktop";
      auth_basic_user_file /run/desktop.htpasswd;
      proxy_pass http://127.0.0.1:${VNC_PORT};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header Host \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_read_timeout 1d;
      proxy_send_timeout 1d;
      proxy_buffering off;
    }
  }
}
NGX
nginx -t -q -c /run/desktop-nginx.conf

# --- start -----------------------------------------------------------------
# Xvnc serves the KasmVNC web client itself on VNC_PORT (plain http, loopback);
# nginx adds auth and TLS termination is Railway's. -SecurityTypes None because
# nginx is the gate; -AlwaysShared so a second tab does not kick the first.
setpriv --reuid=dev --regid=dev --init-groups --reset-env \
  env HOME="$HOME_DIR" USER=dev DISPLAY=":${DISPLAY_NUM}" \
  /usr/bin/Xvnc ":${DISPLAY_NUM}" \
    -geometry "$RES" -depth 24 \
    -interface 127.0.0.1 -websocketPort "$VNC_PORT" -httpd /usr/share/kasmvnc/www -sslOnly 0 -DisableBasicAuth 1 \
    -SecurityTypes None -AlwaysShared -PublicIP 127.0.0.1 \
    -RectThreads 0 -FrameRate 30 \
    -http-header Cross-Origin-Embedder-Policy=require-corp \
    -http-header Cross-Origin-Opener-Policy=same-origin \
    -Log '*:stderr:10' &
XVNC_PID=$!

for i in $(seq 1 50); do [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && break; sleep 0.2; done
[ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] || fail "Xvnc did not start"

setpriv --reuid=dev --regid=dev --init-groups --reset-env \
  env HOME="$HOME_DIR" USER=dev DISPLAY=":${DISPLAY_NUM}" SHELL=/bin/bash \
      XDG_RUNTIME_DIR=/tmp/runtime-dev LANG=C.UTF-8 \
  bash -lc "mkdir -p /tmp/runtime-dev && chmod 0700 /tmp/runtime-dev && exec $HOME_DIR/.vnc/xstartup" \
  >/dev/stderr 2>&1 &
SESSION_PID=$!

nginx -c /run/desktop-nginx.conf -g 'daemon off;' &
NGINX_PID=$!

echo "desktop: ubuntu $(. /etc/os-release && echo "$VERSION_ID") | xfce | kasmvnc $(dpkg-query -W -f='${Version}' kasmvncserver) | firefox $(firefox --version 2>/dev/null | awk '{print $3}')"
[ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ] && echo "desktop: open https://${RAILWAY_PUBLIC_DOMAIN}/  (user dev)" || echo "desktop: listening on port ${PORT} (user dev)"
echo "desktop: password = PASSWORD in the service's Variables tab; /home/dev is on the volume; resolution ${RES}"

shutdown() { kill "$XVNC_PID" "$SESSION_PID" "$NGINX_PID" 2>/dev/null || true; wait; exit "${1:-0}"; }
trap 'shutdown 0' TERM INT
wait -n "$XVNC_PID" "$NGINX_PID" && status=0 || status=$?
echo "desktop: a service exited with status $status; shutting down" >&2
shutdown 1
