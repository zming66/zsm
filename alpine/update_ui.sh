#!/bin/sh

UI_DIR="/etc/sing-box/ui"
BACKUP_DIR="/tmp/sing-box/ui_backup"
TEMP_DIR="/tmp/sing-box-ui"

ZASHBOARD_URL="https://ghproxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip"
METACUBEXD_URL="https://ghproxy.com/https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
YACD_URL="https://ghproxy.com/https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip"

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 创建目录
mkdir -p "$BACKUP_DIR" "$TEMP_DIR"

# 检查依赖
check_and_install_dependencies() {
    for cmd in unzip curl crond; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo -e "${RED}$cmd 未安装,正在安装...${NC}"
            apk add --no-cache $cmd
        fi
    done
    # 启动 crond 后台服务
    rc-update add crond default
    service crond start
}

# 获取默认下载 URL
get_download_url() {
    CONFIG_FILE="/etc/sing-box/config.json"
    DEFAULT_URL="$ZASHBOARD_URL"

    if [ -f "$CONFIG_FILE" ]; then
        URL=$(grep -o '"external_ui_download_url": "[^"]*' "$CONFIG_FILE" | sed 's/"external_ui_download_url": "//')
        echo "${URL:-$DEFAULT_URL}"
    else
        echo "$DEFAULT_URL"
    fi
}

# 备份并删除旧 UI
backup_and_remove_ui() {
    if [ -d "$UI_DIR" ]; then
        echo -e "${CYAN}备份当前 UI 文件夹...${NC}"
        mv "$UI_DIR" "$BACKUP_DIR/$(date +%Y%m%d%H%M%S)_ui"
        echo -e "${GREEN}已备份至 $BACKUP_DIR${NC}"
    fi
}

# 下载并处理 UI
download_and_process_ui() {
    url="$1"
    temp_file="$TEMP_DIR/ui.zip"
    rm -rf "${TEMP_DIR:?}"/*

    echo -e "${CYAN}正在下载 UI 面板...${NC}"
    curl -L "$url" -o "$temp_file"
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败，正在还原备份...${NC}"
        [ -d "$BACKUP_DIR" ] && mv "$BACKUP_DIR/"* "$UI_DIR" 2>/dev/null
        return 1
    fi

    echo -e "${CYAN}解压中...${NC}"
    if unzip "$temp_file" -d "$TEMP_DIR" >/dev/null 2>&1; then
        mkdir -p "$UI_DIR"
        rm -rf "${UI_DIR:?}"/*
        mv "$TEMP_DIR"/*/* "$UI_DIR"
        echo -e "${GREEN}面板安装完成${NC}"
        return 0
    else
        echo -e "${RED}解压失败，正在还原备份...${NC}"
        [ -d "$BACKUP_DIR" ] && mv "$BACKUP_DIR/"* "$UI_DIR" 2>/dev/null
        return 1
    fi
}

# 安装默认 UI
install_default_ui() {
    echo -e "${CYAN}正在安装默认 UI 面板...${NC}"
    DOWNLOAD_URL=$(get_download_url)
    backup_and_remove_ui
    download_and_process_ui "$DOWNLOAD_URL"
}

# 安装自选 UI
install_selected_ui() {
    url="$1"
    backup_and_remove_ui
    download_and_process_ui "$url"
}

# 检查 UI
check_ui() {
    if [ -d "$UI_DIR" ] && [ "$(ls -A "$UI_DIR")" ]; then
        echo -e "${GREEN}UI 面板已安装${NC}"
    else
        echo -e "${RED}UI 面板未安装或为空${NC}"
    fi
}

# 设置自动更新
setup_auto_update_ui() {
    echo -e "${CYAN}请选择自动更新频率：${NC}"
    echo "1. 每周一"
    echo "2. 每月1号"
    read -rp "请输入选项(1/2, 默认1): " schedule_choice
    schedule_choice=${schedule_choice:-1}

    # 写入更新脚本
    cat >/etc/sing-box/update-ui.sh <<EOF
#!/bin/sh
CONFIG_FILE="/etc/sing-box/config.json"
DEFAULT_URL="$ZASHBOARD_URL"
URL=\$(grep -o '"external_ui_download_url": "[^"]*' "\$CONFIG_FILE" | sed 's/"external_ui_download_url": "//')
URL="\${URL:-\$DEFAULT_URL}"

TEMP_DIR="/tmp/sing-box-ui"
UI_DIR="/etc/sing-box/ui"
BACKUP_DIR="/tmp/sing-box/ui_backup"

mkdir -p "\$BACKUP_DIR" "\$TEMP_DIR"

[ -d "\$UI_DIR" ] && mv "\$UI_DIR" "\$BACKUP_DIR/\$(date +%Y%m%d%H%M%S)_ui"

curl -L "\$URL" -o "\$TEMP_DIR/ui.zip"
unzip "\$TEMP_DIR/ui.zip" -d "\$TEMP_DIR" >/dev/null 2>&1 && \
mkdir -p "\$UI_DIR" && rm -rf "\${UI_DIR:?}"/* && mv "\$TEMP_DIR"/*/* "\$UI_DIR"
EOF

    chmod +x /etc/sing-box/update-ui.sh

    # 设置 crontab
    crontab -l 2>/dev/null | grep -v 'update-ui.sh' >/tmp/crontab.tmp
    if [ "$schedule_choice" -eq 1 ]; then
        echo "0 0 * * 1 /etc/sing-box/update-ui.sh" >> /tmp/crontab.tmp
        echo -e "${GREEN}每周一自动更新已设置${NC}"
    else
        echo "0 0 1 * * /etc/sing-box/update-ui.sh" >> /tmp/crontab.tmp
        echo -e "${GREEN}每月1号自动更新已设置${NC}"
    fi
    crontab /tmp/crontab.tmp
    rm -f /tmp/crontab.tmp
}

# 主菜单
update_ui() {
    check_and_install_dependencies
    while true; do
        echo -e "${CYAN}请选择功能：${NC}"
        echo "1. 默认 UI（依据配置文件）"
        echo "2. 安装/更新自选 UI"
        echo "3. 检查是否存在 UI 面板"
        echo "4. 设置定时自动更新 UI"
        read -r -p "请输入选项(1/2/3/4)或回车退出: " choice

        [ -z "$choice" ] && exit 0

        case "$choice" in
            1) install_default_ui; exit 0 ;;
            2)
                echo -e "${CYAN}请选择面板安装：${NC}"
                echo "1. Zashboard"
                echo "2. MetaCubeXD"
                echo "3. Yacd"
                read -r -p "请输入选项(1/2/3): " ui_choice
                case "$ui_choice" in
                    1) install_selected_ui "$ZASHBOARD_URL" ;;
                    2) install_selected_ui "$METACUBEXD_URL" ;;
                    3) install_selected_ui "$YACD_URL" ;;
                    *) echo -e "${RED}无效选项，返回菜单${NC}" ;;
                esac
                exit 0
                ;;
            3) check_ui ;;
            4) setup_auto_update_ui ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac
    done
}

update_ui
