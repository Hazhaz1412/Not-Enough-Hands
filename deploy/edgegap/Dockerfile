FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libasound2 \
        libfontconfig1 \
        libgl1 \
        libx11-6 \
        libxcursor1 \
        libxi6 \
        libxinerama1 \
        libxrandr2 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --home-dir /app --shell /usr/sbin/nologin game

WORKDIR /app
COPY --chown=10001:10001 build/server/ /app/
# HOME is /app, so uid 10001 must own the directory itself. WORKDIR creates it as
# root and COPY --chown only touches the copied entries, so without this chown the
# server cannot create its user data dir and dies with SIGSEGV on startup.
RUN chmod +x /app/not-enough-hands-server.x86_64 \
    && chown 10001:10001 /app

USER 10001:10001
EXPOSE 7777/udp

ENTRYPOINT ["/app/not-enough-hands-server.x86_64", "--headless", "--", "--server"]
CMD ["--port=7777"]
