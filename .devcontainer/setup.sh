#!/bin/bash

set -e

# ──────────────────────────────────────────────────────────────
# Fix: sudo strips env vars — try multiple sources for CODESPACE_NAME
# ──────────────────────────────────────────────────────────────
if [ -z "$CODESPACE_NAME" ]; then
  CODESPACE_NAME=$(cat /proc/1/environ 2>/dev/null | tr '\0' '\n' | grep '^CODESPACE_NAME=' | cut -d= -f2- || true)
fi
if [ -z "$CODESPACE_NAME" ]; then
  CODESPACE_NAME=$(grep '^CODESPACE_NAME=' /etc/environment 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
fi
if [ -z "$CODESPACE_NAME" ]; then
  echo "❌ ERROR: CODESPACE_NAME is not set."
  echo "   Run: export CODESPACE_NAME=<your-codespace-name> then re-run."
  exit 1
fi

# ──────────────────────────────────────────────────────────────
# TCP kernel tuning (best-effort, some may be blocked in container)
# ──────────────────────────────────────────────────────────────
sysctl -w net.core.rmem_max=16777216          2>/dev/null || true
sysctl -w net.core.wmem_max=16777216          2>/dev/null || true
sysctl -w net.core.rmem_default=1048576       2>/dev/null || true
sysctl -w net.core.wmem_default=1048576       2>/dev/null || true
sysctl -w net.ipv4.tcp_fastopen=3             2>/dev/null || true
sysctl -w net.ipv4.tcp_tw_reuse=1             2>/dev/null || true
sysctl -w net.ipv4.tcp_fin_timeout=15         2>/dev/null || true
sysctl -w net.ipv4.tcp_keepalive_time=60      2>/dev/null || true
sysctl -w net.ipv4.tcp_keepalive_intvl=10     2>/dev/null || true
sysctl -w net.ipv4.tcp_keepalive_probes=6     2>/dev/null || true
sysctl -w net.ipv4.tcp_no_metrics_save=1      2>/dev/null || true
sysctl -w net.ipv4.tcp_syn_retries=3          2>/dev/null || true
sysctl -w net.ipv4.ip_local_port_range="1024 65535" 2>/dev/null || true

SNI_HOST="${CODESPACE_NAME}-443.app.github.dev"

# Curated Cloudflare CDN IPs — test these from YOUR device in the client
# These IPs all serve app.github.dev via SNI fronting
CDN_IPS_LIST="104.21.0.1 | 172.64.0.1 | 162.159.0.1 | 188.114.96.1 | 104.22.0.1 | 190.93.240.1"

# ──────────────────────────────────────────────────────────────
# Generate a fresh UUID for this session
# ──────────────────────────────────────────────────────────────
NEW_UUID=$(cat /proc/sys/kernel/random/uuid)

# ──────────────────────────────────────────────────────────────
# Build a date-time remark (UTC)
# ──────────────────────────────────────────────────────────────
REMARK="ghtun-$(date -u +%Y%m%d-%H%M)"

# ──────────────────────────────────────────────────────────────
# Write the optimized Xray config with the new UUID
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
          "host": "${SNI_HOST}"
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
        "uplinkOnly": 1,
        "downlinkOnly": 3,
        "bufferSize": 64
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
# Build the VLESS config URL (direct domain — CDN IPs listed below)
# ──────────────────────────────────────────────────────────────
CONFIG_DIRECT="vless://${NEW_UUID}@${SNI_HOST}:443?encryption=none&security=tls&sni=${SNI_HOST}&insecure=0&allowInsecure=0&type=ws&path=%2Flive-chat#${REMARK}"

# ──────────────────────────────────────────────────────────────
# Print the config to the terminal
# ──────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            🚀  GHTUN — NEW SESSION CONFIG                   ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  UUID   : %-51s║\n" "${NEW_UUID}"
printf "║  SNI    : %-51s║\n" "${SNI_HOST}"
printf "║  Remark : %-51s║\n" "${REMARK}"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  VLESS CONFIG:                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "${CONFIG_DIRECT}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚡ برای پینگ کمتر، در کلاینت خودت host رو روی SNI بذار"
echo "   و به جای domain، یکی از این IP ها رو به عنوان آدرس امتحان کن:"
echo "   ${CDN_IPS_LIST}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ──────────────────────────────────────────────────────────────
# Start Xray
# ──────────────────────────────────────────────────────────────
echo ""
echo "▶  Starting Xray..."
exec /usr/local/bin/xray -c /etc/config.json
