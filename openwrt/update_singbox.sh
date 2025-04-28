#!/bin/sh
# OpenWrt 环境下 sing-box 自动更新脚本（支持最新稳定版和最新测试版）
# 本脚本解决了 GitHub API 访问限制问题：支持访问令牌与缓存，
# 并提供稳定版（L 选项）与测试版（P 选项）的安装选择

# =====================
# 配置参数（按需修改）
# =====================
REPO="SagerNet/sing-box"         # GitHub 仓库名
BIN_PATH="/usr/bin/sing-box"      # 可执行文件路径
TEMP_DIR="/tmp/sing-box_update"   # 临时下载目录
BACKUP_DIR="/etc/sing-box/backup" # 备份目录

# GitHub 访问令牌（可选，提高 API 调用配额；没配置时请留空）
GITHUB_TOKEN=""

# API 缓存时间（单位：秒，建议设置为 600 即 10 分钟）
CACHE_TTL=600

# =====================
# 颜色定义
# =====================
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# =====================
# 依赖检查（需安装 jq、uclient-fetch、opkg、md5sum 与 stat）
# =====================
check_dependencies() {
  for cmd in jq uclient-fetch opkg md5sum stat; do
    if ! command -v $cmd >/dev/null; then
      echo -e "${RED}错误：缺少依赖 $cmd，请先安装${NC}"
      exit 1
    fi
  done
}

# =====================
# 架构检测（根据 uname -m 输出判断系统架构）
# =====================
determine_ipk_arch() {
  case "$(uname -m)" in
    x86_64) echo "x86_64" ;;   # OpenWrt 中 amd64 对应 x86_64
    aarch64) echo "arm64" ;;
    armv7l) echo "armv7"  ;;
    *) echo "$(uname -m)" ;;
  esac
}

# =====================
# GitHub API 请求封装函数
# 使用访问令牌（如果已配置）并对返回结果进行缓存（缓存文件存放于 /tmp，文件名基于 URL 的 md5）
# =====================
fetch_api() {
  local url="$1"
  local cache_file="/tmp/github_api_$(echo -n "$url" | md5sum | awk '{print $1}').json"
  local now
  now=$(date +%s)
  
  if [ -f "$cache_file" ]; then
    local mod_time
    mod_time=$(stat -c %Y "$cache_file")
    if [ $(( now - mod_time )) -lt "$CACHE_TTL" ]; then
      cat "$cache_file"
      return
    fi
  fi
  
  local result
  if [ -n "$GITHUB_TOKEN" ]; then
    result=$(uclient-fetch -qO- -H "Authorization: token $GITHUB_TOKEN" "$url" 2>/dev/null)
  else
    result=$(uclient-fetch -qO- "$url" 2>/dev/null)
  fi
  
  echo "$result" > "$cache_file"
  echo "$result"
}

# =====================
# 获取版本信息：同时获取最新稳定版与最新测试版
# 稳定版通过 /releases/latest 获取，测试版从 /releases 数据中过滤 prerelease==true 的首个项获取
# =====================
fetch_releases() {
  local stable_url="https://api.github.com/repos/$REPO/releases/latest"
  local stable_json
  stable_json=$(fetch_api "$stable_url")
  local latest_stable
  latest_stable=$(echo "$stable_json" | jq -r '.tag_name')
  
  local all_url="https://api.github.com/repos/$REPO/releases"
  local all_json
  all_json=$(fetch_api "$all_url")
  local latest_beta
  latest_beta=$(echo "$all_json" | jq -r '[.[] | select(.prerelease == true)][0].tag_name')
  
  echo "{\"stable\": \"${latest_stable}\", \"beta\": \"${latest_beta}\"}"
}

# =====================
# 显示交互菜单（显示当前版本、最新稳定版和最新测试版）
# =====================
show_menu() {
  current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
  releases=$(fetch_releases)
  latest_stable=$(echo "$releases" | jq -r '.stable')
  latest_beta=$(echo "$releases" | jq -r '.beta')
  
  echo -e "\n${CYAN}=== 当前版本 ===${NC}"
  if [ -n "$current_ver" ]; then
    echo -e "${GREEN}$current_ver${NC}"
  else
    echo -e "${RED}未安装${NC}"
  fi

  echo -e "\n${CYAN}=== 最新稳定版 ===${NC}"
  if [ -n "$latest_stable" ] && [ "$latest_stable" != "null" ]; then
    echo -e "  ${GREEN}$latest_stable (Latest Stable)${NC}"
  else
    echo -e "${YELLOW}无可用稳定版${NC}"
  fi

  echo -e "\n${CYAN}=== 最新测试版 ===${NC}"
  if [ -n "$latest_beta" ] && [ "$latest_beta" != "null" ]; then
    echo -e "  ${YELLOW}$latest_beta (Latest Beta)${NC}"
  else
    echo -e "${YELLOW}无可用测试版${NC}"
  fi

  echo -e "\n${CYAN}快捷安装：${NC}"
  echo -e "  ${GREEN}L) 安装最新稳定版 (${latest_stable})${NC}"
  echo -e "  ${YELLOW}P) 安装最新测试版 (${latest_beta})${NC}"
}

# =====================
# 下载与安装 IPK 包逻辑（根据指定版本从 GitHub Releases 中查找对应 openwrt IPK 文件并安装）
# =====================
replace_by_ipk() {
  version=$1
  [ -z "$version" ] && return 1
  
  current_ver=$($BIN_PATH version 2>/dev/null | awk '{print $3}')
  if [ "$current_ver" = "$version" ]; then
    echo -e "${YELLOW}已是最新版本${NC}"
    return 0
  fi
  
  IPK_ARCH=$(determine_ipk_arch)
  case "$IPK_ARCH" in
    x86_64) search_arch="x86_64" ;;
    arm64) search_arch="arm64"   ;;
    *) search_arch="$IPK_ARCH"   ;;
  esac
  
  # 通过全部 releases 接口查找指定版本的 IPK 文件（含 openwrt 和架构判断）
  local all_api_url="https://api.github.com/repos/$REPO/releases"
  all_releases=$(fetch_api "$all_api_url")
  asset_url=$(echo "$all_releases" | jq -r --arg ver "$version" --arg arch "$search_arch" '
    .[] | select(.tag_name == $ver) |
    .assets[] | select(.name | contains("openwrt") and contains($arch) and endswith(".ipk")) |
    .browser_download_url
  ')
  
  [ -z "$asset_url" ] && echo -e "${RED}未找到对应架构的 IPK 文件${NC}" && return 1
  
  echo -e "${CYAN}下载 IPK 包...${NC}"
  mkdir -p "$TEMP_DIR"
  uclient-fetch -qO "$TEMP_DIR/sing-box.ipk" "$asset_url" || return 1
  
  # 停止服务（如果存在）
  [ -f "/etc/init.d/sing-box" ] && /etc/init.d/sing-box stop
  
  # 备份当前版本（如果存在）
  if [ -f "$BIN_PATH" ]; then
    backup_file="$BACKUP_DIR/sing-box_$(date +%s).bak"
    cp "$BIN_PATH" "$backup_file"
    echo -e "${CYAN}已备份旧版本至: ${backup_file}${NC}"
  fi
  
  echo -e "${CYAN}执行安装...${NC}"
  opkg install --force-reinstall "$TEMP_DIR/sing-box.ipk"
  
  # 启动服务（如果存在）
  [ -f "/etc/init.d/sing-box" ] && /etc/init.d/sing-box start
  
  new_ver=$($BIN_PATH version 2>/dev/null | awk '{print $3}')
  if [ "$new_ver" = "$version" ]; then
    echo -e "${GREEN}更新成功! 新版本: $new_ver${NC}"
  else
    echo -e "${RED}版本验证失败，请手动检查${NC}"
  fi
}

# =====================
# 主程序入口
# =====================
singbox() {
  check_dependencies
  mkdir -p "$TEMP_DIR" "$BACKUP_DIR"
  
  while :; do
    show_menu
    echo -ne "\n${CYAN}请选择选项 (L/P/q): ${NC}"
    read choice
    
    case $choice in
      q|Q)
        break
        ;;
      l|L)
        releases=$(fetch_releases)
        version=$(echo "$releases" | jq -r '.stable')
        if [ -n "$version" ] && [ "$version" != "null" ]; then
          replace_by_ipk "$version"
        else
          echo -e "${RED}无法获取最新稳定版信息${NC}"
        fi
        ;;
      p|P)
        releases=$(fetch_releases)
        version=$(echo "$releases" | jq -r '.beta')
        if [ -n "$version" ] && [ "$version" != "null" ]; then
          replace_by_ipk "$version"
        else
          echo -e "${RED}无法获取最新测试版信息${NC}"
        fi
        ;;
      *)
        echo -e "${RED}无效输入${NC}"
        ;;
    esac
  done
  
  rm -rf "$TEMP_DIR"
}

singbox
