#!/bin/sh
# OpenWrt sing-box 更新修复版脚本

# =====================
# 配置区（按需修改）
# =====================
REPO="SagerNet/sing-box"
BIN_PATH="/usr/bin/sing-box"
TEMP_DIR="/tmp/sing-box_update"
BACKUP_DIR="/etc/sing-box/backup"
MAX_RETRY=3  # 下载最大重试次数

# =====================
# 颜色定义
# =====================
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# =====================
# 依赖检查
# =====================
check_dependencies() {
  for cmd in jq uclient-fetch opkg; do
    if ! command -v $cmd >/dev/null; then
      echo -e "${RED}错误：缺少必要依赖 $cmd${NC}"
      exit 1
    fi
  done
}

# =====================
# 增强版架构检测
# =====================
determine_arch() {
  case $(uname -m) in
    x86_64)  echo "x86_64" ;;
    aarch64) echo "arm64"  ;;
    armv7l)  echo "armv7"  ;;
    *)       echo "$(uname -m)" ;;
  esac
}

# =====================
# 智能版本获取
# =====================
get_latest_versions() {
  releases=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" || {
    echo -e "${RED}错误：无法获取版本信息${NC}"
    exit 1
  })
  
  stable=$(echo "$releases" | jq -r '[.[] | select(.prerelease == false)][0].tag_name')
  beta=$(echo "$releases" | jq -r '[.[] | select(.prerelease == true)][0].tag_name')
  
  echo "$stable $beta"
}

# =====================
# 增强安装逻辑
# =====================
install_version() {
  version=$1
  [ -z "$version" ] && return 1

  # 架构处理
  arch=$(determine_arch)
  case $arch in
    x86_64) search_arch="x86_64" ;;
    arm64)  search_arch="arm64"  ;;
    *)      search_arch="$arch"  ;;
  esac

  # 获取下载链接
  ipk_url=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
    jq -r --arg ver "$version" --arg arch "$search_arch" \
    '.[] | select(.tag_name == $ver).assets[] | 
    select(.name | contains("openwrt") and contains($arch) and endswith(".ipk")).browser_download_url')

  [ -z "$ipk_url" ] && {
    echo -e "${RED}未找到 $version 的IPK文件${NC}"
    return 1
  }

  # 服务管理增强
  if [ -f "/etc/init.d/sing-box" ]; then
    echo -e "${CYAN}停止运行中的服务...${NC}"
    /etc/init.d/sing-box stop || echo -e "${YELLOW}服务停止失败，继续安装${NC}"
  else
    echo -e "${YELLOW}未找到服务文件，跳过停止服务步骤${NC}"
  fi

  # 下载重试机制
  mkdir -p "$TEMP_DIR"
  retry=0
  while [ $retry -lt $MAX_RETRY ]; do
    echo -e "${CYAN}正在下载: ${GREEN}$(basename "$ipk_url")${NC} (尝试: $((retry+1))/$MAX_RETRY)"
    if uclient-fetch -qO "$TEMP_DIR/sing-box.ipk" "$ipk_url"; then
      break
    else
      retry=$((retry+1))
      sleep 3
    fi
  done
  [ $retry -eq $MAX_RETRY ] && {
    echo -e "${RED}下载失败，请检查网络连接${NC}"
    return 1
  }

  # 备份增强
  [ -f "$BIN_PATH" ] && {
    backup_file="$BACKUP_DIR/sing-box_$(date +%Y%m%d%H%M%S).bak"
    mkdir -p "$BACKUP_DIR"
    cp "$BIN_PATH" "$backup_file"
    echo -e "${CYAN}已备份旧版本至: ${YELLOW}$backup_file${NC}"
  }

  # 安装流程
  echo -e "${CYAN}开始安装操作...${NC}"
  opkg remove sing-box >/dev/null 2>&1
  if opkg install --force-reinstall "$TEMP_DIR/sing-box.ipk"; then
    echo -e "${GREEN}✓ 安装成功${NC}"
    # 版本验证
    new_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
    if [ "$new_ver" = "$version" ]; then
      echo -e "${GREEN}当前版本: $new_ver${NC}"
    else
      echo -e "${YELLOW}版本验证异常，请手动确认${NC}"
    fi
  else
    echo -e "${RED}✗ 安装失败${NC}"
    return 1
  fi

  # 服务启动增强
  if [ -f "/etc/init.d/sing-box" ]; then
    echo -e "${CYAN}启动服务...${NC}"
    /etc/init.d/sing-box start || echo -e "${RED}服务启动失败，请手动检查${NC}"
  fi
}

# =====================
# 交互界面优化
# =====================
show_menu() {
  clear
  current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
  IFS=' ' read -r stable_ver beta_ver <<< "$(get_latest_versions)"
  
  echo -e "\n${CYAN}======= Sing-box 更新助手 =======${NC}"
  echo -e "[当前版本] ${GREEN}${current_ver:-未安装}${NC}"
  echo -e "\n${CYAN}可用版本：${NC}"
  echo -e "1) ${GREEN}稳定版: $stable_ver${NC}"
  echo -e "2) ${YELLOW}测试版: $beta_ver${NC}"
  echo -e "\nq) 退出"
  
  echo -ne "\n${CYAN}请选择 (1/2/q): ${NC}"
  read -r choice
  
  case $choice in
    1) install_version "$stable_ver" ;;
    2) install_version "$beta_ver" ;;
    q) exit 0 ;;
    *) 
      echo -e "${RED}无效输入，请重新选择${NC}"
      sleep 1
      show_menu
      ;;
  esac
}

# =====================
# 主程序
# =====================
singbox() {
  check_dependencies
  mkdir -p "$TEMP_DIR" "$BACKUP_DIR"
  chmod 755 "$TEMP_DIR"  # 确保临时目录权限
  show_menu
  rm -rf "$TEMP_DIR"
}

singbox
