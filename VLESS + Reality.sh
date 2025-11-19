#!/bin/bash
set -e

echo "======================================"
echo "     🚀 Xray Reality 一键安装脚本"
echo "======================================"

# ====== 1. 安装官方 Xray ======
echo "🚀 安装官方 Xray..."
bash <(wget -qO- https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install -u root

# ====== 2. 生成或读取 Reality 密钥 ======
KEY_FILE="/root/reality.keys"

if [ -f "$KEY_FILE" ]; then
    echo "🔑 读取已存在的 Reality 密钥..."
    source "$KEY_FILE"
else
    echo "🔑 生成 Reality 密钥..."
    # 尝试非交互方式生成
    KEY_PAIR=$(xray x25519 --yes 2>/dev/null || echo | xray x25519)
    PRIVATE_KEY=$(echo "$KEY_PAIR" | grep -Po '(?<=PrivateKey: ).*')
    PUBLIC_KEY=$(echo "$KEY_PAIR" | grep -Po '(?<=PublicKey: ).*')

    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        echo "❌ Reality 密钥生成失败，请手动检查 xray x25519 输出"
        exit 1
    fi

    echo "PRIVATE_KEY=$PRIVATE_KEY" > "$KEY_FILE"
    echo "PUBLIC_KEY=$PUBLIC_KEY" >> "$KEY_FILE"
    echo "✅ Reality 密钥已保存到 $KEY_FILE"
fi

# 生成 UUID 和短 ID
UUID=$(xray uuid)
SHORT_ID=$(openssl rand -hex 4)

# ====== 3. 创建配置目录 ======
mkdir -p /usr/local/etc/xray
mkdir -p /var/log/xray

# ====== 4. 写入 Reality 配置 ======
SERVER_IP=$(curl -s ipv4.ip.sb)
cat > /usr/local/etc/xray/config.json << EOF
{
  # vless://$UUID@$SERVER_IP:443?encryption=none&security=reality&flow=xtls-rprx-vision&sni=www.bing.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Reality_$SHORT_ID
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

# ====== 5. 创建 systemd 服务 ======
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

# ====== 6. 启动并开机自启 ======
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# ====== 7. 输出连接信息 ======
echo -e "\n===== Reality 配置信息 ====="
echo "服务器IP: $SERVER_IP"
echo "UUID: $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "ShortID: $SHORT_ID"
echo "伪装域名: www.bing.com"
echo "端口: 443"
echo -e "客户端示例（NekoBox 格式）：\n\
vless://$UUID@$SERVER_IP:443?encryption=none&security=reality&flow=xtls-rprx-vision&sni=www.bing.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Reality\n"

echo "✅ Xray Reality 安装完成"
