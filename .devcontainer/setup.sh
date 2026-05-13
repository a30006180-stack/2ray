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

# ──────────────────────────────────────────────────────────────
# Scan CDN IPs to find the lowest-latency one from THIS server
# (Cloudflare anycast IPs that serve app.github.dev via SNI fronting)
# ──────────────────────────────────────────────────────────────
SNI_HOST="${CODESPACE_NAME}-443.app.github.dev"

# Known Cloudflare anycast IP ranges — pick best one via ping
CDN_IPS=(
  "104.21.0.1"
  "104.21.64.1"
  "104.21.96.1"
  "104.22.0.1"
  "104.22.32.1"
  "172.64.0.1"
  "172.64.32.1"
  "172.64.64.1"
  "172.64.128.1"
  "172.64.160.1"
  "172.64.192.1"
  "172.65.0.1"
  "172.65.32.1"
  "162.159.0.1"
  "162.159.128.1"
  "162.159.135.1"
  "162.159.200.1"
  "162.159.36.1"
  "108.162.192.1"
  "108.162.196.1"
  "190.93.240.1"
  "190.93.244.1"
  "188.114.96.1"
  "188.114.97.1"
  "188.114.98.1"
  "188.114.99.1"
)

echo "🔍 Scanning CDN IPs for lowest latency..."

BEST_IP=""
BEST_PING=9999

for IP in "${CDN_IPS[@]}"; do
  # ping with 2 packets, 1s timeout, get avg
  PING_MS=$(ping -c 2 -W 1 -q "$IP" 2>/dev/null | awk -F'/' 'END{print int($5)}' || echo "9999")
  if [ "$PING_MS" -lt "$BEST_PING" ] 2>/dev/null; then
    BEST_PING=$PING_MS
    BEST_IP=$IP
  fi
done

# Fallback if scan fails
if [ -z "$BEST_IP" ] || [ "$BEST_PING" -ge 9999 ]; then
  BEST_IP="204.12.196.34"
  BEST_PING="N/A"
fi

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
          "headers": {
            "Host": "${SNI_HOST}"
          }
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
# Build the VLESS config URLs (best CDN IP + direct domain)
# ──────────────────────────────────────────────────────────────
CONFIG_CDN="vless://${NEW_UUID}@${BEST_IP}:443?encryption=none&security=tls&sni=${SNI_HOST}&insecure=0&allowInsecure=0&type=ws&path=%2Flive-chat&host=${SNI_HOST}#${REMARK}-cdn"
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
printf "║  Best IP: %-40s ping=%s ms ║\n" "${BEST_IP}" "${BEST_PING}"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  ① RECOMMENDED — CDN IP (usually lower ping):               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "${CONFIG_CDN}"
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ② FALLBACK — Direct domain:                                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "${CONFIG_DIRECT}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚡ Tip: Try BOTH configs in your client — use whichever pings lower"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ──────────────────────────────────────────────────────────────
# Start Xray
# ──────────────────────────────────────────────────────────────
echo ""
echo "▶  Starting Xray..."
exec /usr/local/bin/xray -c /etc/config.json
