#!/bin/bash
set -euo pipefail

# ==========================
# 可调参数（按需修改）
# ==========================
REALITY_DEST_DOMAIN="www.bing.com"             # 伪装/指向域名
REALITY_DEST_PORT="443"                        # 目标站端口
REALITY_SERVER_NAMES='["www.bing.com"]'        # ServerName 列表（JSON 数组）
XRAY_PORT="443"                                # 本地监听端口
GRPC_SERVICE_NAME="grpcReality"                # gRPC serviceName
XRAY_USER="root"                               # 以 root 运行
LOGLEVEL="warning"                             # 日志等级

# ==========================
# 1) 安装 Xray
# ==========================
bash <(wget -qO- https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install -u "${XRAY_USER}"

# ==========================
# 2) 生成 UUID & x25519 & shortId
# ==========================
UUID=$(/usr/local/bin/xray uuid)
KEY_PAIR=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEY_PAIR" | awk '/Private key/{print $3}')
PUBLIC_KEY=$(echo  "$KEY_PAIR" | awk '/Public key/{print $3}')
SHORT_ID=$(openssl rand -hex 8)   # 8字节更通用

# ==========================
# 3) 创建目录
# ==========================
mkdir -p /usr/local/etc/xray
mkdir -p /var/log/xray

# ==========================
# 4) 写入 Xray 配置（Reality + gRPC + sockopt）
# ==========================
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "${LOGLEVEL}",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-reality-grpc",
      "listen": "[::]",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST_DOMAIN}:${REALITY_DEST_PORT}",
          "xver": 0,
          "serverNames": ${REALITY_SERVER_NAMES},
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"],
          "fingerprint": "chrome"
        },
        "grpcSettings": {
          "serviceName": "${GRPC_SERVICE_NAME}",
          "multiMode": true
        },
        "sockopt": {
          "tcpFastOpen": true,
          "tcpNoDelay": true
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["tls","http"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true,
          "tcpNoDelay": true
        }
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF

# ==========================
# 5) systemd 服务
# ==========================
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service (Reality+gRPC)
After=network.target nss-lookup.target

[Service]
User=${XRAY_USER}
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# ==========================
# 6) 开启内核网络优化（BBR / fq / fastopen）
# 6) 开启内核网络优化（安全兼容版）
# ========================== 
echo "正在应用内核优化..."

# 只设置现代内核支持的参数
cat >> /etc/sysctl.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=1200
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
EOF

# 应用更改
sysctl -p >/dev/null 2>&1 || true


# ==========================
# 7) 开放防火墙（如有 ufw/iptables 自行调整）
# ==========================
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${XRAY_PORT}/tcp || true
fi

# ==========================
# 8) 启动并自启
# ==========================
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# ==========================
# 9) 输出连接信息
# ==========================
SERVER_IPv4=$(curl -4s https://ipv4.ip.sb || true)
SERVER_IPv6=$(curl -6s https://ipv6.ip.sb || true)

echo -e "\n========= Reality + gRPC 配置 ========="
echo "IPv4: ${SERVER_IPv4}"
echo "IPv6: ${SERVER_IPv6}"
echo "端口: ${XRAY_PORT}"
echo "UUID: ${UUID}"
echo "PublicKey: ${PUBLIC_KEY}"
echo "ShortID: ${SHORT_ID}"
echo "SNI: ${REALITY_DEST_DOMAIN}"
echo "gRPC serviceName: ${GRPC_SERVICE_NAME}"

if [[ -n "${SERVER_IPv4}" ]]; then
  echo -e "\n客户端示例（IPv4）:"
  echo "vless://${UUID}@${SERVER_IPv4}:${XRAY_PORT}?type=grpc&serviceName=${GRPC_SERVICE_NAME}&mode=gun&security=reality&sni=${REALITY_DEST_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&encryption=none#Reality-gRPC-IPv4"
fi
if [[ -n "${SERVER_IPv6}" ]]; then
  echo -e "\n客户端示例（IPv6）:"
  echo "vless://${UUID}@[${SERVER_IPv6}]:${XRAY_PORT}?type=grpc&serviceName=${GRPC_SERVICE_NAME}&mode=gun&security=reality&sni=${REALITY_DEST_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&encryption=none#Reality-gRPC-IPv6"
fi
echo -e "=======================================\n"
