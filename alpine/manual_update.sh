#!/bin/bash
# ====================================================
# sing-box 自动更新与防火墙应用脚本
# 支持 TProxy/TUN 模式
# ====================================================

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 文件路径
MANUAL_FILE="/etc/sing-box/manual.conf"
DEFAULTS_FILE="/etc/sing-box/defaults.conf"
CONFIG_FILE="/etc/sing-box/config.json"
MODE_FILE="/etc/sing-box/mode.conf"

# 获取当前模式
if [ ! -f "$MODE_FILE" ]; then
    echo -e "${RED}未找到模式文件 $MODE_FILE，请先设置模式 (TProxy/TUN)${NC}"
    exit 1
fi
MODE=$(grep '^MODE=' "$MODE_FILE" | cut -d'=' -f2)

# 提示用户输入订阅信息
prompt_user_input() {
    while true; do
        read -rp "请输入后端地址(不填使用默认): " BACKEND_URL
        if [ -z "$BACKEND_URL" ]; then
            BACKEND_URL=$(grep BACKEND_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
            [ -n "$BACKEND_URL" ] && echo -e "${CYAN}使用默认后端: $BACKEND_URL${NC}"
        fi
        [ -n "$BACKEND_URL" ] && break || echo -e "${RED}必须填写后端地址${NC}"
    done

    while true; do
        read -rp "请输入订阅地址(不填使用默认): " SUBSCRIPTION_URL
        if [ -z "$SUBSCRIPTION_URL" ]; then
            SUBSCRIPTION_URL=$(grep SUBSCRIPTION_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
            [ -n "$SUBSCRIPTION_URL" ] && echo -e "${CYAN}使用默认订阅: $SUBSCRIPTION_URL${NC}"
        fi
        [ -n "$SUBSCRIPTION_URL" ] && break || echo -e "${RED}必须填写订阅地址${NC}"
    done

    while true; do
        read -rp "请输入配置模板地址(不填使用默认): " TEMPLATE_URL
        if [ -z "$TEMPLATE_URL" ]; then
            if [ "$MODE" = "TProxy" ]; then
                TEMPLATE_URL=$(grep TPROXY_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
            else
                TEMPLATE_URL=$(grep TUN_TEMPLATE_URL "$DEFAULTS_FILE" 2>/dev/null | cut -d'=' -f2-)
            fi
            [ -n "$TEMPLATE_URL" ] && echo -e "${CYAN}使用默认模板: $TEMPLATE_URL${NC}"
        fi
        [ -n "$TEMPLATE_URL" ] && break || echo -e "${RED}必须填写模板地址${NC}"
    done
}

# 是否更换订阅
read -rp "是否更换订阅地址? (y/n): " CHANGE_SUBS
if [[ "$CHANGE_SUBS" =~ ^[Yy]$ ]]; then
    prompt_user_input
    # 更新手动配置文件
    cat > "$MANUAL_FILE" <<EOF
BACKEND_URL=$BACKEND_URL
SUBSCRIPTION_URL=$SUBSCRIPTION_URL
TEMPLATE_URL=$TEMPLATE_URL
EOF
else
    if [ ! -f "$MANUAL_FILE" ]; then
        echo -e "${RED}订阅配置不存在，请先设置！${NC}"
        exit 1
    fi
    BACKEND_URL=$(grep BACKEND_URL "$MANUAL_FILE" | cut -d'=' -f2-)
    SUBSCRIPTION_URL=$(grep SUBSCRIPTION_URL "$MANUAL_FILE" | cut -d'=' -f2-)
    TEMPLATE_URL=$(grep TEMPLATE_URL "$MANUAL_FILE" | cut -d'=' -f2-)
fi

# 构建完整 URL
FULL_URL="${BACKEND_URL}/config/${SUBSCRIPTION_URL}"
[ -n "$TEMPLATE_URL" ] && FULL_URL="${FULL_URL}&file=${TEMPLATE_URL}"
echo -e "${CYAN}生成完整订阅链接: $FULL_URL${NC}"

# 备份现有配置
[ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"

# 下载配置文件
if curl -fSL --connect-timeout 10 --max-time 30 "$FULL_URL" -o "$CONFIG_FILE"; then
    echo -e "${GREEN}配置文件下载成功${NC}"
    if ! sing-box check -c "$CONFIG_FILE"; then
        echo -e "${RED}配置验证失败，恢复备份${NC}"
        [ -f "${CONFIG_FILE}.backup" ] && cp "${CONFIG_FILE}.backup" "$CONFIG_FILE"
        exit 1
    fi
else
    echo -e "${RED}下载失败，恢复备份${NC}"
    [ -f "${CONFIG_FILE}.backup" ] && cp "${CONFIG_FILE}.backup" "$CONFIG_FILE"
    exit 1
fi

# 应用防火墙规则函数
apply_firewall() {
    if [ "$MODE" = "TProxy" ]; then
        bash /etc/sing-box/scripts/configure_tproxy.sh
    elif [ "$MODE" = "TUN" ]; then
        bash /etc/sing-box/scripts/configure_tun.sh
    else
        echo -e "${RED}未知模式: $MODE${NC}"
        exit 1
    fi
}

# 重启服务
if command -v rc-service >/dev/null 2>&1; then
    # Alpine/OpenRC
    rc-service sing-box restart
elif command -v systemctl >/dev/null 2>&1; then
    systemctl restart sing-box
else
    /etc/init.d/sing-box restart
fi

# 等待 2 秒应用
sleep 2

# 检查服务状态
if pgrep -x sing-box >/dev/null 2>&1; then
    echo -e "${GREEN}sing-box 启动成功${NC}"
else
    echo -e "${RED}sing-box 启动失败${NC}"
fi

# 应用防火墙规则
apply_firewall

echo -e "${GREEN}订阅更新与防火墙应用完成！${NC}"
