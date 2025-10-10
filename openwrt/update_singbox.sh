#!/bin/sh
# OpenWrt sing-box 精简安装脚本（增加版本回退功能）

# =====================
# 配置区
# =====================
REPO="SagerNet/sing-box"         # GitHub仓库
BIN_PATH="/usr/bin/sing-box"     # 可执行文件路径
TEMP_DIR="/tmp/sing-box_update"  # 临时目录
LAST_VER_FILE="/etc/sing-box/last_version" # 版本号记录
MAX_RETRY=3                      # 下载最大重试次数

# =====================
# 颜色定义
# =====================
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# =====================
# 依赖检查
# =====================
check_dependencies() {
    for cmd in jq uclient-fetch opkg; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo -e "${RED}错误：缺少必要依赖 $cmd${NC}"
            exit 1
        fi
    done
}

# =====================
# 架构检测
# =====================
determine_arch() {
    case $(uname -m) in
        x86_64)  echo "x86_64" ;;
        aarch64) echo "arm64"  ;;
        armv7l)  echo "armv7"  ;;
        *)       echo "$(uname -m)" ;;
    esac
}

# =====================
# 通用带重试的获取函数
# =====================
fetch_with_retry() {
    url="$1"
    retry=0
    while [ $retry -lt $MAX_RETRY ]; do
        data=$(uclient-fetch -qO- "$url" 2>/dev/null)
        if [ -n "$data" ]; then
            echo "$data"
            return 0
        fi
        retry=$((retry+1))
        sleep 2
    done
    return 1
}

# =====================
# 获取版本信息
# =====================
fetch_releases() {
    base_url="https://api.github.com/repos/$REPO/releases"
    data=$(fetch_with_retry "$base_url")
    [ -n "$data" ] && { echo "$data"; return; }

    echo -e "${CYAN}API直连失败，尝试镜像...${NC}"
    data=$(fetch_with_retry "https://ghproxy.com/$base_url")
    [ -n "$data" ] && { echo "$data"; return; }

    echo -e "${RED}无法获取版本信息${NC}"
}

# =====================
# 安装流程核心
# =====================
install_version() {
    version=$1
    [ -z "$version" ] && return 1

    # 记录当前版本号
    current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
    [ -n "$current_ver" ] && echo "$current_ver" > "$LAST_VER_FILE"

    arch=$(determine_arch)
    case $arch in
        x86_64) search_arch="x86_64" ;;
        arm64)  search_arch="arm64"  ;;
        *)      search_arch="$arch"  ;;
    esac

    ipk_url=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
        jq -r --arg ver "$version" --arg arch "$search_arch" \
        '.[] | select(.tag_name == $ver).assets[] |
         select(.name | contains("openwrt") and contains($arch) and endswith(".ipk")).browser_download_url')

    [ -z "$ipk_url" ] && { echo -e "${RED}未找到 $version 的IPK文件${NC}"; return 1; }

    mkdir -p "$TEMP_DIR"
    retry=0
    while [ $retry -lt $MAX_RETRY ]; do
        echo -e "${CYAN}下载尝试: $((retry+1))/$MAX_RETRY${NC}"
        if uclient-fetch -qO "$TEMP_DIR/sing-box.ipk" "$ipk_url"; then
            echo -e "${GREEN}✓ 下载成功${NC}"
            break
        fi
        retry=$((retry+1))
        sleep 3
    done
    [ $retry -eq $MAX_RETRY ] && { echo -e "${RED}✗ 下载失败${NC}"; return 1; }

    [ -f "/etc/init.d/sing-box" ] && /etc/init.d/sing-box stop
    opkg remove sing-box
    if opkg install "$TEMP_DIR/sing-box.ipk"; then
        echo -e "${GREEN}✓ 安装成功${NC}"
        /etc/init.d/sing-box enable
        /etc/init.d/sing-box start
    else
        echo -e "${RED}✗ 安装失败${NC}"
        return 1
    fi
}

# =====================
# 回退功能
# =====================
rollback_version() {
    if [ ! -f "$LAST_VER_FILE" ]; then
        echo -e "${RED}未找到历史版本记录，无法回退${NC}"
        return 1
    fi
    old_ver=$(cat "$LAST_VER_FILE")
    echo -e "${CYAN}准备回退到版本: $old_ver${NC}"
    install_version "$old_ver"
}

# =====================
# 用户界面
# =====================
show_menu() {
    clear
    current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
    releases=$(fetch_releases)
    stable=$(echo "$releases" | jq -r '[.[] | select(.prerelease == false)][0].tag_name')
    beta=$(echo "$releases" | jq -r '[.[] | select(.prerelease == true)][0].tag_name')

    echo -e "\n${CYAN}======= Sing-box 更新助手 =======${NC}"
    echo -e "[当前版本] ${GREEN}${current_ver:-未安装}${NC}"
    echo -e "\n1) 更新到稳定版: ${stable:-获取失败}"
    echo -e "2) 更新到测试版: ${beta:-获取失败}"
    echo -e "3) 回退到上一个版本"
    echo -e "0) 退出"

    echo -ne "\n请选择 (1/2/3/0): "
    read -r choice
    case $choice in
        1) install_version "$stable" ;;
        2) install_version "$beta" ;;
        3) rollback_version ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${NC}"; sleep 2; show_menu ;;
    esac
}

# =====================
# 主程序
# =====================
singbox() {
    check_dependencies
    mkdir -p "$TEMP_DIR"
    show_menu
    rm -rf "$TEMP_DIR"
}

singbox
