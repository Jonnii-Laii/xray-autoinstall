#!/bin/bash
set -e

# 定义变量
IP="2605:e440:4::53"
PORT="443"
UUID="bf6a59a0-7f9c-4465-a03f-b98c8fb41ae8"

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

# 系统内核参数优化
cat >> /etc/sysctl.conf << EOF

# 优化网络性能（通用优化）
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
fs.file-max = 65536
fs.nr_open = 65536
net.netfilter.nf_conntrack_max = 16384

net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000

# IPv6 优化参数
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.neigh.default.gc_thresh1 = 1024
net.ipv6.neigh.default.gc_thresh2 = 2048
net.ipv6.neigh.default.gc_thresh3 = 4096
net.ipv6.icmp.ratelimit = 1000
net.ipv6.route.flush = 1
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
