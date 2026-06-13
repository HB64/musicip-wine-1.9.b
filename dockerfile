FROM debian:trixie-slim

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine \
        wine32:i386 \
        xvfb \
        ca-certificates \
        locales \
        gosu && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "ja_JP.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/*

ENV WINEARCH=win32
ENV WINEPREFIX=/home/wineuser/.wine32
ENV XDG_RUNTIME_DIR=/tmp/runtime-root
ENV PUID=1000
ENV PGID=1000

ADD MusicIP.tgz /opt
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]