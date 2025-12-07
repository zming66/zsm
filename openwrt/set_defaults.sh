#!/bin/bash

DEFAULTS_FILE="/etc/sing-box/defaults.conf"
MANUAL_FILE="/etc/sing-box/manual.conf"
HEADERS_FILE="/etc/sing-box/headers.txt"

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 错误处理函数
error_exit() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

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
    if [ "$key" == "SUBSCRIPTION_URL" ]; then
        if grep -q "^SUBSCRIPTION_URL=" "$MANUAL_FILE"; then
            sed -i "s|^SUBSCRIPTION_URL=.*|SUBSCRIPTION_URL=$value|" "$MANUAL_FILE"
        else
            echo "SUBSCRIPTION_URL=$value" >> "$MANUAL_FILE"
        fi
        echo -e "${GREEN}manual.conf 文件中也已更新${NC}"
    fi
}

# 自动选择最快节点
get_best_node() {
    NAV_URL="https://hongxingyun.help"
    echo -e "${CYAN}正在获取登录节点...${NC}"

    # 抓取导航页内容并提取所有候选节点
    NODES=$(curl -s "$NAV_URL" | grep -oE "hongxingyun\.[a-z]+" | sort -u)

    BEST=""
    BEST_LATENCY=999999

    for node in $NODES; do
        # 测试连接延迟（毫秒）
        LATENCY=$(curl -o /dev/null -s -w "%{time_connect}" "https://$node")
        LATENCY_MS=$(awk "BEGIN {print $LATENCY * 1000}")
        echo "$node 延迟: ${LATENCY_MS} ms"

        # 选择最小延迟的节点
        if [ "$LATENCY_MS" -lt "$BEST_LATENCY" ]; then
            BEST=$node
            BEST_LATENCY=$LATENCY_MS
        fi
    done

    [ -z "$BEST" ] && error_exit "未找到可用节点"

    echo -e "${GREEN}✅ 选择最快节点: https://$BEST${NC}"
    echo "https://$BEST"
}


# ===== 自动登录并获取订阅地址 =====
auto_update_subscription() {
    USER=$(get_config USER)
    PASS=$(get_config PASS)

    # 如果没有账号密码，提示输入
    if [ -z "$USER" ] || [ -z "$PASS" ]; then
        read -rp "请输入登录邮箱: " USER
        read -rsp "请输入登录密码: " PASS
        echo
        set_config USER "$USER"
        set_config PASS "$PASS"
    fi

    BASE_URL=$(get_best_node)

    # 确保 headers 文件存在
    touch "$HEADERS_FILE"

    echo "尝试登录..."
    LOGIN=$(curl -s -D "$HEADERS_FILE" \
      -d "email=$USER&password=$PASS" \
      -o /dev/null -w "%{http_code}" \
      "$BASE_URL/hxapicc/passport/auth/login")

    # 判断 HTTP 状态码
    if [ "$LOGIN" != "200" ]; then
        echo -e "${RED}❌ 登录失败，HTTP 状态码: ${LOGIN:-未返回}${NC}"
        return 1
    fi

    # 提取 Cookie
    COOKIE=$(grep -i "Set-Cookie" "$HEADERS_FILE" | head -n1 | sed -E 's/Set-Cookie: ([^;]+);.*/\1/')
    if [ -z "$COOKIE" ]; then
        echo -e "${RED}❌ 未能提取 Cookie${NC}"
        return 1
    fi
    set_config COOKIE "$COOKIE"
    echo "✅ 已保存 Cookie 到 defaults.conf"

    # 获取 Bearer Token
    AUTH=$(curl -s -H "Cookie: $COOKIE" \
      -d "email=$USER&password=$PASS" \
      "$BASE_URL/hxapicc/passport/auth/login" | jq -r '.data.auth_data // .data.token // .auth_data // .token // .authorization')

    if [ -z "$AUTH" ] || [ "$AUTH" == "null" ]; then
        echo -e "${RED}❌ 登录失败，未获取到 Bearer Token${NC}"
        return 1
    fi

    [[ "$AUTH" != Bearer* ]] && AUTH="Bearer $AUTH"
    echo -e "✅ 登录成功，获取到认证信息: $AUTH"

    # ===== 获取订阅地址 =====
    SUB_INFO=$(curl -s -H "Authorization: $AUTH" -H "Cookie: $COOKIE" \
      "$BASE_URL/hxapicc/user/getSubscribe")

    SUB_URL=$(echo "$SUB_INFO" | jq -r '.data.subscribe_url')
    if [ -n "$SUB_URL" ] && [ "$SUB_URL" != "null" ]; then
        echo "✅ 订阅地址: $SUB_URL"
        set_config SUBSCRIPTION_URL "$SUB_URL"
    else
        echo -e "${RED}❌ 未能获取订阅地址，请检查接口返回${NC}"
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
    echo -e "${GREEN}5) 自动登录并更新订阅地址"
    echo -e "${GREEN}6) 修改账号和密码"
    echo -e "${YELLOW}7) 查看当前配置${NC}"
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
                    combined=$(printf "%s|" "${urls[@]}")
                    combined=${combined%|}
                    encoded_combined=$(urlencode "$combined")
                    set_config SUBSCRIPTION_URL "$encoded_combined"
                    echo -e "${GREEN}多地址已编码并更新${NC}"
                fi
            else
                read -rp "请输入新的订阅地址(单地址不编码): " val
                [ -n "$val" ] && set_config SUBSCRIPTION_URL "$val"
                echo -e "${GREEN}单地址已更新（未编码）${NC}"
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
            auto_update_subscription
            ;;
        6)
            read -rp "请输入新的登录邮箱: " USER
            read -rsp "请输入新的登录密码: " PASS
            echo
            set_config USER "$USER"
            set_config PASS "$PASS"
            echo "账号和密码已更新"
            ;;
        7)
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
