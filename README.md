# SG-JP sing-box Relay

新加坡 GoMami 线路机 + 日本 BIGLOBE 家宽出口的轻量 sing-box 管理工具。

## 当前目标架构

\`\`\`
客户端
  -> Singapore GoMami VLESS Reality inbound
  -> Singapore VLESS Reality outbound
  -> Japan BIGLOBE VLESS Reality inbound
  -> Japan BIGLOBE direct outbound
\`\`\`

## Install

仅支持 Alpine Linux x86_64 + OpenRC：

\`\`\`sh
bash <(curl -fsSL https://raw.githubusercontent.com/Berry-Blog/Berry-Blog-sg-jp-singbox-relay/main/install.sh)
\`\`\`

安装器要求输入 \`YES\` 才继续。它先将旧安装备份到 \`/root/sb-relay-backups/\`，再清理已知的 sing-box 半成品并安装官方 musl amd64 二进制。不会修改日本服务器，也不会删除 SSH 或系统网络配置。

默认建议值：
- Singapore public endpoint: \`178.94.15.19:30010/TCP\`
- Singapore internal listener: \`0.0.0.0:10010/TCP\`
- Japan BIGLOBE endpoint: \`167.254.242.31:30001/TCP\`
- SNI: \`addons.mozilla.org\`
- sing-box: \`1.13.21\`

日本 UUID、Reality Public Key、Short ID 和新加坡生成的私钥不会写入公开仓库；安装时交互输入/生成，保存在 root-only 文件。

## Management

登录新加坡服务器后运行：

\`\`\`sh
sb
\`\`\`

菜单支持查看节点、客户端链接、修改 IP/端口/UUID/Reality 参数、切换 Reality 或 SS 出站、配置检查、服务启停、日志、备份恢复、更新和卸载。

## Important

- 首次部署默认启用 Reality -> Reality。
- 所有代理流量通过 sing-box \`route.final\` 固定发往日本 outbound，不配置 Singapore direct fallback。
- 当前默认只配置 TCP。
- 修改 Singapore internal port 时，必须同步修改商家端口映射。
- 修改日本 UUID/Public Key/Short ID 时，必须确保日本 BIGLOBE 的 Reality inbound 凭据匹配。
- Reality -> SS 模式只生成日本 SS 入站配置片段；切换前必须先在日本增加 SS inbound，并由商家设置公网 TCP 端口映射到日本内网 8388。此管理器不会远程修改日本机器。
- SS mode is a later A/B test, not enabled by default.
- Keep backup archives private; they contain authentication secrets.

## Files

- \`/etc/sing-box/relay.json\`: root-only parameters and credentials
- \`/etc/sing-box/config.json\`: generated runtime config
- \`/etc/sing-box/uris.txt\`: client URI, root-only
- \`/root/sb-relay-backups/\`: timestamped backups
- \`/usr/local/bin/sb\`: interactive manager
