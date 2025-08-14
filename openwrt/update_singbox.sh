#!/bin/sh
# OpenWrt sing-box 精简安装脚本（增强版）

REPO="SagerNet/sing-box"         # GitHub 仓库
BIN_PATH="/usr/bin/sing-box"     # 可执行文件路径
TEMP_DIR="/tmp/sing-box_update"  # 临时目录
MAX_RETRY=3                      # 下载最大重试次数

# 颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 检查依赖
check_dependencies() {
    for cmd in jq uclient-fetch opkg; do
        if ! command -v $cmd >/dev/null; then
            echo -e "${RED}错误：缺少必要依赖 $cmd${NC}"
            exit 1
        fi
    done
}

# 检测架构
determine_arch() {
    case $(uname -m) in
        x86_64)  echo "x86_64" ;;
        aarch64) echo "arm64"  ;;
        armv7l)  echo "armv7"  ;;
        *)       echo "$(uname -m)" ;;
    esac
}

# 重试获取
fetch_with_retry() {
    url="$1"
    retries=3
    while [ $retries -gt 0 ]; do
        result=$(uclient-fetch -qO- --no-check-certificate \
                 -H "User-Agent: singbox-updater" "$url" 2>/dev/null)
        if [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
        retries=$((retries - 1))
        sleep 2
    done
    return 1
}

# 获取 releases 数据（API → 镜像 API → HTML）
fetch_releases() {
    base_url="https://api.github.com/repos/$REPO/releases"

    # API 直连
    data=$(fetch_with_retry "$base_url")
    if [ -n "$data" ]; then
        echo "$data"
        return
    fi

    # 国内加速镜像
    echo -e "${CYAN}API直连失败，尝试镜像...${NC}"
    data=$(fetch_with_retry "https://ghproxy.com/$base_url")
    if [ -n "$data" ]; then
        echo "$data"
        return
    fi

    # HTML 兜底
    echo -e "${CYAN}API获取失败，尝试解析GitHub网页...${NC}"
    html=$(fetch_with_retry "https://github.com/$REPO/releases")
    if [ -n "$html" ]; then
        echo "$html" | grep -oP '(?<=/tag/)[^"]+' | awk '{print "{\"tag_name\":\""$1"\"}"}'
    fi
}

# 安装版本
install_version() {
    version=$1
    [ -z "$version" ] && return 1

    arch=$(determine_arch)
    case $arch in
        x86_64) search_arch="x86_64" ;;
        arm64)  search_arch="arm64"  ;;
        *)      search_arch="$arch"  ;;
    esac

    ipk_url=$(fetch_with_retry "https://api.github.com/repos/$REPO/releases" | \
        jq -r --arg ver "$version" --arg arch "$search_arch" \
        '.[] | select(.tag_name == $ver).assets[] |
         select(.name | contains($arch) and endswith(".ipk")).browser_download_url')

    [ -z "$ipk_url" ] && {
        echo -e "${RED}未找到 $version 的IPK文件${NC}"
        return 1
    }

    mkdir -p "$TEMP_DIR"
    retry=0
    while [ $retry -lt $MAX_RETRY ]; do
        echo -e "${CYAN}下载尝试: $((retry+1))/$MAX_RETRY${NC}"
        if uclient-fetch -qO "$TEMP_DIR/sing-box.ipk" "$ipk_url" --no-check-certificate; then
            if [ -s "$TEMP_DIR/sing-box.ipk" ]; then
                echo -e "${GREEN}✓ 下载成功${NC}"
                break
            else
                echo -e "${RED}✗ 文件为空，重试${NC}"
            fi
        fi
        retry=$((retry+1))
        sleep 3
    done

    [ $retry -eq $MAX_RETRY ] && {
        echo -e "${RED}✗ 下载失败，终止流程${NC}"
        return 1
    }

    [ -f "/etc/init.d/sing-box" ] && {
        echo -e "${CYAN}停止服务...${NC}"
        /etc/init.d/sing-box stop
    }

    echo -e "${CYAN}卸载旧版本...${NC}"
    opkg remove sing-box

    echo -e "${CYAN}开始安装...${NC}"
    if opkg install "$TEMP_DIR/sing-box.ipk"; then
        echo -e "${GREEN}✓ 安装成功${NC}"
        rm -f "/etc/init.d/sing-box-opkg" \
              "/etc/sing-box/config.json-opkg" \
              "$TEMP_DIR/sing-box.ipk"

        /etc/init.d/sing-box enable
        /etc/init.d/sing-box start
    else
        echo -e "${RED}✗ 安装失败${NC}"
        return 1
    fi
}

# 菜单
show_menu() {
    clear
    current_ver=$($BIN_PATH version 2>/dev/null | grep -oE '([0-9]+\.)+[0-9]+' || echo "未安装")

    releases=$(fetch_releases)
    if echo "$releases" | grep -q "tag_name"; then
        stable=$(echo "$releases" | jq -r '[.[] | select(.prerelease == false)][0].tag_name // "获取失败"')
        beta=$(echo "$releases" | jq -r '[.[] | select(.prerelease == true)][0].tag_name // "获取失败"')
    else
        stable="获取失败"
        beta="获取失败"
    fi

    echo -e "\n${CYAN}======= Sing-box 更新助手 ======="
    echo -e "[当前版本] ${GREEN}${current_ver}${NC}"
    echo -e "\n${CYAN}1) 稳定版: $stable"
    echo -e "2) 测试版: $beta${NC}"
    echo -e "\n${RED}0) 退出${NC}"

    echo -ne "\n${CYAN}请选择 (1/2/0): ${NC}"
    read -r choice
    case $choice in
        1) [ "$stable" != "获取失败" ] && install_version "$stable" ;;
        2) [ "$beta" != "获取失败" ] && install_version "$beta" ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入，2秒后重试...${NC}"; sleep 2; show_menu ;;
    esac
}

# 主函数
singbox() {
    check_dependencies
    mkdir -p "$TEMP_DIR"
    show_menu
    rm -rf "$TEMP_DIR"
}

singbox
