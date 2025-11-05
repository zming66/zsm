#!/bin/bash

CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

MANUAL_FILE="/etc/sing-box/manual.conf"
DEFAULTS_FILE="/etc/sing-box/defaults.conf"
CONFIG_FILE="/etc/sing-box/config.json"

MODE=$(grep -E '^MODE=' /etc/sing-box/mode.conf 2>/dev/null | cut -d'=' -f2)
MODE=${MODE:-TUN}  # 默认 TUN 模式

prompt_user_input() {
    read -rp "请输入后端地址(回车使用默认值可留空): " BACKEND_URL
    BACKEND_URL=${BACKEND_URL:-$(grep BACKEND_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)}

    read -rp "请输入订阅地址(回车使用默认值可留空): " SUBSCRIPTION_URL
    SUBSCRIPTION_URL=${SUBSCRIPTION_URL:-$(grep SUBSCRIPTION_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)}

    read -rp "请输入配置文件地址(回车使用默认值可留空): " TEMPLATE_URL
    if [ -z "$TEMPLATE_URL" ]; then
        if [ "$MODE" = "TProxy" ]; then
            TEMPLATE_URL=$(grep TPROXY_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
        else
            TEMPLATE_URL=$(grep TUN_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
        fi
    fi

    echo -e "${CYAN}使用配置: BACKEND=$BACKEND_URL, SUBSCRIPTION=$SUBSCRIPTION_URL, TEMPLATE=$TEMPLATE_URL${NC}"
}

while true; do
    prompt_user_input
    read -rp "确认输入的配置信息？(y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 更新手动配置
        cat > "$MANUAL_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TEMPLATE_URL=$TEMPLATE_URL
EOF

        # 构建完整链接
        if [ -n "$BACKEND_URL" ] && [ -n "$SUBSCRIPTION_URL" ]; then
            FULL_URL="${BACKEND_URL}/config/${SUBSCRIPTION_URL}"
            [ -n "$TEMPLATE_URL" ] && FULL_URL="${FULL_URL}&file=${TEMPLATE_URL}"
        else
            FULL_URL="${TEMPLATE_URL}"
        fi
        echo "完整订阅链接: $FULL_URL"

        # 备份旧配置
        [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"

        # 下载并验证
        while true; do
            if curl -fSL --connect-timeout 10 --max-time 30 "$FULL_URL" -o "$CONFIG_FILE"; then
                if sing-box check -c "$CONFIG_FILE"; then
                    echo -e "${CYAN}✅ 配置文件下载并验证成功${NC}"
                    break
                else
                    echo -e "${RED}❌ 配置验证失败，恢复备份${NC}"
                    [ -f "${CONFIG_FILE}.backup" ] && cp "${CONFIG_FILE}.backup" "$CONFIG_FILE"
                    exit 1
                fi
            else
                echo -e "${RED}❌ 配置文件下载失败${NC}"
                read -rp "是否重试？(y/n): " retry
                [[ "$retry" =~ ^[Nn]$ ]] && exit 1
            fi
        done
        break
    fi
done
