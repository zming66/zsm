#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 检查 sing-box 是否已安装
if ! command -v sing-box &> /dev/null; then
    echo -e "${RED}sing-box 未安装，请先安装${NC}"
    bash /etc/sing-box/scripts/install_singbox.sh
    exit 1
fi

# 确保配置目录和 mode.conf 文件存在
mkdir -p /etc/sing-box/
[ -f /etc/sing-box/mode.conf ] || touch /etc/sing-box/mode.conf
chmod 600 /etc/sing-box/mode.conf

echo -e "${CYAN}切换模式开始...请根据提示输入操作。${NC}"

while true; do
    # 选择模式
    read -rp "请选择模式(1: TProxy 模式, 2: TUN 模式): " mode_choice

    # 停止 sing-box 服务
    /etc/init.d/sing-box stop

    case $mode_choice in
        1)
            echo "MODE=TProxy" > /etc/sing-box/mode.conf
            echo -e "${GREEN}当前选择模式为: TProxy 模式${NC}"
            
            # 应用 TProxy 防火墙规则
            if [ -f /etc/sing-box/scripts/configure_tproxy.sh ]; then
                bash /etc/sing-box/scripts/configure_tproxy.sh
                echo -e "${GREEN}TProxy 防火墙规则已应用${NC}"
            fi
            break
            ;;
        2)
            echo "MODE=TUN" > /etc/sing-box/mode.conf
            echo -e "${GREEN}当前选择模式为: TUN 模式${NC}"
            
            # 应用 TUN 防火墙规则
            if [ -f /etc/sing-box/scripts/configure_tun.sh ]; then
                bash /etc/sing-box/scripts/configure_tun.sh
                echo -e "${GREEN}TUN 防火墙规则已应用${NC}"
            fi
            break
            ;;
        *)
            echo -e "${RED}无效的选择，请重新输入。${NC}"
            ;;
    esac
done

# 启动 sing-box 服务
/etc/init.d/sing-box start
if /etc/init.d/sing-box status | grep -q "running"; then
    echo -e "${GREEN}sing-box 已成功启动${NC}"
else
    echo -e "${RED}sing-box 启动失败，请检查日志${NC}"
fi
