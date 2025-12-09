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

# 依赖检查
for cmd in curl jq awk sed; do
    command -v $cmd >/dev/null 2>&1 || error_exit "缺少依赖: $cmd"
done

# URL 编码函数
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

# 更新配置函数（避免重复键）
set_config() {
    local key=$1
    local value=$2
    tmp=$(mktemp)
    awk -F= -v k="$key" -v v="$value" '
        BEGIN{found=0}
        $1==k {print k"="v; found=1; next}
        {print}
        END{if(!found) print k"="v}
    ' "$DEFAULTS_FILE" > "$tmp" && mv "$tmp" "$DEFAULTS_FILE"
    echo -e "${GREEN}已更新 $key=${value}${NC}"

    # 同时更新 manual.conf 文件中的 SUBSCRIPTION_URL 字段
    if [ "$key" == "SUBSCRIPTION_URL" ]; then
        tmp2=$(mktemp)
        awk -F= -v k="SUBSCRIPTION_URL" -v v="$value" '
            BEGIN{found=0}
            $1==k {print k"="v; found=1; next}
            {print}
            END{if(!found) print k"="v}
        ' "$MANUAL_FILE" > "$tmp2" && mv "$tmp2" "$MANUAL_FILE"
        echo -e "${GREEN}manual.conf 文件中也已更新${NC}"
    fi
}

# 自动选择最快节点并返回登录入口
get_best_node() {
    NAV_URL="https://hongxingyun.help"
    echo -e "${CYAN}正在解析导航页...${NC}"

    LINKS=$(curl -s "$NAV_URL" | grep -Eo 'https://hongxingyun[^" ]+' | sort -u)
    BEST=""
    BEST_LATENCY=999999

    for link in $LINKS; do
        LATENCY=$(curl -o /dev/null -s -w "%{time_starttransfer}" "$link")
        if [ -z "$LATENCY" ]; then
            echo "$link 不可达"
            continue
        fi
        LATENCY_MS=$(awk "BEGIN {print int($LATENCY * 1000)}")
        echo "$link 延迟: ${LATENCY_MS} ms"

        if [ "$LATENCY_MS" -lt "$BEST_LATENCY" ]; then
            BEST=$link
            BEST_LATENCY=$LATENCY_MS
        fi
    done

    if [ -z "$BEST" ]; then
        echo -e "${YELLOW}未找到可用入口，尝试使用上次保存的 BACKEND_URL${NC}"
        BEST=$(get_config JC_URL)
        [ -z "$BEST" ] && error_exit "没有可用入口，也没有保存的后端地址"
    fi

    echo -e "${GREEN}✅ 选择入口: $BEST (延迟 ${BEST_LATENCY} ms)${NC}"

    # 写入 /etc/sing-box/defaults.conf 中 JC_URL
    DEFAULTS_FILE="/etc/sing-box/defaults.conf"
    tmp=$(mktemp)
    awk -F= -v k="JC_URL" -v v="$BEST" '
        BEGIN{found=0}
        $1==k {print k"="v; found=1; next}
        {print}
        END{if(!found) print k"="v}
    ' "$DEFAULTS_FILE" > "$tmp" && mv "$tmp" "$DEFAULTS_FILE"

    echo -e "${GREEN}已更新 JC_URL=$BEST 到 $DEFAULTS_FILE${NC}"

    echo "$BEST"
}
# ==# ===== 自动登录并获取订阅地址 =====
auto_update_subscription() {
    USER=$(get_config USER)
    PASS=$(get_config PASS)

    if [ -z "$USER" ] || [ -z "$PASS" ]; then
        read -rp "请输入登录邮箱: " USER
        read -rp "请输入登录密码: " PASS
        set_config USER "$USER"
        set_config PASS "$PASS"
    fi

    BASE_URL=$(get_config JC_URL)

    echo "尝试登录..."
    LOGIN=$(curl -s -D headers.txt \
      -d "email=$USER&password=$PASS" \
      "$BASE_URL/hxapicc/passport/auth/login")

    echo "登录返回原始数据: $LOGIN"

    # ===== 修复后的 Cookie 提取 =====
    COOKIE=$(grep -i "Set-Cookie" headers.txt \
        | sed -E 's/Set-Cookie:[[:space:]]*([^=]+=[^;]+).*/\1/' \
        | grep -v -i 'deleted' \
        | paste -sd '; ' -)

    if [ -n "$COOKIE" ]; then
        set_config COOKIE "$COOKIE"
        echo "✅ 已保存 Cookie 到 defaults.conf → $COOKIE"
    else
        echo "❌ 未获取到 Cookie"
    fi

    # ===== Bearer Token 解析（兼容多种字段）=====
    AUTH=$(echo "$LOGIN" | jq -r '
        .data.auth_data // .data.token // .auth_data // .token // empty
    ')

    if [ -n "$AUTH" ] && [ "$AUTH" != "null" ]; then
        case $AUTH in
            Bearer*) ;;  # 已包含 Bearer
            *) AUTH="Bearer $AUTH" ;;
        esac
        set_config AUTH "$AUTH"
        echo "✅ 已保存 Bearer Token 到 defaults.conf"
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

# 支持通过参数直接执行菜单功能
if [[ $# -gt 0 ]]; then
    choice=$1
    case $choice in
        5)
            get_best_node
            auto_update_subscription
            exit 0
            ;;
        *)
            echo "未知参数: $choice"
            exit 1
            ;;
    esac
fi

# 主菜单循环
while true; do
    echo -e "${CYAN}============================${NC}"
    echo -e "${CYAN} 配置订阅菜单${NC}"
    echo -e "${CYAN}============================${NC}"
    echo -e "${GREEN}1) 修改后端地址 ${NC}(当前: $(get_config BACKEND_URL))"
    echo -e "${GREEN}2) 修改订阅地址 ${NC}(当前: $(get_config SUBSCRIPTION_URL))"
    echo -e "${GREEN}3) 修改TProxy配置文件地址 ${NC}(当前: $(get_config TPROXY_TEMPLATE_URL))"
    echo -e "${GREEN}4) 修改TUN配置文件地址 ${NC}(当前: $(get_config TUN_TEMPLATE_URL))"
    echo -e "${GREEN}5) 自动登录并更新订阅地址 ${NC}(当前: $(get_config JC_URL))"
    echo -e "${GREEN}6) 修改 账号-密码-机场"
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
            get_best_node
            auto_update_subscription
            ;;
        6)
            read -rp "是否修改登录邮箱? (y/n): " ans_user
            if [ "$ans_user" = "y" ]; then
                read -rp "请输入新的登录邮箱: " USER
                if [ -n "$USER" ]; then
                    set_config USER "$USER"
                    echo "✅ 邮箱已更新"
                else
                    echo "❌ 邮箱不能为空"
                fi
            fi
        
            read -rp "是否修改登录密码? (y/n): " ans_pass
            if [ "$ans_pass" = "y" ]; then
                read -rsp "请输入新的登录密码: " PASS
                echo
                if [ -n "$PASS" ]; then
                    set_config PASS "$PASS"
                    echo "✅ 密码已更新"
                else
                    echo "❌ 密码不能为空"
                fi
            fi
        
            read -rp "是否修改网址 JC_URL? (y/n): " ans_url
            if [ "$ans_url" = "y" ]; then
                read -rp "请输入新的网址 JC_URL: " JC_URL
                if [ -n "$JC_URL" ]; then
                    set_config JC_URL "$JC_URL"
                    echo "✅ 机场地址 已更新"
                else
                    echo "❌ 机场地址 不能为空"
                fi
            fi
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
