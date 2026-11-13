#!/usr/bin/env bash
set -Eeuo pipefail

REPO="Berry-Blog/Berry-Blog-sg-jp-singbox-relay"
VERSION="1.13.21"
ASSET="sing-box-${VERSION}-linux-amd64-musl.tar.gz"
URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${ASSET}"
SHA256="8864abb3b72a6b404445a8c25183c79cfa44a80def0d775ac79578e74fb980e7"
CONFIG_DIR="/etc/sing-box"
SERVICE="/etc/init.d/sing-box"
CONF_FILE="/etc/conf.d/sing-box"
BIN="/usr/local/bin/sing-box"

info(){ printf '[INFO] %s\n' "$*"; }
warn(){ printf '[WARN] %s\n' "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "请使用 root 用户执行。"
[[ -r /etc/os-release ]] || die "无法识别操作系统。"
. /etc/os-release
[[ "${ID:-}" == "alpine" ]] || die "当前版本仅支持 Alpine Linux。"
[[ "$(uname -m)" == "x86_64" ]] || die "当前版本仅支持 x86_64。"
command -v rc-service >/dev/null 2>&1 || die "未检测到 OpenRC。"

FREE_MB="$(df -Pm / | awk 'NR==2 {print $4}')"
[[ "$FREE_MB" =~ ^[0-9]+$ ]] && (( FREE_MB >= 120 )) || die "根分区可用空间不足 120MB。"

TMP="$(mktemp -d /tmp/sg-jp-relay.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

info "从公开 GitHub 仓库获取管理脚本..."
curl -fsSL --retry 3 \
  "https://raw.githubusercontent.com/${REPO}/main/sb" \
  -o "$TMP/sb" || die "无法下载 sb 管理脚本。"
bash -n "$TMP/sb" || die "sb 管理脚本 Bash 语法检查失败。"
curl -fsSL --retry 3 \
  "https://raw.githubusercontent.com/${REPO}/main/global_relay.py" \
  -o "$TMP/global_relay.py" || die "无法下载 Global 线路管理模块。"

echo "================================================"
echo " SG-JP sing-box Relay 一键部署"
echo " Alpine Linux x86_64 / sing-box ${VERSION}"
echo "================================================"
echo "清理旧 sing-box 配置是可选操作。"
echo "选择清理：停止旧服务并删除旧 sing-box 配置、服务文件和核心程序；不备份旧安装。"
echo "选择保留：不触碰旧配置和服务，并取消本次安装，避免覆盖正在运行的节点。"
echo "无论选择哪项，都不会删除 SSH、系统网络配置或历史备份。"
echo

HAS_OLD=0
[[ ! -d "$CONFIG_DIR" ]] || HAS_OLD=1
[[ ! -e "$SERVICE" ]] || HAS_OLD=1
[[ ! -e "$CONF_FILE" ]] || HAS_OLD=1
[[ ! -e "$BIN" ]] || HAS_OLD=1
[[ ! -e /usr/bin/sing-box ]] || HAS_OLD=1
[[ ! -e /usr/local/bin/sb ]] || HAS_OLD=1
[[ ! -e /usr/bin/sb ]] || HAS_OLD=1
if command -v apk >/dev/null 2>&1 && apk info -e sing-box >/dev/null 2>&1; then
  HAS_OLD=1
fi

if (( HAS_OLD )); then
  echo "检测到已有 sing-box 相关文件："
  [[ ! -d "$CONFIG_DIR" ]] || echo "  - ${CONFIG_DIR}/（旧配置目录）"
  [[ ! -e "$SERVICE" ]] || echo "  - ${SERVICE}（OpenRC 服务）"
  [[ ! -e "$CONF_FILE" ]] || echo "  - ${CONF_FILE}（服务参数）"
  [[ ! -e "$BIN" ]] || echo "  - ${BIN}（核心程序）"
  [[ ! -e /usr/bin/sing-box ]] || echo "  - /usr/bin/sing-box"
  [[ ! -e /usr/local/bin/sb ]] || echo "  - /usr/local/bin/sb（管理命令）"
  [[ ! -e /usr/bin/sb ]] || echo "  - /usr/bin/sb（管理命令链接）"
  echo
  read -r -p "是否清理上述旧 sing-box 文件？[Y/n]: " CLEAN_OLD
  CLEAN_OLD="${CLEAN_OLD:-Y}"
  case "$CLEAN_OLD" in
    Y|y|YES|yes)
      info "按选择清理旧 sing-box 安装（不创建旧安装备份）..."
      rc-service sing-box stop 2>/dev/null || true
      rc-update del sing-box default 2>/dev/null || true
      rm -f "$SERVICE" "$CONF_FILE"
      if command -v apk >/dev/null 2>&1 && apk info -e sing-box >/dev/null 2>&1; then
        apk del sing-box || warn "apk del sing-box 未成功，将继续清理已知文件。"
      fi
      rm -rf "$CONFIG_DIR"
      rm -f "$BIN" /usr/bin/sing-box /usr/local/bin/sb /usr/bin/sb
      rm -f /var/log/sing-box.log /var/log/sing-box.err
      rm -f /root/deploy-sg-reality.sh /root/finish-sg-reality.sh
      ok "旧 sing-box 文件已清理；历史备份目录未删除。"
      ;;
    N|n|NO|no)
      die "你选择保留旧配置。为避免覆盖旧服务，本次安装已取消，服务器未清理旧文件。"
      ;;
    *)
      die "无效选项，请输入 Y 或 N；本次未清理旧文件。"
      ;;
  esac
else
  info "未发现旧 sing-box 安装，无需清理。"
fi

info "安装依赖..."
apk add --no-cache bash curl ca-certificates jq openssl tar coreutils net-tools python3
python3 -m py_compile "$TMP/global_relay.py" || die "Global 线路管理模块语法检查失败。"

info "下载官方 sing-box ${VERSION} musl amd64..."
curl -fL --retry 3 --connect-timeout 20 -o "$TMP/$ASSET" "$URL"
printf '%s  %s\n' "$SHA256" "$TMP/$ASSET" | sha256sum -c -

tar -xzf "$TMP/$ASSET" -C "$TMP"
CANDIDATE="$(find "$TMP" -type f -name sing-box | head -n1)"
[[ -n "$CANDIDATE" ]] || die "压缩包中未找到 sing-box 二进制文件。"
install -m 0755 "$CANDIDATE" "$BIN"
"$BIN" version | head -n 3

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

info "安装 sb 管理命令..."
install -m 0755 "$TMP/sb" /usr/local/bin/sb
ln -sf /usr/local/bin/sb /usr/bin/sb
install -d -m 0755 /usr/local/libexec/sb
install -m 0644 "$TMP/global_relay.py" /usr/local/libexec/sb/global_relay.py

info "进入首次配置..."
/usr/local/bin/sb setup

info "检查服务状态..."
rc-service sing-box status
"$BIN" check -c "$CONFIG_DIR/config.json"

echo
echo "================================================"
echo "部署完成"
echo "管理菜单：sb"
echo "状态检查：sb status"
echo "配置校验：sb check"
echo "客户端链接：sb node"
echo "================================================"
