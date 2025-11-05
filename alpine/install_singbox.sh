#!/bin/ash
# Alpine Linux sing-box 安装与服务脚本（OpenRC 版本）

# 检查 root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误：需要 root 权限"
    exit 1
fi

CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 安装 sing-box 及依赖
if command -v sing-box >/dev/null 2>&1; then
    echo -e "${CYAN}sing-box 已安装，跳过安装步骤${NC}"
else
    echo "正在安装 sing-box..."
    apk update || { echo -e "${RED}apk update 失败${NC}"; exit 1; }
    apk add sing-box nftables iproute2 || { echo -e "${RED}安装失败${NC}"; exit 1; }
    echo -e "${CYAN}sing-box 安装完成${NC}"
fi

# 创建 OpenRC 服务脚本
SERVICE_FILE="/etc/init.d/sing-box"
if [ ! -f "$SERVICE_FILE" ]; then
cat << 'EOF' > "$SERVICE_FILE"
#!/sbin/openrc-run
command=/usr/bin/sing-box
command_args="run -c /etc/sing-box/config.json"
pidfile=/run/sing-box.pid
name=sing-box

depend() {
    need net
}

start() {
    ebegin "Starting $name"
    start-stop-daemon --start --quiet --pidfile $pidfile --exec $command -- $command_args
    eend $?
    
    # 读取模式并应用防火墙规则
    MODE=$(grep -oE '^MODE=.*' /etc/sing-box/mode.conf | cut -d'=' -f2)
    if [ "$MODE" = "TProxy" ]; then
        /etc/sing-box/scripts/configure_tproxy.sh
    elif [ "$MODE" = "TUN" ]; then
        /etc/sing-box/scripts/configure_tun.sh
    fi
}

stop() {
    ebegin "Stopping $name"
    start-stop-daemon --stop --quiet --pidfile $pidfile
    eend $?
}
EOF
    chmod +x "$SERVICE_FILE"
fi

# 启用并启动服务
rc-update add sing-box default
rc-service sing-box start

echo -e "${CYAN}✅ sing-box 服务已启用并启动${NC}"
