FROM debian:bookworm-slim

COPY install.sh /app/install.sh
COPY setup.sh   /app/setup.sh
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash git curl wget unzip tzdata openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN chmod +x /app/install.sh && /app/install.sh
RUN chmod +x /app/setup.sh

# Placeholder config — the real UUID is injected at container start by setup.sh
COPY config.json /etc/config.json

# Print the live config link (UUID + remark) every time a shell opens
RUN echo 'cat /run/ghtun-config.txt 2>/dev/null || true' >> /etc/bash.bashrc

CMD ["/app/setup.sh"]