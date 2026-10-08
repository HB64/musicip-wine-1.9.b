FROM debian:trixie-slim

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine \
        wine32:i386 \
        xvfb \
        ca-certificates \
        locales && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/*

ENV WINEARCH=win32
ENV WINEPREFIX=/home/wineuser/.wine32
ENV XDG_RUNTIME_DIR=/tmp/runtime-root
ENV PUID=1000
ENV PGID=1000

COPY MusicIP /tmp/payload

# Install the payload into the Wine install dir at build time. The user
# config (mmm.ini, recipes.xml, moods) is moved to /opt/defaults and replaced
# by symlinks into /config, so the server reads and writes the host copies.
RUN set -e; \
    P="/home/wineuser/.wine32/drive_c/Program Files/MusicIP"; \
    mkdir -p "$P" /opt/defaults/moods; \
    sed -i 's/\r//' /tmp/payload/entrypoint.sh; \
    mv /tmp/payload/entrypoint.sh /entrypoint.sh; \
    chmod +x /entrypoint.sh; \
    mv /tmp/payload/mmm.ini /tmp/payload/recipes.xml /opt/defaults/; \
    cp -a /tmp/payload/. "$P"/; \
    rm -rf /tmp/payload; \
    ln -s /config/mmm.ini "$P/mmm.ini"; \
    ln -s /config/recipes.xml "$P/recipes.xml"; \
    ln -s /config/moods "$P/moods"

CMD ["/entrypoint.sh"]
