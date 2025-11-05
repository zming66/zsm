#!/bin/ash
# Alpine Linux 适配版：TUN 模式防火墙规则应用脚本

PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')

# 读取当前模式
MODE=$(grep -E '^MODE=' /etc/sing-box/mode.conf 2>/dev/null | sed 's/^MODE=//')

# 清理 TProxy 模式的防火墙规则
clearTProxyRules() {
    if command -v nft >/dev/null 2>&1; then
        nft list table inet sing-box >/dev/null 2>&1 && nft delete table inet sing-box
    fi
    ip rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null
    ip route del local default dev "$INTERFACE" table $PROXY_ROUTE_TABLE 2>/dev/null
    echo "✅ 清理 TProxy 模式的防火墙规则完成"
}

if [ "$MODE" = "TUN" ]; then
    echo "应用 TUN 模式下的防火墙规则..."

    # 清理 TProxy 模式的防火墙规则
    clearTProxyRules

    # 确保目录存在
    mkdir -p /etc/sing-box/tun

    # 设置 TUN 模式的基础 nftables 配置
    cat > /etc/sing-box/tun/nftables.conf <<EOF
table inet sing-box {
    chain input {
        type filter hook input priority 0; policy accept;
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    # 应用防火墙规则
    if command -v nft >/dev/null 2>&1; then
        nft -f /etc/sing-box/tun/nftables.conf
        # 持久化规则
        nft list ruleset > /etc/nftables.conf
        echo "✅ TUN 模式的防火墙规则已应用"
    else
        echo "⚠️ 系统未安装 nftables，无法应用防火墙规则"
    fi

else
    echo "ℹ️ 当前模式不是 TUN 模式，跳过防火墙规则配置"
fi
