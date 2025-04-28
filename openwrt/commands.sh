#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

function view_firewall_rules() {
    echo -e "${YELLOW}查看防火墙规则...${NC}"
    nft list ruleset
    read -rp "按回车键返回二级菜单..."
}

function check_config() {
    echo -e "${YELLOW}检查配置文件...${NC}"
    bash /etc/sing-box/scripts/check_config.sh
    read -rp "按回车键返回二级菜单..."
}

function view_logs() {
    echo -e "${YELLOW}日志生成中，请等待...${NC}"
    echo -e "${RED}按 Ctrl + C 结束日志输出${NC}"
    logread -f | grep sing-box
    read -rp "按回车键返回二级菜单..."
}

function show_submenu() {
    echo -e "${CYAN}=========== 二级菜单选项 ===========${NC}"
    echo -e "${MAGENTA}1. 查看防火墙规则${NC}"
    echo -e "${MAGENTA}2. 检查配置文件${NC}"
    echo -e "${MAGENTA}3. 查看实时日志${NC}"
    echo -e "${MAGENTA}0. 返回主菜单${NC}"
    echo -e "${CYAN}===================================${NC}"
}

function handle_submenu_choice() {
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
    return 0  # 确保函数结束时返回 0
}

# 显示并处理二级菜单
menu_active=true
while $menu_active; do
    show_submenu
    handle_submenu_choice
    choice_returned=$?  # 捕获函数返回值
    if [[ $choice_returned -eq 0 ]]; then
        menu_active=false
    fi
done