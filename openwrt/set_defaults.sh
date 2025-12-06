#!/bin/bash

DEFAULTS_FILE="/etc/sing-box/defaults.conf"
MANUAL_FILE="/etc/sing-box/manual.conf"

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# URL 编码函数（对整个字符串编码）
urlencode() {
    local raw="$1"
    local length="${#raw}"
    local i c
    for (( i = 0; i < length; i++ )); do
        c="${raw:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

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

    # 同时更新 manual.conf 文件中的 SUBSCRIPTION_URL 字段
    if grep -q "^SUBSCRIPTION_URL=" "$MANUAL_FILE"; then
        sed -i "s|^SUBSCRIPTION_URL=.*|SUBSCRIPTION_URL=$value|" "$MANUAL_FILE"
    else
        echo "SUBSCRIPTION_URL=$value" >> "$MANUAL_FILE"
    fi
    echo -e "${GREEN}manual.conf 文件中也已更新${NC}"
}

# ===== 自动登录并获取订阅地址 =====
auto_update_subscription() {
    USER=$(get_config USER)
    PASS=$(get_config PASS)

    if [ -z "$USER" ] || [ -z "$PASS" ]; then
        read -rp "请输入登录邮箱: " USER
        read -rp "请输入登录密码: " PASS   # 可见输入
        set_config USER "$USER"
        set_config PASS "$PASS"
    fi

    BASE_URL="https://hongxingyun.club"   # 可改为从 hongxingyun.help 获取

    echo "尝试登录..."
    LOGIN=$(curl -s -D headers.txt \
      -d "email=$USER&password=$PASS" \
      "$BASE_URL/hxapicc/passport/auth/login")

    echo "登录返回原始数据: $LOGIN"

    # 提取 Cookie
    COOKIE=$(grep -i "Set-Cookie" headers.txt | head -n1 | cut -d' ' -f2- | tr -d '\r\n')
    if [ -n "$COOKIE" ]; then
        set_config COOKIE "$COOKIE"
        echo "✅ 已保存 Cookie 到 defaults.conf"
    fi

    # 提取 Bearer Token，兼容不同字段
    AUTH=$(echo "$LOGIN" | jq -r '.data.auth_data // .data.token // .auth_data // .token')
    if [ -n "$AUTH" ] && [ "$AUTH" != "null" ]; then
        case $AUTH in
            Bearer*) ;; # 已经是完整 Bearer
            *) AUTH="Bearer $AUTH" ;;
        esac
    else
        echo "❌ 登录失败，未获取到 Bearer Token"
        return 1
    fi

    echo "✅ 登录成功，获取到认证信息: $AUTH"

# ===== 获取订阅地址 =====
    COOKIE=$(get_config COOKIE)
    SUB_INFO=$(curl -s -H "Authorization: $AUTH" -H "Cookie: $COOKIE" \
      "$BASE_URL/hxapicc/user/getSubscribe")

    echo "订阅接口返回原始数据: $SUB_INFO"

    SUB_URL=$(echo "$SUB_INFO" | jq -r '.data.subscribe_url')
    if [ -n "$SUB_URL" ] && [ "$SUB_URL" != "null" ]; then
        echo "✅ 订阅地址: $SUB_URL"
        set_config SUBSCRIPTION_URL "$SUB_URL"
    else
        echo "❌ 未能获取订阅地址，请检查接口返回"
    fi
}

# 主菜单循环
while true; do
    echo -e "${CYAN}============================${NC}"
    echo -e "${CYAN} 配置订阅菜单${NC}"
    echo -e "${CYAN}============================${NC}"
    echo -e "${GREEN}1) 修改后端地址 ${NC}(当前: $(get_config BACKEND_URL))"
    echo -e "${GREEN}2) 修改订阅地址 ${NC}(当前: $(get_config SUBSCRIPTION_URL))"
    echo -e "${GREEN}3) 修改TProxy配置文件地址 ${NC}(当前: $(get_config TPROXY_TEMPLATE_URL))"
    echo -e "${GREEN}4) 修改TUN配置文件地址 ${NC}(当前: $(get_config TUN_TEMPLATE_URL))"
    echo -e "${YELLOW}5) 查看当前配置${NC}"
    echo -e "${GREEN}6) 自动登录并更新订阅地址"
    echo -e "${GREEN}7) 修改账号和密码"
    echo -e "${RED}0) 退出${NC}"
    echo -e "${CYAN}============================${NC}"
    read -rp "请选择操作: " choice

    case $choice in
        1)
            read -rp "请输入新的后端地址: " val
            [ -n "$val" ] && set_config BACKEND_URL "$val"
            ;;
        2)
            read -rp "是否输入多个订阅地址? (y/n): " multi
            if [[ "$multi" =~ ^[Yy]$ ]]; then
                echo "请输入多个订阅地址，每行一个，输入空行结束:"
                urls=()
                while true; do
                    read -rp "> " addr
                    [ -z "$addr" ] && break
                    urls+=("$addr")
                done

                if [ ${#urls[@]} -eq 0 ]; then
                    echo -e "${RED}未输入任何地址${NC}"
                else
                    # 用 | 拼接
                    combined=$(printf "%s|" "${urls[@]}")
                    combined=${combined%|} 
                    # 对整串做一次编码（包括 | -> %7C）
                    encoded_combined=$(urlencode "$combined")
                    set_config SUBSCRIPTION_URL "$encoded_combined"
                    echo -e "${GREEN}多地址已编码并更新${NC}"
                fi
            else
                read -rp "请输入新的订阅地址(单地址不编码): " val
                if [ -n "$val" ]; then
                    set_config SUBSCRIPTION_URL "$val"
                    echo -e "${GREEN}单地址已更新（未编码）${NC}"
                fi
            fi
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
        6)
            auto_update_subscription
            ;;
        7)
            read -rp "请输入新的登录邮箱: " USER
            read -rp "请输入新的登录密码: " PASS   # 可见输入
            set_config USER "$USER"
            set_config PASS "$PASS"
            echo "账号和密码已更新"
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
