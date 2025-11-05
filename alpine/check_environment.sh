#!/bin/ash
# ==============================================
# 功能: 检查 sing-box 是否安装及版本信息
# 支持系统: Alpine / Debian / Ubuntu / OpenWRT
# ==============================================

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误: 此脚本需要 root 权限运行。"
    exit 1
fi

# 检查 sing-box 是否已安装
if command -v sing-box >/dev/null 2>&1; then
    version_output=$(sing-box version 2>/dev/null)
    current_version=$(echo "$version_output" | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)
    
    if [ -n "$current_version" ]; then
        echo "✅ sing-box 已安装，版本：$current_version"
    else
        echo "⚠️  已检测到 sing-box，但无法识别版本号。"
        echo "版本信息输出如下："
        echo "$version_output"
    fi
else
    echo "🚫 sing-box 未安装。"
    echo "可执行以下命令进行安装（以 Alpine 为例）："
    echo ""
    echo "   apk add sing-box"
    echo ""
fi
