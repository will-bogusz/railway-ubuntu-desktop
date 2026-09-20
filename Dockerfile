# syntax=docker/dockerfile:1
#
# Ubuntu 24.04 desktop for Railway: XFCE served by KasmVNC (browser only, no
# VNC client) behind nginx basic auth on $PORT, /home/dev on a volume, Firefox,
# a terminal and the usual CLI tools. Everything is pinned; bump the ARGs and
# rebuild. See README.md for the runtime contract.

# ubuntu:24.04 multi-arch index digest, resolved 2026-09-20 from Docker Hub.
ARG UBUNTU_DIGEST=sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3

FROM ubuntu:24.04@${UBUNTU_DIGEST} AS fetch
ARG KASMVNC_VERSION=1.5.0
ARG KASMVNC_SHA256=f599fe02e2175b9817b6165f74a5d2bebdc73118dde9181ba3410963bed7ae1e
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
WORKDIR /fetch
RUN set -eu; \
    curl -fsSLo kasmvnc.deb "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_noble_${KASMVNC_VERSION}_amd64.deb"; \
    echo "${KASMVNC_SHA256}  kasmvnc.deb" | sha256sum -c -

FROM ubuntu:24.04@${UBUNTU_DIGEST}
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color

# Firefox from Mozilla's apt repo (the Ubuntu package is a snap stub, which
# cannot run in a container). Pinned to the repo by keyring; the version is
# whatever Mozilla currently ships for the "mozilla" suite.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o /etc/apt/keyrings/packages.mozilla.org.asc \
 && echo 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' > /etc/apt/sources.list.d/mozilla.list \
 && printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      xfce4 xfce4-terminal xfce4-whiskermenu-plugin thunar mousepad ristretto \
      dbus-x11 x11-xserver-utils xdg-utils xauth \
      fonts-dejavu fonts-noto-core fonts-noto-color-emoji \
      adwaita-icon-theme greybird-gtk-theme \
      firefox \
      nginx-light openssl sudo \
      git curl wget nano vim less htop jq unzip zip tmux python3 python3-pip procps iproute2 \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default

COPY --from=fetch /fetch/kasmvnc.deb /tmp/kasmvnc.deb
RUN apt-get update && apt-get install -y --no-install-recommends /tmp/kasmvnc.deb && rm -rf /var/lib/apt/lists/* /tmp/kasmvnc.deb

# The base image ships `ubuntu` at uid 1000; free it so the volume's owner is stable.
RUN userdel -r ubuntu \
 && useradd --uid 1000 --user-group --create-home --shell /bin/bash dev \
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev && chmod 0440 /etc/sudoers.d/dev \
 && usermod -a -G ssl-cert dev 2>/dev/null || true

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY xstartup /etc/devbox/xstartup
RUN chmod 0755 /usr/local/bin/entrypoint.sh /etc/devbox/xstartup

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
