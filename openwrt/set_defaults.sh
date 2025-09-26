#!/bin/bash

DEFAULTS_FILE="/etc/sing-box/defaults.conf"

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
}

# 主菜单循环
while true; do
    echo "============================"
    echo " 配置管理菜单"
    echo "============================"
    echo "1) 修改后端地址 (当前: $(get_config BACKEND_URL))"
    echo "2) 修改订阅地址 (当前: $(get_config SUBSCRIPTION_URL))"
    echo "3) 修改TProxy配置文件地址 (当前: $(get_config TPROXY_TEMPLATE_URL))"
    echo "4) 修改TUN配置文件地址 (当前: $(get_config TUN_TEMPLATE_URL))"
    echo "5) 查看当前配置"
    echo "0) 退出"
    echo "============================"
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
            echo "------ 当前配置 ------"
            cat "$DEFAULTS_FILE"
            echo "----------------------"
            ;;
        0)
            echo "已退出"
            break
            ;;
        *)
            echo "无效选择，请重试"
            ;;
    esac
done
