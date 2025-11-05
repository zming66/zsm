#!/bin/ash
# ==============================================
# 描述: Alpine Linux sing-box 自动更新配置脚本
# 版本: 1.0-alpine
# 原作者: zming66 (OpenWRT)
# 改写: ChatGPT (适配 Alpine)
# ==============================================

CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

MANUAL_FILE="/etc/sing-box/manual.conf"
UPDATE_SCRIPT="/etc/sing-box/update-singbox.sh"

# ========= 确保环境准备好 =========
apk add --no-cache bash curl wget jq dcron >/dev/null 2>&1
rc-service crond start 2>/dev/null || rc-service dcron start 2>/dev/null

# ========= 创建更新脚本 =========
cat > "$UPDATE_SCRIPT" <<'EOF'
#!/bin/ash

MANUAL_FILE="/etc/sing-box/manual.conf"

BACKEND_URL=$(grep BACKEND_URL "$MANUAL_FILE" | cut -d'=' -f2-)
SUBSCRIPTION_URL=$(grep SUBSCRIPTION_URL "$MANUAL_FILE" | cut -d'=' -f2-)
TEMPLATE_URL=$(grep TEMPLATE_URL "$MANUAL_FILE" | cut -d'=' -f2-)

FULL_URL="${BACKEND_URL}/config/${SUBSCRIPTION_URL}&file=${TEMPLATE_URL}"

# 备份旧配置
[ -f "/etc/sing-box/config.json" ] && cp /etc/sing-box/config.json /etc/sing-box/config.json.backup

# 下载新配置
if curl -L --connect-timeout 10 --max-time 30 "$FULL_URL" -o /etc/sing-box/config.json; then
    if ! sing-box check -c /etc/sing-box/config.json; then
        echo "配置验证失败，恢复备份..."
        [ -f "/etc/sing-box/config.json.backup" ] && cp /etc/sing-box/config.json.backup /etc/sing-box/config.json
    fi
else
    echo "下载配置失败，恢复备份..."
    [ -f "/etc/sing-box/config.json.backup" ] && cp /etc/sing-box/config.json.backup /etc/sing-box/config.json
fi

# 重启 sing-box 服务
if pgrep sing-box >/dev/null; then
    pkill sing-box
    nohup sing-box run -c /etc/sing-box/config.json >/var/log/singbox.log 2>&1 &
else
    nohup sing-box run -c /etc/sing-box/config.json >/var/log/singbox.log 2>&1 &
fi

echo "$(date '+%F %T') - sing-box 配置已自动更新" >> /var/log/singbox-update.log
EOF

chmod +x "$UPDATE_SCRIPT"

# ========= 设置交互菜单 =========
while true; do
    echo -e "${CYAN}请选择操作:${NC}"
    echo "1. 设置自动更新间隔"
    echo "2. 取消自动更新"
    read -rp "请输入选项 (1或2, 默认为1): " menu_choice
    menu_choice=${menu_choice:-1}

    if [ "$menu_choice" = "1" ]; then
        while true; do
            read -rp "请输入更新间隔小时数 (1-23小时, 默认为12小时): " interval_choice
            interval_choice=${interval_choice:-12}

            case "$interval_choice" in
                [1-9]|1[0-9]|2[0-3]) break ;;
                *) echo -e "${RED}输入无效，请输入 1~23。${NC}" ;;
            esac
        done

        # 清除旧任务
        crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT" | crontab -

        # 添加新任务
        (crontab -l 2>/dev/null; echo "0 */$interval_choice * * * $UPDATE_SCRIPT") | crontab -

        rc-service crond restart 2>/dev/null || rc-service dcron restart 2>/dev/null

        echo -e "${CYAN}✅ 已设置每 $interval_choice 小时自动更新一次配置。${NC}"
        break

    elif [ "$menu_choice" = "2" ]; then
        crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT" | crontab -
        rc-service crond restart 2>/dev/null || rc-service dcron restart 2>/dev/null
        echo -e "${CYAN}已取消自动更新任务。${NC}"
        break

    else
        echo -e "${RED}输入无效，请重新输入。${NC}"
    fi
done
