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

## Private repository installation

此仓库设为 Private 后，匿名 \`curl\` 无法读取安装文件。请创建一个仅对此仓库有访问权限的 GitHub Fine-grained Personal Access Token，权限只需：

- Repository access: Only select repositories -> this repository
- Repository permissions: Contents -> Read-only

在服务器 SSH 中执行以下命令。Token 通过隐藏输入读取，不会写入 shell 命令历史；安装器不会将 Token 持久保存：

\`\`\`sh
read -r -s -p "GitHub read-only token: " GH_TOKEN </dev/tty
printf '\\n' >/dev/tty
export GH_TOKEN
curl -fsSL \\
  -H "Authorization: Bearer $GH_TOKEN" \\
  -H "Accept: application/vnd.github.raw" \\
  "https://api.github.com/repos/Berry-Blog/Berry-Blog-sg-jp-singbox-relay/contents/install.sh?ref=main" \\
  -o /tmp/sg-jp-install.sh
bash /tmp/sg-jp-install.sh
status=$?
rm -f /tmp/sg-jp-install.sh
unset GH_TOKEN
exit "$status"
\`\`\`

安装器会先预取并检查管理脚本，再要求输入 \`YES\` 确认。随后备份已知旧安装、清理本项目旧文件、安装官方 sing-box 二进制并进入首次配置。安装器不会连接或修改日本服务器。

## First setup

安装时需要交互输入：

- Singapore public endpoint and mapped TCP port
- Singapore internal listen address and port
- Japan BIGLOBE public endpoint and Reality TCP port
- SNI
- Japan VLESS UUID
- Japan Reality Public Key
- Japan Reality Short ID

所有节点地址和端口均由管理员在服务器本地输入，不在仓库中提供默认值。新加坡 Reality 凭据由 sing-box 在本机生成。认证凭据保存在 root-only 本地文件，不会提交到 GitHub。

## Management

首次配置完成后，登录新加坡服务器运行：

\`\`\`sh
sb
\`\`\`

菜单支持查看节点、生成客户端链接、修改端点和端口、修改 UUID/Reality 参数、切换 Reality 或 Shadowsocks 出站、配置检查、服务启停、日志、备份恢复、更新和卸载。

更新私有仓库中的 \`sb\` 管理脚本时，需要再次输入同一类只读 GitHub Token；Token 不会保存。

## Important

- 首次部署默认启用 Reality -> Reality。
- 所有代理流量通过 sing-box \`route.final\` 固定发往日本 outbound，不配置新加坡 Direct fallback。
- 当前默认仅配置 TCP。
- 修改内部监听端口时，必须同步修改运营商端口映射。
- 修改日本 UUID/Public Key/Short ID 时，必须确保日本 BIGLOBE 的 Reality inbound 凭据匹配。
- Reality -> SS 模式仅生成日本 SS 入站配置片段；切换前必须先在日本增加 SS inbound，并由管理员配置相应 TCP 端口映射。此管理器不会远程修改日本机器。
- SS mode is a later A/B test, not enabled by default.
- Keep backup archives private; they contain authentication secrets.

## Local files

- \`/etc/sing-box/relay.json\`: root-only parameters and credentials
- \`/etc/sing-box/config.json\`: generated runtime config
- \`/etc/sing-box/uris.txt\`: client URI, root-only
- \`/root/sb-relay-backups/\`: timestamped backups
- \`/usr/local/bin/sb\`: interactive manager
