#!/bin/bash

set -e

# ──────────────────────────────────────────────────────────────
# Fix: sudo strips env vars — try multiple sources for CODESPACE_NAME
# ──────────────────────────────────────────────────────────────
if [ -z "$CODESPACE_NAME" ]; then
  # Try to read from the parent process environment
  CODESPACE_NAME=$(cat /proc/1/environ 2>/dev/null | tr '\0' '\n' | grep '^CODESPACE_NAME=' | cut -d= -f2- || true)
fi

if [ -z "$CODESPACE_NAME" ]; then
  # Fallback: read from /etc/environment (sometimes set by Codespaces init)
  CODESPACE_NAME=$(grep '^CODESPACE_NAME=' /etc/environment 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
fi

if [ -z "$CODESPACE_NAME" ]; then
  echo "❌ ERROR: CODESPACE_NAME is not set. Cannot determine SNI hostname."
  echo "   Try running:  export CODESPACE_NAME=<your-codespace-name>  then re-run this script."
  exit 1
fi

# ──────────────────────────────────────────────────────────────
# Generate a fresh UUID for this session
# ──────────────────────────────────────────────────────────────
NEW_UUID=$(cat /proc/sys/kernel/random/uuid)

# ──────────────────────────────────────────────────────────────
# Build a date-time remark (UTC)
# ──────────────────────────────────────────────────────────────
REMARK="ghtun-$(date -u +%Y%m%d-%H%M)"

SNI="${CODESPACE_NAME}-443.app.github.dev"

# ──────────────────────────────────────────────────────────────
# Write the fresh Xray config with the new UUID
# No geoip.dat / geosite.dat rules — not available in this image
# ──────────────────────────────────────────────────────────────
cat > /etc/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${NEW_UUID}",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/live-chat",
          "headers": {}
        }
      },
      "sniffing": {
        "enabled": false
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "tag": "direct"
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "bufferSize": 512
      }
    }
  }
}
EOF

# ──────────────────────────────────────────────────────────────
# Make port 443 public via GitHub CLI
# ──────────────────────────────────────────────────────────────
echo "🔓 Setting port 443 to public..."
gh codespace ports visibility 443:public -c "$CODESPACE_NAME" 2>/dev/null || true

# ──────────────────────────────────────────────────────────────
# Build the VLESS config URL
# ──────────────────────────────────────────────────────────────
CONFIG_URL="vless://${NEW_UUID}@${SNI}:443?encryption=none&security=tls&sni=${SNI}&insecure=0&allowInsecure=0&type=ws&path=%2Flive-chat#${REMARK}"

# ──────────────────────────────────────────────────────────────
# Print the config to the terminal
# ──────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            🚀  GHTUN — NEW SESSION CONFIG                   ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  UUID   : %-51s║\n" "${NEW_UUID}"
printf "║  SNI    : %-51s║\n" "${SNI}"
printf "║  Remark : %-51s║\n" "${REMARK}"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  VLESS CONFIG (copy & paste into your client):              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "${CONFIG_URL}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ──────────────────────────────────────────────────────────────
# Start Xray
# ──────────────────────────────────────────────────────────────
echo "▶  Starting Xray..."
exec /usr/local/bin/xray -c /etc/config.json
