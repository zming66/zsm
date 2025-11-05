#!/bin/ash
# ==============================================
# 功能: sing-box 二级管理菜单
# 支持系统: Alpine / OpenWRT / Debian / Ubuntu
# ==============================================

# 定义颜色
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 查看防火墙规则
view_firewall_rules() {
    echo -e "${YELLOW}查看防火墙规则...${NC}"
    if command -v nft >/dev/null 2>&1; then
        nft list ruleset
    elif command -v iptables >/dev/null 2>&1; then
        iptables -L -n -v
    else
        echo -e "${RED}未检测到 nftables 或 iptables！${NC}"
    fi
    read -rp "按回车键返回二级菜单..."
}

# 检查配置文件
check_config() {
    echo -e "${YELLOW}检查配置文件...${NC}"
    if [ -x /etc/sing-box/scripts/check_config.sh ]; then
        bash /etc/sing-box/scripts/check_config.sh
    else
        echo -e "${RED}未找到 /etc/sing-box/scripts/check_config.sh${NC}"
    fi
    read -rp "按回车键返回二级菜单..."
}

# 查看实时日志
view_logs() {
    echo -e "${YELLOW}查看 sing-box 实时日志...${NC}"
    echo -e "${RED}按 Ctrl + C 结束日志输出${NC}"

    # OpenWRT 使用 logread，Alpine 使用 rc-service / tail 日志
    if command -v logread >/dev/null 2>&1; then
        logread -f | grep sing-box
    elif [ -f /var/log/messages ]; then
        tail -f /var/log/messages | grep sing-box
    elif [ -f /var/log/syslog ]; then
        tail -f /var/log/syslog | grep sing-box
    else
        echo -e "${RED}未找到系统日志文件或 logread 命令。${NC}"
    fi
    read -rp "按回车键返回二级菜单..."
}

# 显示二级菜单
show_submenu() {
    echo -e "${CYAN}=========== 二级菜单选项 ===========${NC}"
    echo -e "${MAGENTA}1. 查看防火墙规则${NC}"
    echo -e "${MAGENTA}2. 检查配置文件${NC}"
    echo -e "${MAGENTA}3. 查看实时日志${NC}"
    echo -e "${MAGENTA}0. 返回主菜单${NC}"
    echo -e "${CYAN}===================================${NC}"
}

# 处理选择
handle_submenu_choice() {
    while true; do
        read -rp "请选择操作: " choice
        case $choice in
            1) view_firewall_rules ;;
            2) check_config ;;
            3) view_logs ;;
            0) return 0 ;;
            *) echo -e "${RED}无效的选择${NC}" ;;
        esac
        show_submenu
    done
    return 0
}

# 主循环
menu_active=true
while $menu_active; do
    show_submenu
    handle_submenu_choice
    choice_returned=$?
    if [ "$choice_returned" -eq 0 ]; then
        menu_active=false
    fi
done
