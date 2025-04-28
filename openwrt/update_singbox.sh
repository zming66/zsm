#!/bin/sh
# OpenWrt专用sing-box更新脚本
# 该脚本直接从GitHub仓库下载IPK文件并通过opkg进行安装更新

# 定义颜色变量，便于终端输出友好提示
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 仓库、安装路径以及临时工作目录设置
REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
TEMP_DIR="/tmp/sing-box_update"
BACKUP_DIR="/etc/sing-box/backup"

# 创建必要目录
mkdir -p "$TEMP_DIR" "$BACKUP_DIR"

# 根据系统架构返回对应的标识
determine_ipk_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l|armv7) echo "armv7" ;;
        i686) echo "i386" ;;
        *) echo "$(uname -m)" ;;
    esac
}
IPK_ARCH=$(determine_ipk_arch)

# 从GitHub获取发布信息，利用jq将版本分为稳定版和测试版
fetch_releases() {
    uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
    jq -r 'group_by(.prerelease) | {
        "stable": [.[] | select(.prerelease == false) | .tag_name],
        "beta":   [.[] | select(.prerelease == true)  | .tag_name]
    }'
}

# 显示当前安装版本及可选的稳定版和测试版列表
show_menu() {
    current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/{print $3}')
    releases=$(fetch_releases)
    
    echo -e "\n${CYAN}=== 当前版本 ===${NC}"
    if [ -n "$current_ver" ]; then
        echo -e "${GREEN}$current_ver${NC}"
    else
        echo -e "${RED}未安装${NC}"
    fi
    
    echo -e "\n${CYAN}=== 稳定版列表 ===${NC}"
    stable_vers=$(echo "$releases" | jq -r '.stable[]')
    if [ -n "$stable_vers" ]; then
        echo "$stable_vers" | nl -w 3 -s ") "
    else
        echo -e "${YELLOW}暂无稳定版${NC}"
    fi
    
    echo -e "\n${CYAN}=== 测试版列表 ===${NC}"
    beta_vers=$(echo "$releases" | jq -r '.beta[]')
    if [ -n "$beta_vers" ]; then
        echo "$beta_vers" | nl -w 3 -s ") " | awk '{print $0" (测试版)"}'
    else
        echo -e "${YELLOW}暂无测试版${NC}"
    fi
}

# 通过下载IPK文件并使用opkg进行安装更新sing-box
replace_by_ipk() {
    version=$1
    # 获取当前已安装的版本
    current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/{print $3}')
    
    if [ "$current_ver" = "$version" ]; then
        echo -e "${YELLOW}当前已安装版本 $version，无需更新。${NC}"
        return 0
    fi

    # 根据架构，如果返回amd64则实际文件中使用x86_64标识
    if [ "$IPK_ARCH" = "amd64" ]; then
        ipk_arch_label="x86_64"
    else
        ipk_arch_label="$IPK_ARCH"
    fi

    # 获取指定版本的IPK下载地址，要求文件名中包含 "openwrt"、正确的架构标识并以 .ipk结尾
    ipk_url=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
              jq --arg tag "$version" --arg arch "$ipk_arch_label" -r \
              '.[] | select(.tag_name == $tag) | .assets[] | 
              select(.name | contains("openwrt") and contains($arch) and endswith(".ipk")) | .browser_download_url')

    [ -z "$ipk_url" ] && { echo -e "${RED}错误：未找到对应版本的IPK文件${NC}"; return 1; }

    # 下载IPK包
    echo -e "${CYAN}正在下载：${GREEN}$(basename "$ipk_url")${NC}"
    if ! uclient-fetch -qO "$TEMP_DIR/package.ipk" "$ipk_url"; then
        echo -e "${RED}错误：下载失败，请检查网络连接${NC}"
        return 1
    fi

    # 停止sing-box服务（若存在）
    if [ -f /etc/init.d/sing-box ]; then
        echo -e "${CYAN}停止sing-box服务...${NC}"
        /etc/init.d/sing-box stop
    fi

    # 备份当前二进制文件
    backup_file="$BACKUP_DIR/sing-box_$(date +%Y%m%d%H%M).bak"
    cp "$BIN_PATH" "$backup_file" 2>/dev/null
    echo -e "${CYAN}已创建备份：${GREEN}$backup_file${NC}"

    # 使用opkg安装IPK文件，--force-reinstall选项确保对已安装包进行覆盖安装
    echo -e "${CYAN}执行 opkg 安装...${NC}"
    if opkg install --force-reinstall "$TEMP_DIR/package.ipk"; then
        echo -e "${GREEN}IPK安装成功${NC}"
    else
        echo -e "${RED}错误：IPK安装失败，请检查问题${NC}"
        return 1
    fi

    # 启动sing-box服务（若存在）
    if [ -f /etc/init.d/sing-box ]; then
        echo -e "${CYAN}启动sing-box服务...${NC}"
        /etc/init.d/sing-box start
    fi

    # 验证更新后的版本
    new_ver=$($BIN_PATH version 2>/dev/null | awk '/version/{print $3}')
    if [ "$new_ver" = "$version" ]; then
        echo -e "${GREEN}成功更新到版本: $new_ver${NC}"
    else
        echo -e "${RED}更新后版本验证失败，请手动检查${NC}"
        return 1
    fi

    # 清理临时文件
    rm -rf "$TEMP_DIR"/*
}

# 主程序：循环显示菜单，等待用户输入稳定版 (s序号) 或测试版 (b序号) 进行更新，输入q退出
update_singbox() {
    while :; do
        show_menu
        echo -ne "\n${CYAN}输入版本序号 (s-稳定版/b-测试版/q退出): ${NC}"
        read choice
        
        case $choice in
            q|Q)
                break
                ;;
            s*|b*)
                type=${choice:0:1}
                num=${choice:1}
                
                [ -z "$num" ] && {
                    echo -ne "${CYAN}请输入具体序号: ${NC}"
                    read num
                }
                
                if [ "$type" = "s" ]; then
                    version=$(echo "$releases" | jq -r ".stable[$((num-1))]")
                else
                    version=$(echo "$releases" | jq -r ".beta[$((num-1))]")
                fi
                
                [ "$version" = "null" ] && {
                    echo -e "${RED}无效版本选择!${NC}"
                    continue
                }
                
                replace_by_ipk "$version"
                ;;
            *)
                echo -e "${RED}无效输入，请使用 s序号/b序号 格式选择${NC}"
                ;;
        esac
    done
}

update_singbox
