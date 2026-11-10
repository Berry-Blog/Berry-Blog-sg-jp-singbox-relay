# SG-JP sing-box 双节点中转管理

为新加坡 GoMami 线路机与日本 BIGLOBE 家宽落地机设计的轻量管理脚本。基于 sing-box 1.13.21，支持双 VLESS Reality 节点、Clash Meta/Mihomo 配置导出、备份恢复和中文菜单。

## 双节点工作方式

两个客户端节点共用新加坡同一个 Reality 监听地址和端口，通过不同的 VLESS UUID 用户名路由：

- **节点 A：新加坡直出**。VLESS 用户名为 \`sg-direct\`，流量由新加坡机器直接出站。
- **节点 B：新加坡 → 日本 BIGLOBE**。VLESS 用户名为 \`sg-via-jp\`，流量继续使用现有日本 Reality（或后续配置的 SS）出站。

路由使用 sing-box 的 VLESS 用户 \`name\` 与 route \`auth_user\` 匹配。新增节点不会重新生成或替换现有日本中转节点的 UUID、Reality 私钥、公钥和 Short ID。

## 一键安装

仅支持 Alpine Linux x86_64 + OpenRC：

\`\`\`sh
apk add --no-cache bash curl && bash -c "$(curl -fsSL https://raw.githubusercontent.com/Berry-Blog/Berry-Blog-sg-jp-singbox-relay/main/install.sh)"
\`\`\`

安装器检测到旧 sing-box 文件时会询问是否清理。清理为可选项；不会删除 SSH、系统网络配置或历史备份。首次配置时服务器 IP/域名由管理员输入，端口可直接回车采用默认值，也可以输入自定义端口。

## 已部署机器升级

如果机器已经安装旧版管理脚本，不要重新安装核心，也不要重新运行安装器。

1. SSH 登录新加坡服务器。
2. 输入 \`sb\`。
3. 在旧版菜单中选择“更新 sb 管理脚本”（旧菜单编号 27）。
4. 脚本从本 Public 仓库下载新版、先执行 \`bash -n\` 检查，再自动重新载入中文菜单。
5. 在新版菜单选择“应用/修复双节点路由配置”（编号 9）；新版菜单中的管理脚本更新功能为编号 30。

更新管理脚本本身不会立即改变正在运行的 sing-box 配置。必须主动选择菜单 9 才会应用双节点配置。应用前会自动备份当前参数和配置；校验或重启失败会回滚。

也可以在服务器上执行 \`sb update\` 更新管理脚本。

## 中文菜单功能

- 查看双节点状态与参数
- 明文显示新加坡、日本两侧 UUID、Reality Private/Public Key、Short ID
- 生成两个独立 VLESS Reality 一键导入链接
- 生成 Clash Meta / Mihomo YAML 配置文件
- 启用本机 Clash 订阅文件服务并生成 HTTPS 订阅地址
- 修改新加坡/日本 IP、端口、UUID、Public Key、Short ID、SNI
- 单独重新生成新加坡直出 UUID
- 轮换新加坡 Reality 密钥
- Reality / Shadowsocks 日本出站切换
- 配置校验、服务启停、日志、备份恢复、核心更新和卸载

## 导出文件

应用双节点配置后，执行 \`sb\`：

- 菜单 3：显示两个 VLESS 分享链接，保存在 \`/etc/sing-box/export/vless.txt\`
- 菜单 4：生成 Clash Meta/Mihomo 配置，保存在 \`/etc/sing-box/export/clash.yaml\`

Clash YAML 内含两个代理节点和一个手动选择策略组，可通过 SCP 下载后在 Clash Meta / Mihomo 中从文件导入。

## Clash 远程订阅地址

菜单 5 可以启用一个轻量本机静态文件服务：

- 默认仅监听 \`127.0.0.1:18080\`，不直接开放公网端口
- 生成随机长令牌路径，订阅文件不放在公开仓库
- 要获得可用的远程订阅 URL，需自行将 HTTPS 域名、Cloudflare Tunnel 或 HTTPS 反向代理转发到脚本显示的本机上游地址
- 订阅 URL 包含随机访问令牌，等同于节点凭据；不要公开分享
- 脚本不会擅自增加商家公网端口映射，也不会自动替用户创建 DNS、证书或 Cloudflare Tunnel

如果尚未配置 HTTPS 反向代理，可先使用本地 Clash YAML 文件导入，不要把含节点凭据的 YAML 放在公开 GitHub 仓库或通过明文 HTTP 公开传输。

## 安全说明

- 公开仓库只保存通用脚本，不保存真实服务器 IP、UUID、Reality 密钥、Short ID 或订阅令牌。
- 本地参数文件 \`/etc/sing-box/relay.json\` 权限为 root-only（600）。
- 用户明确要求凭据在 SSH 终端明文显示；菜单 2 会展示完整参数。请不要在公开录屏、截图或聊天中暴露这些内容。
- 当前节点端口映射为 TCP；Clash 配置按 TCP Reality 生成，不宣称已启用 UDP。
- 修改端口后，需要在商家面板同步修改端口映射。
- 修改日本落地 UUID/Public Key/Short ID 后，必须与日本 BIGLOBE 实际入站配置一致。此脚本只管理新加坡机器，不会远程修改日本服务器。

## 本地文件

- \`/etc/sing-box/relay.json\`：本地参数及认证凭据（600）
- \`/etc/sing-box/config.json\`：sing-box 运行配置（600）
- \`/etc/sing-box/export/vless.txt\`：两个 VLESS 分享链接（600）
- \`/etc/sing-box/export/clash.yaml\`：Clash Meta/Mihomo 配置（600）
- \`/root/sb-relay-backups/\`：修改前自动备份
- \`/usr/local/bin/sb\`：中文管理命令

## 参考

管理菜单和节点导出体验参考 [yonggekkk/sing-box-yg](https://github.com/yonggekkk/sing-box-yg)；双节点路由和参数管理为本项目按 SG-JP 架构定制。
