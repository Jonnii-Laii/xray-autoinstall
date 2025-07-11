#!/usr/bin/env bash
# install_xray.sh - 自动安装 Xray 并配置多个端口

# ① 安装 Xray（省略实际安装逻辑，这部分保持原脚本）

# ② 生成 config.json，多端口配置
cat <<EOF > /usr/local/etc/xray/config.json
{
  "log":{
    "access":"/var/log/xray/access.log",
    "error":"/var/log/xray/error.log",
    "loglevel":"info"
  },
  "inbounds":[
EOF

# 端口列表，你可以按需调整
ports=(80 443 8080 8443 1080 8888 2053 2087 2096)
for idx in "${!ports[@]}"; do
  port=${ports[$idx]}
  cat <<EOF >> /usr/local/etc/xray/config.json
    {
      "port": $port,
      "listen": "::",
      "protocol": "vmess",
      "settings":{
        "clients":[
          {"id":"ba5c7e63-57b6-4511-a6e0-067afd3a1ccb","alterId":0}
        ]
      },
      "streamSettings":{"network":"tcp"}
    }$( [ $idx -lt $((${#ports[@]}-1)) ] && echo ",")
EOF
done

cat <<EOF >> /usr/local/etc/xray/config.json
  ],
  "outbounds":[{"protocol":"freedom","settings":{}}]
}
EOF

echo "🌐 config.json generated with ports: ${ports[*]}"

# ③ 创建 systemd service 文件（覆盖版本）
cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# ④ 重载 systemd，启动服务
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

echo "✅ Xray 已安装并启动，监听端口: ${ports[*]}"
echo "👉 查看日志: journalctl -u xray -f"
