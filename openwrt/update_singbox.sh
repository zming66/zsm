#!/bin/sh

# OpenWrt专用sing-box更新脚本
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
TEMP_DIR="/tmp/sing-box_update"
BACKUP_DIR="/etc/sing-box/backup"

# 创建必要目录
mkdir -p "$TEMP_DIR" "$BACKUP_DIR"

# 获取设备架构
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

# 获取GitHub版本信息
fetch_releases() {
    uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
    jq -r 'group_by(.prerelease) | 
        {
            "stable": [.[] | select(.prerelease == false) | .tag_name],
            "beta": [.[] | select(.prerelease == true) | .tag_name]
        }'
}

# 显示版本菜单
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

# 文件验证
verify_binary() {
    file "$1" | grep -q "ELF"
}

# 执行更新
replace_binary() {
    version=$1
    current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/{print $3}')
    
    if [ "$current_ver" = "$version" ]; then
        echo -e "${YELLOW}当前已安装版本 $version，无需更新。${NC}"
        return 0
    fi

    ipk_url=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
              jq --arg ipk_arch "$IPK_ARCH" -r \
              ".[] | select(.tag_name == \"$version\") | .assets[] | 
              select(.name | contains(\"openwrt\") and contains(\"$IPK_ARCH\") and endswith(\".ipk\")) | .browser_download_url")

    [ -z "$ipk_url" ] && { echo -e "${RED}错误：未找到对应版本的IPK文件${NC}"; return 1; }

    # 下载IPK
    echo -e "${CYAN}正在下载：${GREEN}$(basename "$ipk_url")${NC}"
    if ! uclient-fetch -qO "$TEMP_DIR/package.ipk" "$ipk_url"; then
        echo -e "${RED}错误：下载失败，请检查网络连接${NC}"
        return 1
    fi

    # 解压文件
    echo -e "${CYAN}解压文件中..."
    if ! tar -xzOf "$TEMP_DIR/package.ipk" ./data.tar.gz | tar -xzf - -C "$TEMP_DIR" ./usr/bin/sing-box; then
        echo -e "${RED}错误：解压失败，文件可能已损坏${NC}"
        return 1
    fi

    # 验证二进制
    if ! verify_binary "$TEMP_DIR/usr/bin/sing-box"; then
        echo -e "${RED}错误：文件校验失败，非有效ELF文件${NC}"
        return 1
    fi

    # 停止服务
    if [ -f /etc/init.d/sing-box ]; then
        echo -e "${CYAN}停止sing-box服务...${NC}"
        /etc/init.d/sing-box stop
    fi

    # 创建备份
    backup_file="$BACKUP_DIR/sing-box_$(date +%Y%m%d%H%M).bak"
    cp "$BIN_PATH" "$backup_file" 2>/dev/null
    echo -e "${CYAN}已创建备份：${GREEN}$backup_file${NC}"

    # 替换文件
    echo -e "${CYAN}更新二进制文件中...${NC}"
    mv -f "$TEMP_DIR/usr/bin/sing-box" "$BIN_PATH" || { 
        echo -e "${RED}错误：文件替换失败，权限不足？${NC}"
        return 1
    }
    chmod 755 "$BIN_PATH"

    # 启动服务
    if [ -f /etc/init.d/sing-box ]; then
        echo -e "${CYAN}启动sing-box服务...${NC}"
        /etc/init.d/sing-box start
    fi

    # 验证版本
    new_ver=$($BIN_PATH version 2>/dev/null | awk '/version/{print $3}')
    if [ "$new_ver" = "$version" ]; then
        echo -e "${GREEN}成功更新到版本: $new_ver${NC}"
    else
        echo -e "${RED}更新后版本验证失败，请手动检查${NC}"
        return 1
    fi

    rm -rf "$TEMP_DIR"/*
}

# 主程序
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
                
                replace_binary "$version"
                ;;
            *)
                echo -e "${RED}无效输入，请使用 s序号/b序号 格式选择${NC}"
                ;;
        esac
    done
}

update_singbox
