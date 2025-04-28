#!/bin/sh
# OpenWrt sing-box 极简更新脚本（仅显示最新稳定版+测试版）

# =====================
# 配置参数（按需修改）
# =====================
REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
TEMP_DIR="/tmp/sing-box_update"

# 颜色定义
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 依赖检查
check_deps() {
  for cmd in jq uclient-fetch opkg; do
    command -v $cmd >/dev/null || {
      echo -e "${RED}错误：缺少依赖 $cmd${NC}"
      exit 1
    }
  done
}

# 架构检测
get_arch() {
  case $(uname -m) in
    x86_64) echo "x86_64" ;;
    aarch64) echo "arm64" ;;
    armv7l) echo "armv7" ;;
    *) echo "$(uname -m)" ;;
  esac
}

# 获取最新版本
fetch_versions() {
  releases=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases")
  
  latest_stable=$(echo "$releases" | jq -r '[.[] | select(.prerelease == false)][0].tag_name')
  latest_beta=$(echo "$releases" | jq -r '[.[] | select(.prerelease == true)][0].tag_name')
  
  echo "$latest_stable $latest_beta"
}

# 安装逻辑
install_version() {
  version=$1
  arch=$(get_arch)
  
  # 查找对应IPK
  ipk_url=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
    jq -r --arg ver "$version" --arg arch "$arch" \
    '.[] | select(.tag_name == $ver).assets[] | 
    select(.name | contains("openwrt") and contains($arch) and endswith(".ipk")).browser_download_url')

  [ -z "$ipk_url" ] && {
    echo -e "${RED}未找到 $version 的IPK文件${NC}"
    return 1
  }

  # 下载安装
  echo -e "${CYAN}正在下载: $(basename "$ipk_url")${NC}"
  uclient-fetch -qO "$TEMP_DIR/sing-box.ipk" "$ipk_url" || return 1
  
  # 清除旧版
  [ -f "/etc/init.d/sing-box" ] && /etc/init.d/sing-box stop
  opkg remove sing-box >/dev/null 2>&1
  
  # 安装新版
  if opkg install --force-reinstall "$TEMP_DIR/sing-box.ipk"; then
    echo -e "${GREEN}安装成功! 版本: $($BIN_PATH version | awk '{print $3}')${NC}"
    [ -f "/etc/init.d/sing-box" ] && /etc/init.d/sing-box start
  else
    echo -e "${RED}安装失败，请检查日志${NC}"
  fi
}

# 主菜单
main_menu() {
  current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
  IFS=' ' read -r stable_ver beta_ver <<< "$(fetch_versions)"
  
  echo -e "\n${CYAN}=== 当前版本 ===${NC}"
  [ -n "$current_ver" ] && echo -e "${GREEN}$current_ver${NC}" || echo -e "${RED}未安装${NC}"
  
  echo -e "\n${CYAN}=== 最新版本 ===${NC}"
  echo -e "1) ${GREEN}$stable_ver (稳定版)${NC}"
  echo -e "2) ${YELLOW}$beta_ver (测试版)${NC}"
  
  echo -ne "\n${CYAN}请选择 (1/2/q): ${NC}"
  read -r choice
  
  case $choice in
    1) install_version "$stable_ver" ;;
    2) install_version "$beta_ver" ;;
    q) exit 0 ;;
    *) echo -e "${RED}无效输入${NC}" ;;
  esac
}

# 执行流程
check_deps
mkdir -p "$TEMP_DIR"
main_menu
rm -rf "$TEMP_DIR"
