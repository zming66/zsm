#!/bin/sh
# Alpine Linux sing-box 安装/更新脚本
# 适用于 x86_64 / arm64 / aarch64 / armv7 等架构

# =====================
# 配置区
# =====================
REPO="SagerNet/sing-box"          # GitHub 仓库
BIN_PATH="/usr/local/bin/sing-box" # 可执行文件路径
TEMP_DIR="/tmp/sing-box_update"   # 临时目录
LAST_VER_FILE="/etc/sing-box/last_version" # 历史版本记录
MAX_RETRY=3                       # 下载重试次数

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
    for cmd in jq wget tar; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo -e "${RED}错误：缺少必要依赖 $cmd${NC}"
            echo "使用: apk add $cmd 安装"
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
# 带重试的获取函数
# =====================
fetch_with_retry() {
    url="$1"
    retry=0
    while [ $retry -lt $MAX_RETRY ]; do
        data=$(wget -qO- "$url" 2>/dev/null)
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
    echo -e "${RED}无法获取版本信息${NC}"
}

# =====================
# 清理旧版本
# =====================
cleanup_old_version() {
    if [ -f "$BIN_PATH" ]; then
        echo -e "${CYAN}检测到旧版本 sing-box，正在删除...${NC}"
        systemctl stop sing-box 2>/dev/null || true
        rm -f "$BIN_PATH"
        echo -e "${GREEN}旧版本已删除${NC}"
    fi
}

# =====================
# 安装流程核心
# =====================
install_version() {
    version=$1
    releases=$2
    [ -z "$version" ] && { echo -e "${RED}版本号为空${NC}"; return 1; }

    arch=$(determine_arch)

    bin_url=$(echo "$releases" | jq -r --arg ver "$version" --arg arch "$arch" \
        '.[] | select(.tag_name==$ver).assets[] | select(.name|contains("alpine") and contains($arch) and endswith(".tar.gz")).browser_download_url')

    [ -z "$bin_url" ] && { echo -e "${RED}未找到 $version 的 Alpine tar.gz 文件${NC}"; return 1; }

    mkdir -p "$TEMP_DIR"
    retry=0
    while [ $retry -lt $MAX_RETRY ]; do
        echo -e "${CYAN}下载尝试: $((retry+1))/$MAX_RETRY${NC}"
        if wget -qO "$TEMP_DIR/sing-box.tar.gz" "$bin_url"; then
            echo -e "${GREEN}✓ 下载成功${NC}"
            break
        fi
        retry=$((retry+1))
        sleep 3
    done
    [ $retry -eq $MAX_RETRY ] && { echo -e "${RED}✗ 下载失败${NC}"; return 1; }

    # 清理旧版本
    cleanup_old_version

    # 解压并移动到 /usr/local/bin
    tar -xzf "$TEMP_DIR/sing-box.tar.gz" -C "$TEMP_DIR"
    mv "$TEMP_DIR/sing-box" "$BIN_PATH"
    chmod +x "$BIN_PATH"

    # 设置 systemd 服务
    if [ ! -f /etc/systemd/system/sing-box.service ]; then
        cat <<EOF >/etc/systemd/system/sing-box.service
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=$BIN_PATH run -c /etc/sing-box/config.json
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable sing-box
    systemctl restart sing-box

    echo -e "${GREEN}sing-box 安装并启动成功${NC}"

    # 更新历史版本
    echo "$version" > "$LAST_VER_FILE"
}

# =====================
# 回退功能
# =====================
rollback_version() {
    releases=$1
    if [ ! -f "$LAST_VER_FILE" ]; then
        echo -e "${RED}未找到历史版本，无法回退${NC}"
        return 1
    fi
    old_ver=$(cat "$LAST_VER_FILE")
    install_version "$old_ver" "$releases"
}

# =====================
# 菜单
# =====================
show_menu() {
    clear
    current_ver=$("$BIN_PATH" version 2>/dev/null | awk '/version/ {print $3}')
    releases=$(fetch_releases)
    [ -z "$releases" ] && { echo -e "${RED}无法获取版本信息${NC}"; exit 1; }

    stable=$(echo "$releases" | jq -er '[.[]|select(.prerelease==false)][0].tag_name' 2>/dev/null || echo "")
    beta=$(echo "$releases" | jq -er '[.[]|select(.prerelease==true)][0].tag_name' 2>/dev/null || echo "")

    echo -e "\n${CYAN}======= Sing-box 更新助手 (Alpine) =======${NC}"
    echo -e "[当前版本] ${GREEN}${current_ver:-未安装}${NC}"
    echo -e "\n1) 更新到稳定版: ${stable:-获取失败}"
    echo -e "2) 更新到测试版: ${beta:-获取失败}"
    echo -e "3) 回退到上一个版本"
    echo -e "0) 退出"

    echo -ne "\n请选择 (1/2/3/0): "
    read choice
    case $choice in
        1) install_version "$stable" "$releases" ;;
        2) install_version "$beta" "$releases" ;;
        3) rollback_version "$releases" ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${NC}"; sleep 2; show_menu ;;
    esac
}

# =====================
# 主程序
# =====================
main() {
    check_dependencies
    mkdir -p "$TEMP_DIR" /etc/sing-box
    show_menu
    rm -rf "$TEMP_DIR"
}

main
