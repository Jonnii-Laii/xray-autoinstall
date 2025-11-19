#!/bin/bash
set -e

echo "=== 🔧 修复 APT / DNS / 网络 环境中... ==="

# ---------- 0. 修复 DNS ----------
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# ---------- 1. 测试 apt update ----------
if ! apt update -y >/dev/null 2>&1; then
    echo "⚠️ APT 源不可用，切换到官方 Debian 源..."

    cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian bookworm main contrib non-free
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free
deb http://deb.debian.org/debian bookworm-updates main contrib non-free
EOF

    apt update -y
fi

# ---------- 2. 安装依赖 ----------
apt install -y curl wget unzip openssl

echo "=== 🚀 开始安装 Xray ==="

# ---------- 3. 安装 Xray ----------
bash <(wget -qO- https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install -u root

# ---------- 确保 Xray 命令可用 ----------
XRAY_BIN="/usr/local/bin/xray"
if [ ! -f "$XRAY_BIN" ]; then
    echo "❌ Xray 安装失败，程序退出"
    exit 1
fi

# ---------- 4. 生成 UUID ----------
UUID=$($XRAY_BIN uuid)

# ---------- 5. 生成 Reality 密钥对 ----------
echo "=== 🔑 生成 Reality 密钥 ==="

KEY_PAIR=$($XRAY_BIN x25519)

PRIVATE_KEY=$(echo "$KEY_PAIR" | awk '/Private key/ {print $3}')
PUBLIC_KEY=$(echo "$KEY_PAIR" | awk '/Public key/ {print $3}')

# 🔄 如果为空 → 自动重试一次
if [ -z "$PUBLIC_KEY" ]; then
    echo "⚠️ PublicKey 为空，正在重试生成密钥..."
    KEY_PAIR=$($XRAY_BIN x25519)
    PRIVATE_KEY=$(echo "$KEY_PAIR" | awk '/Private key/ {print $3}')
    PUBLIC_KEY=$(echo "$KEY_PAIR" | awk '/Public key/ {print $3}')
fi

# 🔴 如果仍为空 → 报错退出
if [ -z "$PUBLIC_KEY" ]; then
    echo "❌ 密钥生成失败，请检查 Xray 是否正常安装"
    exit 1
fi

SHORT_ID=$(openssl rand -hex 4)

# ---------- 6. 创建目录 ----------
mkdir -p /usr/local/etc/xray
mkdir -p /var/log/xray

# ---------- 7. 写入配置文件 ----------
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
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# ---------- 8. systemd 服务 ----------
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

# ---------- 9. 启动服务 ----------
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# ---------- 10. 输出信息 ----------
SERVER_IP=$(curl -s ipv4.ip.sb)

echo -e "\n===== 🎉 Reality 配置信息生成成功 ====="
echo "服务器IP: $SERVER_IP"
echo "UUID: $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "ShortID: $SHORT_ID"
echo "伪装域名: www.bing.com"
echo "端口: 443"
echo -e "\n📌 NekoBox 连接格式："
echo "vless://$UUID@$SERVER_IP:443?encryption=none&security=reality&flow=xtls-rprx-vision&sni=www.bing.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Reality"
echo -e "========================================\n"
