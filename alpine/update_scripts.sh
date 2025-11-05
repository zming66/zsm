#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 脚本目录和临时目录
SCRIPT_DIR="/etc/sing-box/scripts"
TEMP_DIR="/tmp/sing-box"

# 脚本URL基础路径
BASE_URL="https://raw.githubusercontent.com/zming66/zsm/refs/heads/main/openwrt"
MENU_SCRIPT_URL="$BASE_URL/menu.sh"

# 提示用户检测版本
echo -e "${CYAN}正在检测版本，请耐心等待...${NC}"

# 创建目录
mkdir -p "$SCRIPT_DIR" "$TEMP_DIR"
chown "$(id -u)":"$(id -g)" "$SCRIPT_DIR" "$TEMP_DIR"

# 下载远程菜单脚本
wget -q -O "$TEMP_DIR/menu.sh" "$MENU_SCRIPT_URL"

# 检查是否下载成功
if [ ! -f "$TEMP_DIR/menu.sh" ]; then
    echo -e "${RED}下载远程脚本失败，请检查网络连接${NC}"
    exit 1
fi

# 获取版本号
LOCAL_VERSION=$(grep '^# 版本:' "$SCRIPT_DIR/menu.sh" 2>/dev/null | awk '{print $3}')
REMOTE_VERSION=$(grep '^# 版本:' "$TEMP_DIR/menu.sh" | awk '{print $3}')

if [ -z "$REMOTE_VERSION" ]; then
    echo -e "${RED}远程版本获取失败，请检查网络连接${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${CYAN}版本信息：本地 $LOCAL_VERSION，远程 $REMOTE_VERSION${NC}"

# 判断是否升级
if [ "$LOCAL_VERSION" == "$REMOTE_VERSION" ]; then
    echo -e "${GREEN}脚本已是最新版本${NC}"
    read -rp "是否强制更新？(y/n): " force_update
    [[ ! "$force_update" =~ ^[Yy]$ ]] && rm -rf "$TEMP_DIR" && exit 0
else
    echo -e "${RED}检测到新版本，准备升级...${NC}"
fi

# 更新脚本列表
SCRIPTS=(
    check_environment.sh
    install_singbox.sh
    manual_input.sh
    manual_update.sh
    auto_update.sh
    configure_tproxy.sh
    configure_tun.sh
    start_singbox.sh
    stop_singbox.sh
    clean_nft.sh
    set_defaults.sh
    commands.sh
    switch_mode.sh
    manage_autostart.sh
    check_config.sh
    update_singbox.sh
    update_scripts.sh
    update_ui.sh
    menu.sh
)

# 下载单个脚本函数，支持重试
download_script() {
    local SCRIPT="$1"
    local RETRIES=3
    local RETRY_DELAY=5
    for ((i=1;i<=RETRIES;i++)); do
        if wget -q -O "$SCRIPT_DIR/$SCRIPT" "$BASE_URL/$SCRIPT"; then
            chmod +x "$SCRIPT_DIR/$SCRIPT"
            return 0
        else
            sleep "$RETRY_DELAY"
        fi
    done
    echo -e "${RED}下载 $SCRIPT 失败${NC}"
    return 1
}

# 并行下载所有脚本
parallel_download_scripts() {
    local pids=()
    for SCRIPT in "${SCRIPTS[@]}"; do
        download_script "$SCRIPT" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# 常规更新
regular_update() {
    echo -e "${CYAN}正在清理旧脚本...${NC}"
    rm -f "$SCRIPT_DIR"/*.sh
    echo -e "${CYAN}正在更新脚本...${NC}"
    parallel_download_scripts
    echo -e "${GREEN}脚本更新完成${NC}"
}

# 重置更新
reset_update() {
    echo -e "${RED}停止 sing-box 并重置所有内容...${NC}"
    bash "$SCRIPT_DIR/clean_nft.sh" 2>/dev/null
    rm -rf /etc/sing-box
    echo -e "${CYAN}重新拉取菜单脚本...${NC}"
    bash <(curl -s "$MENU_SCRIPT_URL")
}

# 提示用户选择更新方式
echo -e "${CYAN}请选择更新方式:${NC}"
echo -e "${GREEN}1. 常规更新${NC}"
echo -e "${GREEN}2. 重置更新${NC}"
read -rp "请选择操作: " update_choice

case $update_choice in
    1)
        read -rp "是否继续常规更新？(y/n): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && regular_update || echo -e "${CYAN}操作已取消${NC}"
        ;;
    2)
        read -rp "是否继续重置更新？(y/n): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && reset_update || echo -e "${CYAN}操作已取消${NC}"
        ;;
    *)
        echo -e "${RED}无效选择${NC}"
        ;;
esac

# 清理临时目录
rm -rf "$TEMP_DIR"
