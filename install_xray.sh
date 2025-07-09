#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
echo -e "${GREEN}>>> 开始安装 Xray 并生成配置（VMess + Clash）${NC}"

# 安装依赖
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y curl unzip uuid-runtime

# 安装 Xray
bash <(curl -fsSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# 生成随机 UUID 和设定端口
UUID=$(uuidgen)
PORT=10086

# 创建 xray config.json
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "listen": "::",
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "${UUID}", "alterId": 0 }
        ]
      },
      "streamSettings": { "network": "tcp" }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF

# 启动并开机自启
systemctl restart xray
systemctl enable xray

# 获取公网 IPv4/IPv6
IPV4=$(curl -s ipv4.ip.sb); IPV6=$(curl -s ipv6.ip.sb)

# 构造 VMess 链接
PAYLOAD=$(echo -n "{\"v\":\"2\",\"ps\":\"Xray-VPS\",\"add\":\"${IPV4}\",\"port\":\"${PORT}\",\"id\":\"${UUID}\",\"aid\":0,\"net\":\"tcp\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"tls\":\"\"}" | base64 -w 0)
VMESS4="vmess://${PAYLOAD}"

PAYLOAD6=$(echo -n "{\"v\":\"2\",\"ps\":\"Xray-VPS-IPv6\",\"add\":\"[${IPV6}]\",\"port\":\"${PORT}\",\"id\":\"${UUID}\",\"aid\":0,\"net\":\"tcp\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"tls\":\"\"}" | base64 -w 0)
VMESS6="vmess://${PAYLOAD6}"

# 构造 Clash YAML 节点
CLASH_NODE=$(cat <<YAML
proxies:
  - name: "Xray-IPv4"
    type: vmess
    server: ${IPV4}
    port: ${PORT}
    uuid: ${UUID}
    alterId: 0
    cipher: auto
    network: tcp
    tls: false

  - name: "Xray-IPv6"
    type: vmess
    server: ${IPV6}
    port: ${PORT}
    uuid: ${UUID}
    alterId: 0
    cipher: auto
    network: tcp
    tls: false
YAML
)

# 输出信息
echo -e "\n${GREEN}>>> 安装完成！配置如下：${NC}"
echo -e "UUID: ${UUID}"
echo -e "端口: ${PORT}"
echo -e "IPv4: ${IPV4}"
echo -e "IPv6: ${IPV6}"
echo -e "\nVMess 链接 IPv4:\n${VMESS4}"
echo -e "\nVMess 链接 IPv6:\n${VMESS6}"
echo -e "\nClash 节点配置（复制到 Clash 的 YAML 文件中 use/import）：\n${CLASH_NODE}"
