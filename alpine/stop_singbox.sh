#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 脚本下载目录
SCRIPT_DIR="/etc/sing-box/scripts"

# 检查 sing-box 服务是否存在
if [ ! -f /etc/init.d/sing-box ]; then
    echo -e "${RED}错误: sing-box 服务未找到，请先安装${NC}"
    exit 1
fi

# 停止 sing-box 服务
stop_singbox() {
    echo -e "${CYAN}正在停止 sing-box 服务...${NC}"
    /etc/init.d/sing-box stop
    result=$?
    if [ $result -ne 0 ]; then
        echo -e "${YELLOW}停止 sing-box 服务可能已停止或出现异常，返回码: $result${NC}"
    else
        echo -e "${GREEN}sing-box 已成功停止。${NC}"
    fi

    # 提示是否清理防火墙规则
    read -rp "是否清理防火墙规则？(y/n): " confirm_cleanup
    if [[ "$confirm_cleanup" =~ ^[Yy]$ ]]; then
        if [ -f "$SCRIPT_DIR/clean_nft.sh" ]; then
            echo -e "${CYAN}执行清理防火墙规则...${NC}"
            bash "$SCRIPT_DIR/clean_nft.sh"
            echo -e "${GREEN}防火墙规则清理完毕${NC}"
        else
            echo -e "${RED}未找到清理脚本 $SCRIPT_DIR/clean_nft.sh${NC}"
        fi
    else
        echo -e "${CYAN}已取消清理防火墙规则。${NC}"
    fi
}

# 主逻辑
read -rp "是否停止 sing-box?(y/n): " confirm_stop
if [[ "$confirm_stop" =~ ^[Yy]$ ]]; then
    stop_singbox
else
    echo -e "${CYAN}已取消停止 sing-box。${NC}"
    exit 0
fi
