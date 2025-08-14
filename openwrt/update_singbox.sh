#!/bin/sh
# OpenWrt sing-box 精简安装脚本（优化版，修复重复输出问题）

# =====================
# 配置区
# =====================
REPO="SagerNet/sing-box"         # GitHub仓库
BIN_PATH="/usr/bin/sing-box"     # 可执行文件路径
TEMP_DIR="/tmp/sing-box_update"  # 临时目录
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
# 获取版本信息（API → 镜像 → HTML兜底）
# =====================
fetch_releases() {
    base_url="https://api.github.com/repos/$REPO/releases"

    # 1. API直连
    data=$(fetch_with_retry "$base_url")
    if [ -n "$data" ]; then
        echo "$data"
        return
    fi

    # 2. 国内加速镜像
    echo -e "${CYAN}API直连失败，尝试镜像...${NC}"
    data=$(fetch_with_retry "https://ghproxy.com/$base_url")
    if [ -n "$data" ]; then
        echo "$data"
        return
    fi

    # 3. HTML 兜底（防止额外输出版本号）
    echo -e "${CYAN}API获取失败，尝试解析GitHub网页...${NC}"
    html=$(fetch_with_retry "https://github.com/$REPO/releases")
    if [ -n "$html" ]; then
        ver=$(echo "$html" | grep -oP '(?<=/tag/)[^"]+' 2>/dev/null | \
              grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null | \
              head -n1)
        if [ -n "$ver" ]; then
            echo "[{\"tag_name\":\"$ver\"}]"
        fi
    fi
}

# =====================
# 安装流程核心
# =====================
install_version() {
    version=$1
    [ -z "$version" ] && return 1

    # 架构处理
    arch=$(determine_arch)
    case $arch in
        x86_64) search_arch="x86_64" ;;
        arm64)  search_arch="arm64"  ;;
        *)      search_arch="$arch"  ;;
    esac

    # 获取下载链接
    ipk_url=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
        jq -r --arg ver "$version" --arg arch "$search_arch" \
        '.[] | select(.tag_name == $ver).assets[] |
         select(.name | contains("openwrt") and contains($arch) and endswith(".ipk")).browser_download_url')

    [ -z "$ipk_url" ] && {
        echo -e "${RED}未找到 $version 的IPK文件${NC}"
        return 1
    }

    # 下载流程
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

    [ $retry -eq $MAX_RETRY ] && {
        echo -e "${RED}✗ 下载失败，终止流程${NC}"
        return 1
    }

    # 停止服务
    [ -f "/etc/init.d/sing-box" ] && {
        echo -e "${CYAN}停止服务...${NC}"
        /etc/init.d/sing-box stop
    }

    # 卸载旧版
    echo -e "${CYAN}卸载旧版本...${NC}"
    opkg remove sing-box

    # 安装新版
    echo -e "${CYAN}开始安装...${NC}"
    if opkg install "$TEMP_DIR/sing-box.ipk"; then
        echo -e "${GREEN}✓ 安装成功${NC}"

        # 清理残留文件
        echo -e "${CYAN}清理旧版本残留...${NC}"
        rm -f "/etc/init.d/sing-box-opkg" \
              "/etc/sing-box/config.json-opkg" \
              "$TEMP_DIR/sing-box.ipk"

        # 启用并启动服务
        /etc/init.d/sing-box enable
        /etc/init.d/sing-box start
        cmd_status=$?
        if [ "$cmd_status" -eq 0 ]; then
            echo -e "${GREEN}自启动已成功启用。${NC}"
        else
            echo -e "${RED}启用自启动失败。${NC}"
        fi
    else
        echo -e "${RED}✗ 安装失败${NC}"
        return 1
    fi
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
    echo -e "\n${CYAN}1) 稳定版: ${stable:-获取失败}"
    echo -e "2) 测试版: ${beta:-获取失败}${NC}"
    echo -e "\n${RED}0) 退出${NC}"

    echo -ne "\n${CYAN}请选择 (1/2/0): ${NC}"
    read -r choice

    case $choice in
        1) install_version "$stable" ;;
        2) install_version "$beta" ;;
        0) exit 0 ;;
        *)
            echo -e "${RED}无效输入，2秒后重试...${NC}"
            sleep 2
            show_menu
            ;;
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
