# SG-JP sing-box Relay

新加坡线路机与日本家宽落地机之间的轻量 sing-box 管理工具。

## Architecture

\`\`\`
Client
  -> Singapore VLESS Reality inbound
  -> Singapore VLESS Reality outbound
  -> Japan BIGLOBE VLESS Reality inbound
  -> Japan BIGLOBE direct outbound
\`\`\`

## Supported environment

- Alpine Linux x86_64
- OpenRC
- sing-box 1.13.21 (official musl build)

## One-line installation

仓库保持 Public，可直接通过 curl 获取安装器。在新加坡服务器 SSH 中以 root 执行：

\`\`\`sh
apk add --no-cache bash curl && bash -c "$(curl -fsSL https://raw.githubusercontent.com/Berry-Blog/Berry-Blog-sg-jp-singbox-relay/main/install.sh)"
\`\`\`

安装器会先检查环境和下载管理脚本，要求输入 \`YES\` 后才清理已知旧半成品安装。按当前需求，安装器**不会备份已知旧安装**；不会删除 SSH、系统网络配置或历史备份。若检测到已有有效 sing-box 配置，会停止而不是自动删除。

## First setup

首次安装会提示输入服务器 IP/域名（不预填任何实际 IP）：

- Singapore public IP/domain: 必须手动输入
- Singapore public mapped TCP port: 默认 \`30010\`
- Singapore internal listen address: 默认 \`0.0.0.0\`
- Singapore internal listen port: 默认 \`10010\`
- Singapore Reality SNI: 默认 \`addons.mozilla.org\`
- Japan BIGLOBE public IP/domain: 必须手动输入
- Japan Reality public TCP port: 默认 \`30001\`
- Japan Reality SNI: 默认 \`addons.mozilla.org\`
- Japan VLESS UUID
- Japan Reality Public Key
- Japan Reality Short ID

新加坡 Reality 凭据由 sing-box 在本机生成。所有服务器 IP、认证凭据均只保存在服务器本地 root-only 文件，不会写入公开仓库。

## Management

首次配置完成后，登录新加坡服务器运行：

\`\`\`sh
sb
\`\`\`

菜单支持查看节点、生成客户端链接、修改端点和端口、修改 UUID/Reality 参数、切换 Reality 或 Shadowsocks 出站、配置检查、服务启停、日志、备份恢复、更新和卸载。

管理脚本更新也直接从 Public GitHub 仓库 curl 拉取，不需要 Token：

\`\`\`sh
sb
# 选择 "Update sb manager"
\`\`\`

## Default port values

| Purpose | Default |
|---|---:|
| Singapore public TCP mapping | \`30010\` |
| Singapore internal VLESS listener | \`10010\` |
| Japan Reality public TCP mapping | \`30001\` |
| Optional Japan SS public TCP mapping | \`30003\` |
| Optional Japan SS internal listener | \`8388\` |

端口默认值可以在首次安装或 \`sb\` 菜单中修改；服务器 IP 必须由管理员自行输入。

## Important

- 首次部署默认启用 Reality -> Reality。
- 所有代理流量通过 sing-box \`route.final\` 固定发往日本 outbound，不配置新加坡 Direct fallback。
- 当前默认仅配置 TCP。
- 修改新加坡内部监听端口时，必须同步修改运营商端口映射。
- 修改日本 UUID/Public Key/Short ID 时，必须确保日本 BIGLOBE 的 Reality inbound 凭据匹配。
- Reality -> SS 模式仅生成日本 SS 入站配置片段；切换前必须先在日本增加 SS inbound，并由管理员配置相应 TCP 端口映射。此管理器不会远程修改日本机器。
- SS mode is a later A/B test, not enabled by default.
- Keep local backups private; they contain authentication secrets.

## Local files

- \`/etc/sing-box/relay.json\`: root-only parameters and credentials
- \`/etc/sing-box/config.json\`: generated runtime config
- \`/etc/sing-box/uris.txt\`: client URI, root-only
- \`/root/sb-relay-backups/\`: timestamped configuration backups created by the manager
- \`/usr/local/bin/sb\`: interactive manager
