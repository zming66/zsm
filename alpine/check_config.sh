#!/bin/ash
# ==============================================
# 功能: 检查 sing-box 配置文件是否存在并验证有效性
# 适用: Alpine Linux / OpenWRT / Debian 等轻量系统
# ==============================================

# 定义颜色
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

CONFIG_FILE="/etc/sing-box/config.json"

# 检查 sing-box 是否安装
if ! command -v sing-box >/dev/null 2>&1; then
    echo -e "${RED}未检测到 sing-box，请先安装。${NC}"
    exit 1
fi

# 检查配置文件是否存在
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${CYAN}检查配置文件: ${CONFIG_FILE} ...${NC}"
    
    # 验证配置文件
    if sing-box check -c "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${CYAN}✅ 配置文件验证通过！${NC}"
        exit 0
    else
        echo -e "${RED}❌ 配置文件验证失败，请检查语法或内容。${NC}"
        exit 1
    fi
else
    echo -e "${RED}⚠️ 配置文件 ${CONFIG_FILE} 不存在！${NC}"
    exit 1
fi
