#!/usr/bin/env bash
set -Eeuo pipefail
REPO="Berry-Blog/Berry-Blog-sg-jp-singbox-relay"
VERSION="1.13.21"
ASSET="sing-box-${VERSION}-linux-amd64-musl.tar.gz"
URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${ASSET}"
SHA256="8864abb3b72a6b404445a8c25183c79cfa44a80def0d775ac79578e74fb980e7"
CONFIG_DIR="/etc/sing-box"
SERVICE="/etc/init.d/sing-box"
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

info "安装依赖..."
apk add --no-cache bash curl ca-certificates jq openssl tar coreutils net-tools

TMP="$(mktemp -d /tmp/sg-jp-relay.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

info "从公开 GitHub 仓库获取 sb 管理脚本..."
curl -fsSL --retry 3 \
  "https://raw.githubusercontent.com/$REPO/main/sb" \
  -o "$TMP/sb" || die "无法从公开仓库下载 sb 管理脚本。"
bash -n "$TMP/sb" || die "GitHub 中的 sb 管理脚本语法检查失败。"

FREE_MB="$(df -Pm / | awk 'NR==2 {print $4}')"
[[ "$FREE_MB" =~ ^[0-9]+$ ]] && (( FREE_MB >= 120 )) || die "根分区可用空间不足 120MB。"
if [[ -s "$CONFIG_DIR/config.json" || -s "$CONFIG_DIR/relay.json" ]]; then
  die "发现现有 sing-box 配置。为避免删除有效配置，安装器停止；请先使用 sb 卸载或手动确认。"
fi

echo "================================================"
echo " SG-JP sing-box Relay 一键部署"
echo " Alpine 3.23 / sing-box ${VERSION}"
echo "================================================"
echo "此安装器不会备份已知的旧半成品安装。"
echo "确认后将停止并清理已知的 sing-box 二进制、服务文件和旧部署脚本，再安装官方核心与 sb 管理菜单。"
echo "不会连接或修改日本 BIGLOBE，不会删除 SSH、系统网络配置或历史备份。"
echo
read -r -p "确认继续？输入 YES: " confirm
[[ "$confirm" == "YES" ]] || die "用户取消。"

info "停止并移除旧 sing-box 服务..."
rc-service sing-box stop 2>/dev/null || true
rc-update del sing-box default 2>/dev/null || true
rm -f "$SERVICE"
if command -v apk >/dev/null 2>&1 && apk info -e sing-box >/dev/null 2>&1; then
  apk del sing-box || warn "apk del sing-box 未成功；继续使用官方独立二进制安装。"
fi

# 只清理本项目已知的半成品路径。
rm -f "$BIN" /usr/bin/sing-box /usr/local/bin/sb /usr/bin/sb
rm -f /root/deploy-sg-reality.sh /root/finish-sg-reality.sh
rmdir "$CONFIG_DIR" 2>/dev/null || true

info "下载官方 sing-box ${VERSION}..."
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
