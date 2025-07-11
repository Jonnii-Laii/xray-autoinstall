#!/usr/bin/env bash

# 安装 Xray Core
mkdir -p /usr/local/etc/xray /var/log/xray
curl -Lo /usr/local/bin/xray https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip -o Xray-linux-64.zip xray -d /usr/local/bin/
chmod +x /usr/local/bin/xray

# 配置多个监听端口
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    $(for port in 80 443 8080 8443 1080 8888 2053 2087 2096; do
      cat <<EOL
    {
      "port": $port,
      "listen": "::",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "ba5c7e63-57b6-4511-a6e0-067afd3a1ccb",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    }$( [[ $port != 2096 ]] && echo "," )
EOL
    done)
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 配置 systemd 服务（以 root 运行）
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

echo "✅ Xray 安装完成，已以 root 权限运行并监听多个端口。"
