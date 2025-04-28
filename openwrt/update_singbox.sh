#!/bin/sh
# OpenWrt 环境下 sing-box 自动更新脚本（支持 Latest 稳定版和 Pre-release 测试版）

# =====================
# 配置参数（按需修改）
# =====================
REPO="SagerNet/sing-box"         # GitHub 仓库名
BIN_PATH="/usr/bin/sing-box"     # 可执行文件路径
TEMP_DIR="/tmp/sing-box_update"  # 临时下载目录
BACKUP_DIR="/etc/sing-box/backup" # 备份目录

# 颜色定义
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 依赖检查
check_dependencies() {
  for cmd in jq uclient-fetch opkg; do
    if ! command -v $cmd >/dev/null; then
      echo -e "${RED}错误：缺少依赖 $cmd，请先安装${NC}"
      exit 1
    fi
  done
}

# 架构检测
determine_ipk_arch() {
  case "$(uname -m)" in
    x86_64) echo "x86_64" ;;   # OpenWrt 中 amd64 对应 x86_64
    aarch64) echo "arm64" ;;
    armv7l) echo "armv7"  ;;
    *) echo "$(uname -m)" ;;
  esac
}

# 获取版本信息
fetch_releases() {
  # 获取全量发布数据
  releases_json=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" 2>/dev/null)
  
  # 手动提取最新稳定版（取第一个非预发布版本）
  latest_stable=$(echo "$releases_json" | jq -r '[.[] | select(.prerelease == false) | .tag_name][0]')
  
  # 重构返回数据
  echo "$releases_json" | jq --arg lt "$latest_stable" -r '
    {
      latest: $lt,
      stable: [.[] | select(.prerelease == false) | .tag_name],
      beta: [.[] | select(.prerelease == true) | .tag_name]
    }
  '
}

# 显示交互菜单
show_menu() {
  # 当前版本
  current_ver=$($BIN_PATH version 2>/dev/null | awk '/version/ {print $3}')
  
  # 获取版本数据
  releases=$(fetch_releases)
  latest_tag=$(echo "$releases" | jq -r '.latest')
  stable_vers=$(echo "$releases" | jq -r '.stable[]')
  beta_vers=$(echo "$releases" | jq -r '.beta[]')

  # 显示信息
  echo -e "\n${CYAN}=== 当前版本 ===${NC}"
  [ -n "$current_ver" ] && echo -e "${GREEN}$current_ver${NC}" || echo -e "${RED}未安装${NC}"

  # 稳定版列表
echo -e "\n${CYAN}=== 稳定版 ===${NC}"
if [ -n "$stable_vers" ]; then
  cnt=1
  while IFS= read -r ver; do
    # 增加版本号对比逻辑
    if [ "$ver" = "$latest_tag" ]; then
      echo -e "  ${GREEN}$cnt) $ver (Latest)${NC}"
    elif [ -z "$latest_tag" ]; then
      echo -e "  ${YELLOW}$cnt) $ver (未标记Latest)${NC}"
    else
      echo "  $cnt) $ver"
    fi
    cnt=$((cnt+1))
  done <<< "$stable_vers"
else
  echo -e "${YELLOW}无可用稳定版${NC}"
fi

  # 测试版列表
  echo -e "\n${CYAN}=== 测试版 ===${NC}"
  if [ -n "$beta_vers" ]; then
    cnt=1
    while IFS= read -r ver; do
      echo "  $cnt) $ver (Pre-release)"
      cnt=$((cnt+1))
    done <<< "$beta_vers"
  else
    echo -e "${YELLOW}无可用测试版${NC}"
  fi

  # 快捷选项
  echo -e "\n${CYAN}快捷安装：${NC}"
  echo -e "  ${GREEN}L) 最新稳定版 (${latest_tag})${NC}"
  [ -n "$beta_vers" ] && echo -e "  ${YELLOW}P) 最新测试版 ($(echo "$beta_vers" | head -1))${NC}"
}

# 安装逻辑
replace_by_ipk() {
  version=$1
  [ -z "$version" ] && return 1

  # 检查当前版本
  current_ver=$($BIN_PATH version 2>/dev/null | awk '{print $3}')
  [ "$current_ver" = "$version" ] && echo -e "${YELLOW}已是最新版本${NC}" && return 0

  # 架构处理
  IPK_ARCH=$(determine_ipk_arch)
  case "$IPK_ARCH" in
    x86_64) search_arch="x86_64" ;;
    arm64) search_arch="arm64"   ;;
    *) search_arch="$IPK_ARCH"   ;;
  esac

  # 查找 IPK 下载链接
  asset_url=$(uclient-fetch -qO- "https://api.github.com/repos/$REPO/releases" | \
    jq -r --arg ver "$version" --arg arch "$search_arch" '
      .[] | select(.tag_name == $ver) |
      .assets[] | select(.name | contains("openwrt") and contains($arch) and endswith(".ipk")) |
      .browser_download_url
    ')

  [ -z "$asset_url" ] && echo -e "${RED}未找到对应架构的 IPK 文件${NC}" && return 1

  # 下载文件
  echo -e "${CYAN}下载 IPK 包...${NC}"
  mkdir -p "$TEMP_DIR"
  uclient-fetch -qO "$TEMP_DIR/sing-box.ipk" "$asset_url" || return 1

  # 停止服务
  [ -f "/etc/init.d/sing-box" ] && /etc/init.d/sing-box stop

  # 备份旧版
  if [ -f "$BIN_PATH" ]; then
    backup_file="$BACKUP_DIR/sing-box_$(date +%s).bak"
    cp "$BIN_PATH" "$backup_file"
    echo -e "${CYAN}已备份旧版本至: ${backup_file}${NC}"
  fi

  # 清理旧版本（新增代码）
  echo -e "${CYAN}正在移除旧版本...${NC}"
  opkg remove sing-box >/dev/null 2>&1

  # 安装新包
  echo -e "${CYAN}执行安装...${NC}"
  opkg install --force-downgrade "$TEMP_DIR/sing-box.ipk"

  # 启动服务
  [ -f "/etc/init.d/sing-box" ] && /etc/init.d/sing-box start

  # 验证版本
  new_ver=$($BIN_PATH version 2>/dev/null | awk '{print $3}')
  [ "$new_ver" = "$version" ] && \
    echo -e "${GREEN}更新成功! 新版本: $new_ver${NC}" || \
    echo -e "${RED}版本验证失败，请手动检查${NC}"
}

# 主程序
singbox() {
  check_dependencies
  mkdir -p "$TEMP_DIR" "$BACKUP_DIR"
  IPK_ARCH=$(determine_ipk_arch)

  while :; do
    show_menu
    echo -ne "\n${CYAN}请选择版本 (L/P/序号/q): ${NC}"
    read choice

    case $choice in
      q|Q) break ;;
      l|L)
        version=$(echo "$releases" | jq -r '.latest')
        [ "$version" != "null" ] && replace_by_ipk "$version"
        ;;
      p|P)
        version=$(echo "$releases" | jq -r '.beta[0]')
        [ "$version" != "null" ] && replace_by_ipk "$version"
        ;;
      [0-9]*)
        type=$(echo "$choice" | sed 's/[0-9]*//g')
        num=$(echo "$choice" | sed 's/[^0-9]*//g')
        [ -z "$num" ] && continue

        if [ "$type" = "s" ]; then
          version=$(echo "$stable_vers" | sed -n "${num}p")
        elif [ "$type" = "b" ]; then
          version=$(echo "$beta_vers" | sed -n "${num}p")
        else
          version=$(echo "$stable_vers" "$beta_vers" | tr ' ' '\n' | sed -n "${num}p")
        fi
        replace_by_ipk "$version"
        ;;
      *) echo -e "${RED}无效输入${NC}" ;;
    esac
  done

  rm -rf "$TEMP_DIR"
}

singbox
