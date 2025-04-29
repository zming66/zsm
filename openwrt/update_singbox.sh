#!/bin/sh
# OpenWrt sing-box 精简安装脚本

# =====================
# 配置区（按需修改）
# =====================
REPO="SagerNet/sing-box"         # GitHub仓库
BIN_PATH="/usr/bin/sing-box"     # 可执行文件路径
TEMP_DIR="/tmp/sing-box_update"  # 临时目录
MAX_RETRY=3                      # 下载最大重试次数

# =====================
# 颜色定义
# =====================
CYAN='\033[0;36m'
GREEN='\033[0;32m'
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
  [ -f "/etc/init.d/sing-box" ] && {
    echo -e "${CYAN}停止服务...${NC}"
    /etc/init.d/sing-box stop
  }

  # 卸载旧版
  echo -e "${CYAN}卸载旧版本...${NC}"
  opkg remove sing-box

  # 安装新版
  echo -e "${CYAN}开始安装...${NC}"
  if opkg install "$TEMP_DIR/sing-box.ipk"; then
    echo -e "${GREEN}✓ 安装成功${NC}"
    
    # 清理残留文件
    echo -e "${CYAN}清理旧版本残留...${NC}"
    rm -f "/etc/init.d/sing-box-opkg" \
        "/etc/sing-box/config.json-opkg" \
        "$TEMP_DIR/sing-box.ipk"
    
    # 启动服务
    [ -f "/etc/init.d/sing-box" ] && {
      echo -e "${CYAN}启动服务...${NC}"
      /etc/init.d/sing-box start
    }
  else
    echo -e "${RED}✗ 安装失败${NC}"
    return 1
  fi
}

# =====================
# 用户界面
# =====================
show_menu() {
  clear
  current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
  stable=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | jq -r '[.[] | select(.prerelease == false)][0].tag_name')
  beta=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | jq -r '[.[] | select(.prerelease == true)][0].tag_name')
  
  echo -e "\n${CYAN}======= Sing-box 更新助手 ======="
  echo -e "[当前版本] ${GREEN}${current_ver:-未安装}${NC}"
  echo -e "\n${CYAN}1) 稳定版: $stable"
  echo -e "2) 测试版: $beta${NC}"
  echo -e "\n${RED}0) 退出${NC}"
  
  echo -ne "\n${CYAN}请选择 (1/2/0): ${NC}"
  read -r choice
  
  case $choice in
    1) install_version "$stable" ;;
    2) install_version "$beta" ;;
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
  mkdir -p "$TEMP_DIR"
  show_menu
  rm -rf "$TEMP_DIR"
}

singbox
