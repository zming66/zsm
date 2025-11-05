#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 检查当前模式
check_mode() {
    if nft list chain inet sing-box prerouting_tproxy &>/dev/null || nft list chain inet sing-box output_tproxy &>/dev/null; then
        echo "TProxy"
    else
        echo "TUN"
    fi
}

# 启动 sing-box 服务
start_singbox() {
    echo -e "${CYAN}检测网络直连状态...${NC}"
    STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://www.google.com")

    if [ "$STATUS_CODE" -eq 200 ]; then
        echo -e "${YELLOW}检测到网络可直连（非代理环境）${NC}"
    else
        echo -e "${RED}网络可能处于代理环境或无法访问 Google，启动 sing-box 可能受影响${NC}"
    fi

    echo -e "${CYAN}正在启动 sing-box 服务...${NC}"
    /etc/init.d/sing-box start
    sleep 2  # 等待服务启动

    if /etc/init.d/sing-box status | grep -q "running"; then
        echo -e "${GREEN}sing-box 启动成功${NC}"
        mode=$(check_mode)
        echo -e "${MAGENTA}当前启动模式: ${mode}${NC}"
    else
        echo -e "${RED}sing-box 启动失败，请检查日志${NC}"
    fi
}

# 提示用户确认是否启动
read -rp "是否启动 sing-box?(y/n): " confirm_start
if [[ "$confirm_start" =~ ^[Yy]$ ]]; then
    start_singbox
else
    echo -e "${CYAN}已取消启动 sing-box。${NC}"
    exit 0
fi
