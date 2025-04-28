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

# 文件验证和替换函数（保持原有逻辑）
verify_binary() {
    file "$1" | grep -q "ELF"
}

# 执行文件替换
replace_binary() {
    version=$1
    ipk_url=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
              jq -r ".[] | select(.tag_name == \"$version\") | .assets[] | 
              select(.name | contains(\"openwrt\") and endswith(\".ipk\")) | .browser_download_url")

    [ -z "$ipk_url" ] && { echo -e "${RED}错误：未找到对应版本的IPK文件${NC}"; return 1; }

    # 下载IPK文件
    echo -e "${CYAN}正在下载：${GREEN}$(basename "$ipk_url")${NC}"
    uclient-fetch -qO "$TEMP_DIR/package.ipk" "$ipk_url" || return 1

    # 解压IPK
    echo -e "${CYAN}解压文件中..."
    tar -xzOf "$TEMP_DIR/package.ipk" ./data.tar.gz | tar -xzf - -C "$TEMP_DIR" ./usr/bin/sing-box

    # 验证二进制文件
    if ! verify_binary "$TEMP_DIR/usr/bin/sing-box"; then
        echo -e "${RED}错误：文件校验失败${NC}"
        return 1
    fi

    # 创建备份
    backup_file="$BACKUP_DIR/sing-box_$(date +%Y%m%d%H%M).bak"
    cp "$BIN_PATH" "$backup_file"
    echo -e "${CYAN}已创建备份：${GREEN}$backup_file${NC}"

    # 替换文件
    echo -e "${CYAN}正在替换二进制文件...${NC}"
    mv -f "$TEMP_DIR/usr/bin/sing-box" "$BIN_PATH"
    chmod 755 "$BIN_PATH"

    # 清理临时文件
    rm -rf "$TEMP_DIR"/*
    return 0
}


# 主程序
main() {
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

main
