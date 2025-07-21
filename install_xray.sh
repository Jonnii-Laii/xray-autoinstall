#!/bin/bash
set -e

# 定义变量
IP="2605:e440:4::53"
PORT="443"
UUID="d33513b8-1d5c-4aee-8934-9d074867af74"

# 安装 Xray 最新版本
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

# 创建配置目录
mkdir -p /usr/local/etc/xray

# 写入配置文件（无 TLS，指定 UUID、IP 和端口）
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $PORT,
      "listen": "::",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
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


# 应用内核参数
sysctl -p

# 创建 systemd 服务文件
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

# 启动并设置开机自启
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 显示运行状态
systemctl status xray --no-pager

# ===== 生成 Shadowrocket vmess 导入链接 =====
read -r -d '' vmess_json <<EOF
{
  "v": "2",
  "ps": "Xray VMess",
  "add": "$IP",
  "port": "$PORT",
  "id": "$UUID",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": ""
}
EOF

vmess_link="vmess://$(echo -n "$vmess_json" | base64 | tr -d '\n')"

echo
echo "==== Shadowrocket VMess 导入链接 ===="
echo "$vmess_link"
echo "==================================="
