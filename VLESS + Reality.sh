#!/bin/bash
set -e

# ====== 1. 安装 Xray ======
bash <(wget -qO- https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install -u root

# ====== 2. 生成 UUID 和 Reality 密钥 ======
UUID=$(xray uuid)
KEY_PAIR=$(xray x25519)
PRIVATE_KEY=$(echo "$KEY_PAIR" | grep 'Private key' | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEY_PAIR" | grep 'Public key' | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

# ====== 3. 创建配置目录 ======
mkdir -p /usr/local/etc/xray
mkdir -p /var/log/xray

# ====== 4. 写入 Reality 配置 ======
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

# ====== 5. 创建 systemd 服务 ======
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
echo "服务器IP: $(curl -s ipv4.ip.sb)"
echo "UUID: $UUID"
echo "PublicKey: $PUBLIC_KEY"
echo "ShortID: $SHORT_ID"
echo "伪装域名: www.bing.com"
echo "端口: 443"
echo -e "客户端示例：VLESS://$UUID@$(curl -s ipv4.ip.sb):443?encryption=none&security=reality&sni=www.bing.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&flow=xtls-rprx-vision#Reality\n"
