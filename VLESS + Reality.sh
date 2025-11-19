#!/bin/bash
set -e

echo "======================================"
echo "     🚀 Xray Reality 一键安装脚本"
echo "======================================"

XRAY_BIN="/usr/local/bin/xray"

#############################################
# 0. 修复 DNS
#############################################
echo "🔧 修复 DNS..."
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

#############################################
# 1. 修复 APT
#############################################
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

apt install -y curl wget unzip openssl ca-certificates sudo >/dev/null 2>&1

#############################################
# 2. 卸载 Debian 自带 xray-core
#############################################
if dpkg -l | grep -q xray-core; then
    echo "⚠️ 检测到 Debian xray-core，正在卸载..."
    apt remove -y xray-core
fi

# 删除旧二进制
if [ -f "/usr/bin/xray" ]; then
    echo "⚠️ 删除系统旧版 /usr/bin/xray..."
    rm -f /usr/bin/xray
fi

#############################################
# 3. 安装官方 Xray
#############################################
echo "🚀 安装官方 Xray..."
bash <(wget -qO- https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install -u root

if [ ! -f "$XRAY_BIN" ]; then
    echo "❌ Xray 安装失败，请检查网络"
    exit 1
fi

#############################################
# 4. 生成 Reality 密钥
#############################################
echo "🔑 生成 Reality 密钥..."
UUID=$($XRAY_BIN uuid)
KEY_PAIR=$($XRAY_BIN x25519)

PRIVATE_KEY=$(echo "$KEY_PAIR" | awk '/Private key/ {print $3}')
PUBLIC_KEY=$(echo "$KEY_PAIR" | awk '/Public key/ {print $3}')

# 🔄 若为空，执行增强修复流程
if [ -z "$PUBLIC_KEY" ]; then
    echo "⚠️ Reality 密钥为空 → 自动触发增强修复脚本"

    cat << 'EOF' > /tmp/fix-xray.sh
#!/bin/bash
set -e

echo "=== 🔥 彻底清理旧 Xray ==="
systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
rm -rf /usr/local/bin/xray
rm -rf /usr/local/etc/xray
rm -rf /etc/systemd/system/xray.service

echo "=== 🔧 修复系统环境 ==="
apt update -y
apt install -y curl wget unzip openssl ca-certificates

echo "=== 📥 下载最新版 Xray ==="
LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/download/$LATEST/Xray-linux-64.zip
unzip -o /tmp/xray.zip -d /tmp/xray
chmod +x /tmp/xray/xray
mv /tmp/xray/xray /usr/local/bin/xray

echo "=== 🔑 强制生成 Reality 密钥 ==="
/usr/local/bin/xray x25519 > /usr/local/etc/xray/reality.keys
EOF

    chmod +x /tmp/fix-xray.sh
    bash /tmp/fix-xray.sh

    # 重新读取密钥
    KEY_PAIR=$(cat /usr/local/etc/xray/reality.keys)
    PRIVATE_KEY=$(echo "$KEY_PAIR" | awk '/Private/ {print $3}')
    PUBLIC_KEY=$(echo "$KEY_PAIR" | awk '/Public/ {print $3}')
fi

if [ -z "$PUBLIC_KEY" ]; then
    echo "❌ 仍然无法生成 Reality 密钥（可能是 OpenVZ 或 CPU 不支持）"
    exit 1
fi

echo "🔐 Reality 密钥生成成功"
SHORT_ID=$(openssl rand -hex 4)

#############################################
# 5. 写入 Xray 配置
#############################################
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

#############################################
# 6. systemd
#############################################
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

#############################################
# 7. 输出信息
#############################################
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
