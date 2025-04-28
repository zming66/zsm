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

replace_binary() {
    # ...（保持原有文件下载和替换逻辑不变）...
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
