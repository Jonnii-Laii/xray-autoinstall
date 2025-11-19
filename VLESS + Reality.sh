#!/bin/bash
set -e

echo "======================================"
echo "     🚀 Xray Reality 一键安装脚本"
echo "======================================"

# ------------------ 0. 修复 DNS ------------------
echo "🔧 修复 DNS..."
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# ------------------ 1. 修复 APT 源 ------------------
echo "🔧 检查 APT 是否可用..."

if ! apt update -y >/dev/null 2>&1; then
    echo "⚠️ APT 源不可用，切换到 Debian 官方源..."

    cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian bookworm main contrib non-free
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free
deb http://deb.debian.org/debian bookworm-updates main contrib non-free
EOF

    apt update -y
fi

apt install -y curl wget unzip openssl sudo >/dev/null 2>&1

# ------------------ 2. 卸载 Debian xray-core ------------------
if dpkg -l | grep -q xray-core; then
    echo "⚠️ 检测到 Debian xray-core，正在卸载..."
    apt remove -y xray-core
fi

# 删除旧二进制
if [ -f "/usr/bin/xray" ]; then
    echo "⚠️ 删除系统旧版 /usr/bin/xray..."
    rm -f /usr/bin/xray
fi

# ------------------ 3. 安装官方 Xray ------------------
echo "🚀 安装官方 Xray..."

bash <(wget -qO- https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install -u root

XRAY_BIN="/usr/local/bin/xray"

if [ ! -f "$XRAY_BIN" ]; then
    echo "❌ Xray 安装失败，请检查网络"
    exit 1
fi

# ------------------ 4. 生成 Reality 密钥 ------------------
echo "🔑 生成 Reality 密钥..."

UUID=$($XRAY_BIN uuid)
KEY_PAIR=$($XRAY_BIN x25519)

PRIVATE_KEY=$(echo "$KEY_PAIR" | awk '/Private key/ {print $3}')
PUBLIC_KEY=$(echo "$KEY_PAIR" | awk '/Public key/ {print $3}')

# 🔄 若为空重试
if [ -z "$PUBLIC_KEY" ]; then
    echo "⚠️ PublicKey 为空，正在重试..."
    KEY_PAIR=$($XRAY_BIN x25519)
    PRIVATE_KEY=$(echo "$KEY_PAIR" | awk '/Private key/ {print $3}')
    PUBLIC_KEY=$(echo "$KEY_PAIR" | awk '/Public key/ {print $3}')
fi

if [ -z "$PUBLIC_KEY" ]; then
    echo "❌ Reality 密钥生成失败"
    exit 1
fi

SHORT_ID=$(openssl rand -hex 4)

# ------------------ 5. 配置 Xray ------------------
echo "📝 写入 Xray 配置..."

mkdir -p /usr/local/etc/xray
mkdir -p /var/log/xray

cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.bing.com:443",
          "xver": 0,
          "serverNames": ["www.bing.com"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"],
          "fingerprint": "chrome"
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
EOF

# ------------------ 6. systemd 服务 ------------------
echo "⚙️ 创建 systemd 服务..."

cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# ------------------ 7. 输出连接信息 ------------------
SERVER_IP=$(curl -s ipv4.ip.sb)

echo
echo "======================================"
echo "🎉 Reality 安装成功！"
echo "======================================"
echo "服务器 IP: $SERVER_IP"
echo "端口: 443"
echo "UUID: $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "ShortID: $SHORT_ID"
echo
echo "📌 NekoBox / Shadowrocket 链接："
echo "vless://$UUID@$SERVER_IP:443?encryption=none&security=reality&flow=xtls-rprx-vision&sni=www.bing.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Reality"
echo
echo "======================================"
