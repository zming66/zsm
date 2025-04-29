#!/bin/sh
# OpenWrt sing-box 自动更新脚本（含智能清理）

# =====================
# 配置区（按需修改）
# =====================
REPO="SagerNet/sing-box"         # GitHub仓库
BIN_PATH="/usr/bin/sing-box"     # 可执行文件路径
TEMP_DIR="/tmp/sing-box_update"  # 临时目录
BACKUP_DIR="/etc/sing-box/backup" # 备份目录
MAX_RETRY=3                      # 下载最大重试次数
KEEP_BACKUPS=1                   # 保留的旧备份数量

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
# 架构检测
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
# 获取最新版本
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
# 清理旧备份
# =====================
clean_old_backups() {
  echo -e "${CYAN}正在清理旧备份...${NC}"
  # 获取按时间倒序的备份列表
  backup_files=$(ls -t "$BACKUP_DIR"/sing-box_*.bak 2>/dev/null)
  
  # 计算需要删除的数量
  total=$(echo "$backup_files" | wc -w)
  if [ $total -gt $KEEP_BACKUPS ]; then
    to_delete=$((total - KEEP_BACKUPS))
    echo "$backup_files" | tail -n $to_delete | while read -r file; do
      echo -e "删除旧备份: ${YELLOW}$(basename "$file")${NC}"
      rm -f "$file"
    done
  else
    echo -e "${GREEN}当前备份数 $total ≤ 保留数 $KEEP_BACKUPS，无需清理${NC}"
  fi
}

# =====================
# 安装流程核心
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

  # 下载流程
  mkdir -p "$TEMP_DIR"
  retry=0
  while [ $retry -lt $MAX_RETRY ]; do
    echo -e "${CYAN}下载尝试: $((retry+1))/$MAX_RETRY${NC}"
    if uclient-fetch -qO "$TEMP_DIR/sing-box.ipk" "$ipk_url"; then
      echo -e "${GREEN}✓ 下载成功${NC}"
      break
    fi
    retry=$((retry+1))
    sleep 3
  done

  [ $retry -eq $MAX_RETRY ] && {
    echo -e "${RED}✗ 下载失败，终止流程${NC}"
    return 1
  }

  # 停止服务
  if [ -f "/etc/init.d/sing-box" ]; then
    echo -e "${CYAN}停止服务...${NC}"
    /etc/init.d/sing-box stop || echo -e "${YELLOW}服务停止失败，继续安装${NC}"
  else
    echo -e "${YELLOW}未找到服务文件，跳过停止${NC}"
  fi

  # 备份旧版
  [ -f "$BIN_PATH" ] && {
    backup_file="$BACKUP_DIR/sing-box_$(date +%Y%m%d%H%M%S).bak"
    mkdir -p "$BACKUP_DIR"
    cp "$BIN_PATH" "$backup_file"
    echo -e "${CYAN}已备份: ${YELLOW}$(basename "$backup_file")${NC}"
    clean_old_backups
  }

  # 安装流程
  echo -e "${CYAN}开始安装...${NC}"
  opkg remove sing-box >/dev/null 2>&1
  if opkg install --force-reinstall "$TEMP_DIR/sing-box.ipk"; then
    echo -e "${GREEN}✓ 安装成功${NC}"

    # 清理冲突文件
    CONFIG_BACKUPS=(
      "/etc/init.d/sing-box-opkg"
      "/etc/sing-box/config.json-opkg"
    )
    for file in "${CONFIG_BACKUPS[@]}"; do
      [ -f "$file" ] && {
        echo -e "${CYAN}清理残留: ${YELLOW}$(basename "$file")${NC}"
        rm -f "$file"
      }
    done

    # 版本验证
    new_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
    if [ "$new_ver" = "$version" ]; then
      echo -e "${GREEN}当前版本: $new_ver${NC}"
    else
      echo -e "${YELLOW}版本验证异常，尝试重启服务...${NC}"
      [ -f "/etc/init.d/sing-box" ] && /etc/init.d/sing-box restart
    fi
  else
    echo -e "${RED}✗ 安装失败${NC}"
    return 1
  fi

  # 启动服务
  [ -f "/etc/init.d/sing-box" ] && {
    echo -e "${CYAN}启动服务...${NC}"
    /etc/init.d/sing-box start
  }
}

# =====================
# 用户界面
# =====================
show_menu() {
  clear
  current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
  IFS=' ' read -r stable_ver beta_ver <<< "$(get_latest_versions)"
  
  echo -e "\n${CYAN}======= Sing-box 更新助手 ======="
  echo -e "[当前版本] ${GREEN}${current_ver:-未安装}${NC}"
  echo -e "\n${CYAN}1) 稳定版: $stable_ver"
  echo -e "2) 测试版: $beta_ver${NC}"
  echo -e "\n${YELLOW}0) 退出${NC}"
  
  echo -ne "\n${CYAN}请选择 (1/2/0): ${NC}"
  read -r choice
  
  case $choice in
    1) install_version "$stable_ver" ;;
    2) install_version "$beta_ver" ;;
    0) exit 0 ;;
    *) 
      echo -e "${RED}无效输入，2秒后重试...${NC}"
      sleep 2
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
  show_menu
  rm -rf "$TEMP_DIR"
}

singbox
