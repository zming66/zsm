#!/bin/bash
# Alpine Linux (systemd) sing-box 自启动及防火墙应用脚本

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SERVICE_NAME="sing-box.service"
INIT_SCRIPT="/etc/sing-box/scripts/apply_firewall.sh"

apply_firewall() {
    MODE=$(grep -oP '(?<=^MODE=).*' /etc/sing-box/mode.conf 2>/dev/null)
    if [ "$MODE" = "TProxy" ]; then
        echo "应用 TProxy 模式防火墙规则..."
        /etc/sing-box/scripts/configure_tproxy.sh
    elif [ "$MODE" = "TUN" ]; then
        echo "应用 TUN 模式防火墙规则..."
        /etc/sing-box/scripts/configure_tun.sh
    else
        echo "⚠️ 无效模式，跳过防火墙规则应用"
    fi
}

enable_autostart() {
    echo -e "${GREEN}启用 systemd 自启动并启动服务...${NC}"
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    apply_firewall
    echo -e "${GREEN}✅ 自启动已启用并应用防火墙规则${NC}"
}

disable_autostart() {
    echo -e "${RED}禁用 systemd 自启动并停止服务...${NC}"
    systemctl stop "$SERVICE_NAME"
    systemctl disable "$SERVICE_NAME"
    echo -e "${GREEN}✅ 自启动已禁用${NC}"
}

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ 错误：需要 root 权限${NC}"
    exit 1
fi

# 循环选择操作
while true; do
    echo -e "${GREEN}请选择操作: 1=启用自启动, 2=禁用自启动${NC}"
    read -rp "(1/2): " choice
    choice=${choice:-1}

    case "$choice" in
        1)
            enable_autostart
            break
            ;;
        2)
            disable_autostart
            break
            ;;
        *)
            echo -e "${RED}输入无效，请输入 1 或 2${NC}"
            ;;
    esac
done
