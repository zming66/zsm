#!/bin/bash

DEFAULTS_FILE="/etc/sing-box/defaults.conf"

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 读取配置函数
get_config() {
    local key=$1
    awk -F= -v k="$key" '$1==k {print $2}' "$DEFAULTS_FILE"
}

# 更新配置函数
set_config() {
    local key=$1
    local value=$2
    if grep -q "^$key=" "$DEFAULTS_FILE"; then
        sed -i "s|^$key=.*|$key=$value|" "$DEFAULTS_FILE"
    else
        echo "$key=$value" >> "$DEFAULTS_FILE"
    fi
    echo -e "${GREEN}已更新 $key=${value}${NC}"
}

# 主菜单循环
while true; do
    echo -e "${CYAN}============================${NC}"
    echo -e "${CYAN} 配置管理菜单${NC}"
    echo -e "${CYAN}============================${NC}"
    echo -e "${GREEN}1) 修改后端地址 ${NC}(当前: $(get_config BACKEND_URL))"
    echo -e "${GREEN}2) 修改订阅地址 ${NC}(当前: $(get_config SUBSCRIPTION_URL))"
    echo -e "${GREEN}3) 修改TProxy配置文件地址 ${NC}(当前: $(get_config TPROXY_TEMPLATE_URL))"
    echo -e "${GREEN}4) 修改TUN配置文件地址 ${NC}(当前: $(get_config TUN_TEMPLATE_URL))"
    echo -e "${YELLOW}5) 查看当前配置${NC}"
    echo -e "${RED}0) 退出${NC}"
    echo -e "${CYAN}============================${NC}"
    read -rp "请选择操作: " choice

    case $choice in
        1)
            read -rp "请输入新的后端地址: " val
            [ -n "$val" ] && set_config BACKEND_URL "$val"
            ;;
        2)
            read -rp "请输入新的订阅地址: " val
            [ -n "$val" ] && set_config SUBSCRIPTION_URL "$val"
            ;;
        3)
            read -rp "请输入新的TProxy配置文件地址: " val
            [ -n "$val" ] && set_config TPROXY_TEMPLATE_URL "$val"
            ;;
        4)
            read -rp "请输入新的TUN配置文件地址: " val
            [ -n "$val" ] && set_config TUN_TEMPLATE_URL "$val"
            ;;
        5)
            echo -e "${YELLOW}------ 当前配置 ------${NC}"
            cat "$DEFAULTS_FILE"
            echo -e "${YELLOW}----------------------${NC}"
            ;;
        0)
            echo -e "${RED}已退出${NC}"
            break
            ;;
        *)
            echo -e "${RED}无效选择，请重试${NC}"
            ;;
    esac
done
