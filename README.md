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

### Optional legacy cleanup

如果检测到旧 sing-box 文件，安装器会询问是否清理：

- 输入 \`Y\` 或直接回车：停止旧服务，删除旧 sing-box 配置目录、服务文件、核心程序及旧管理命令；**不备份旧安装**。
- 输入 \`N\`：不触碰旧配置和服务，并取消本次安装，避免覆盖旧服务。

清理不会删除 \`/root\` 下已有的历史备份，也不会修改 SSH、系统网络配置或日本 BIGLOBE。若没有检测到旧安装，则跳过清理询问。

## First setup

首次安装会提示输入服务器 IP/域名（不预填任何实际 IP）：

- Singapore public IP/domain: 必须手动输入
- Singapore public mapped TCP port: 默认 \`30010\`，可输入自定义端口
- Singapore internal listen address: 默认 \`0.0.0.0\`
- Singapore internal listen port: 默认 \`10010\`，可输入自定义端口
- Singapore Reality SNI: 默认 \`addons.mozilla.org\`
- Japan BIGLOBE public IP/domain: 必须手动输入
- Japan Reality public TCP port: 默认 \`30001\`，可输入自定义端口
- Japan Reality SNI: 默认 \`addons.mozilla.org\`
- Japan VLESS UUID
- Japan Reality Public Key
- Japan Reality Short ID

端口提示处直接回车使用默认值，输入 1-65535 的数字即可使用自定义端口。修改内部监听端口后，必须同步修改商家端口映射。新加坡 Reality 凭据由 sing-box 在本机生成。所有服务器 IP、认证凭据均只保存在服务器本地 root-only 文件，不会写入公开仓库。

## Management

首次配置完成后，登录新加坡服务器直接运行：

\`\`\`sh
sb
\`\`\`

不需要执行 \`sh sb\`。菜单支持查看节点、生成客户端链接、修改端点和端口、修改 UUID/Reality 参数、切换 Reality 或 Shadowsocks 出站、配置检查、服务启停、日志、备份恢复、更新和卸载。

管理脚本更新也直接从 Public GitHub 仓库 curl 拉取，不需要 Token。

## Default port values

| Purpose | Default | Custom |
|---|---:|---|
| Singapore public TCP mapping | \`30010\` | Yes |
| Singapore internal VLESS listener | \`10010\` | Yes |
| Japan Reality public TCP mapping | \`30001\` | Yes |
| Optional Japan SS public TCP mapping | \`30003\` | Yes |
| Optional Japan SS internal listener | \`8388\` | Yes |

## Important

- 首次部署默认启用 Reality -> Reality。
- 所有代理流量通过 sing-box \`route.final\` 固定发往日本 outbound，不配置新加坡 Direct fallback。
- 当前默认仅配置 TCP。
- 修改端口时，管理器会提示同步更新运营商/商家端口映射；映射需要在商家面板单独调整。
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
