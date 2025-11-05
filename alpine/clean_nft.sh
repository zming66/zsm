#!/bin/ash
# ==============================================
# 功能: 清理 sing-box 的 nftables 防火墙规则
# 适用: Alpine / Debian / OpenWRT 等使用 nft 的系统
# ==============================================

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误: 此脚本需要 root 权限运行。"
    exit 1
fi

# 检查 nft 是否安装
if ! command -v nft >/dev/null 2>&1; then
    echo "⚠️  系统未安装 nftables，请先执行："
    echo "   apk add nftables"
    exit 1
fi

# 检查 sing-box 表是否存在
if nft list tables | grep -q "sing-box"; then
    if nft list table inet sing-box >/dev/null 2>&1; then
        nft delete table inet sing-box
        echo "✅ sing-box 防火墙规则已清理。"
    else
        echo "⚠️  找到 sing-box 表，但删除时发生问题。"
    fi
else
    echo "ℹ️ 未找到 sing-box 相关防火墙规则，无需清理。"
fi

# 可选：停止 sing-box 服务（若使用 OpenRC）
if rc-service sing-box status >/dev/null 2>&1; then
    rc-service sing-box stop
    echo "🛑 sing-box 服务已停止。"
fi
