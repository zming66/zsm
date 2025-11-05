#!/bin/ash
#################################################
# 描述: Alpine Linux 版 sing-box 全自动脚本
# 版本: 1.3.1-alpine
# 作者: 改写自 OpenWRT 版本 (zming66)
#################################################

# ========== 颜色定义 ==========
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# ========== 目录定义 ==========
SCRIPT_DIR="/etc/sing-box/scripts"
INITIALIZED_FILE="$SCRIPT_DIR/.initialized"
BASE_URL="https://raw.githubusercontent.com/zming66/zsm/refs/heads/main/alpine"

mkdir -p "$SCRIPT_DIR"
chown root:root "$SCRIPT_DIR"

# ========== 脚本列表 ==========
SCRIPTS="
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
"

# ========== 函数定义 ==========
download_script() {
    local SCRIPT="$1"
    local RETRIES=5
    local RETRY_DELAY=5
    for i in $(seq 1 $RETRIES); do
        if wget -q -O "$SCRIPT_DIR/$SCRIPT" "$BASE_URL/$SCRIPT"; then
            chmod +x "$SCRIPT_DIR/$SCRIPT"
            return 0
        else
            echo -e "${YELLOW}下载 $SCRIPT 失败，重试 $i/$RETRIES...${NC}"
            sleep "$RETRY_DELAY"
        fi
    done
    echo -e "${RED}下载 $SCRIPT 失败，请检查网络连接。${NC}"
    return 1
}

parallel_download_scripts() {
    for SCRIPT in $SCRIPTS; do
        download_script "$SCRIPT" &
    done
    wait
}

initialize() {
    echo -e "${CYAN}开始初始化脚本...${NC}"
    find "$SCRIPT_DIR" -type f -name "*.sh" -delete
    parallel_download_scripts
    auto_setup
    touch "$INITIALIZED_FILE"
}

auto_setup() {
    echo -e "${GREEN}检测/安装依赖包...${NC}"
    apk add --no-cache bash curl wget iptables iproute2 jq >/dev/null 2>&1

    echo -e "${GREEN}创建配置目录...${NC}"
    mkdir -p /etc/sing-box
    touch /etc/sing-box/mode.conf

    echo -e "${GREEN}检测 sing-box 是否安装...${NC}"
    if ! command -v sing-box >/dev/null 2>&1; then
        echo -e "${CYAN}安装 sing-box...${NC}"
        bash "$SCRIPT_DIR/install_singbox.sh" || echo -e "${YELLOW}请手动安装 sing-box${NC}"
    fi

    echo -e "${CYAN}执行初始化配置...${NC}"
    bash "$SCRIPT_DIR/switch_mode.sh"
    bash "$SCRIPT_DIR/manual_input.sh"
    bash "$SCRIPT_DIR/start_singbox.sh"
}

show_menu() {
    clear
    echo -e "${CYAN}=========== Sbshell 管理菜单 ===========${NC}"
    echo -e "${GREEN}1. Tproxy/Tun 模式切换${NC}"
    echo -e "${GREEN}2. 手动更新配置文件${NC}"
    echo -e "${GREEN}3. 自动更新配置文件${NC}"
    echo -e "${GREEN}4. 启动 sing-box${NC}"
    echo -e "${GREEN}5. 停止 sing-box${NC}"
    echo -e "${GREEN}6. 默认参数设置${NC}"
    echo -e "${GREEN}7. 设置自启动${NC}"
    echo -e "${GREEN}8. 常用命令${NC}"
    echo -e "${GREEN}9. 更新脚本${NC}"
    echo -e "${GREEN}10. 更新控制面板${NC}"
    echo -e "${GREEN}11. 更新 sing-box${NC}"
    echo -e "${GREEN}0. 退出${NC}"
    echo -e "${CYAN}========================================${NC}"
}

handle_choice() {
    read -rp "请选择操作: " choice
    case $choice in
        1) bash "$SCRIPT_DIR/switch_mode.sh"; bash "$SCRIPT_DIR/manual_input.sh"; bash "$SCRIPT_DIR/start_singbox.sh" ;;
        2) bash "$SCRIPT_DIR/manual_update.sh" ;;
        3) bash "$SCRIPT_DIR/auto_update.sh" ;;
        4) bash "$SCRIPT_DIR/start_singbox.sh" ;;
        5) bash "$SCRIPT_DIR/stop_singbox.sh" ;;
        6) bash "$SCRIPT_DIR/set_defaults.sh" ;;
        7) bash "$SCRIPT_DIR/manage_autostart.sh" ;;
        8) bash "$SCRIPT_DIR/commands.sh" ;;
        9) bash "$SCRIPT_DIR/update_scripts.sh" ;;
        10) bash "$SCRIPT_DIR/update_ui.sh" ;;
        11) bash "$SCRIPT_DIR/update_singbox.sh" ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效的选择${NC}" ;;
    esac
}

# ========== 主流程 ==========
if [ ! -f "$INITIALIZED_FILE" ]; then
    echo -e "${CYAN}按回车初始化，输入 skip 跳过${NC}"
    read -r init_choice
    if [ "$init_choice" != "skip" ]; then
        initialize
    fi
fi

# 添加快捷命令
if ! grep -q "alias sb=" ~/.bashrc 2>/dev/null; then
    echo "alias sb='bash $SCRIPT_DIR/menu.sh menu'" >> ~/.bashrc
fi

if [ ! -f /usr/bin/sb ]; then
    echo -e '#!/bin/ash\nbash /etc/sing-box/scripts/menu.sh menu' > /usr/bin/sb
    chmod +x /usr/bin/sb
fi

while true; do
    show_menu
    handle_choice
done
