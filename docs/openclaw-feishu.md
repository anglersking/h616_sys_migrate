# 在 Peutiy Pi 上安装 OpenClaw 并接入飞书

本文按 Peutiy Pi Debian 镜像实测环境编写。示例使用 root 运行 OpenClaw，配置目录为
`/root/.openclaw`。root 模式配置简单，但 Gateway、技能和飞书收到的消息都拥有整块
板子的 root 权限；不可信的技能和群聊不要启用。

## 1. 准备网络和 Node.js

先确认网络正常，并使用 Node.js 22 或更高版本：

```bash
ping -c 3 deb.debian.org
node --version
npm --version
```

本项目镜像已经预装 Node.js 和 npm。若是自行安装的 Debian，Node.js 版本低于 22，
先升级到受支持版本，再继续：

```bash
apt-get update
apt-get install -y ca-certificates curl
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
```

## 2. 安装 OpenClaw 和插件

```bash
npm install --global openclaw
openclaw --version
openclaw plugins install @openclaw/deepseek-provider
openclaw plugins install @openclaw/feishu
```

如果系统里已经有旧的 `openclaw` 用户 Gateway，先停掉它，避免两个 Gateway 抢占
18789 端口：

```bash
runuser -u openclaw -- env HOME=/home/openclaw XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user disable --now openclaw-gateway.service 2>/dev/null || true
systemctl stop openclaw-gateway.service 2>/dev/null || true
```

## 3. 配置 DeepSeek

创建 root 配置目录并设置权限：

```bash
install -d -m 700 /root/.openclaw
```

不要把 API key 直接写在命令行中。用隐藏输入写入环境文件，避免进入 shell history：

```bash
read -rsp 'DeepSeek API key: ' DEEPSEEK_API_KEY; echo
printf 'DEEPSEEK_API_KEY=%s\n' "$DEEPSEEK_API_KEY" > /root/.openclaw/gateway.systemd.env
unset DEEPSEEK_API_KEY
chmod 600 /root/.openclaw/gateway.systemd.env
```

运行配置向导（选择 local Gateway；模型提供商选择 DeepSeek）：

```bash
openclaw onboard --mode local
```

如果向导没有自动填入 DeepSeek API 地址，确认配置中使用：

```text
https://api.deepseek.com/v1
```

API key 不要提交到 Git、不要发到聊天，也不要放进截图。密钥泄露后应立即在
DeepSeek 控制台撤销并重新生成。

## 4. 配置 root Gateway 服务

创建系统级 systemd 服务，使 Gateway 开机自动启动：

```bash
cat >/etc/systemd/system/openclaw-gateway.service <<'UNIT'
[Unit]
Description=OpenClaw Gateway (root)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 18789
Restart=always
RestartSec=5
EnvironmentFile=-/root/.openclaw/gateway.systemd.env
Environment=HOME=/root
Environment=TMPDIR=/tmp
Environment=PATH=/usr/bin:/bin:/usr/local/bin:/root/.local/bin:/root/.npm-global/bin:/root/bin
Environment=OPENCLAW_GATEWAY_PORT=18789

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now openclaw-gateway.service
systemctl status openclaw-gateway.service --no-pager
```

确认只有一个 Gateway：

```bash
ps -eo user,pid,args | grep '[o]penclaw.*gateway'
ss -ltnp | grep ':18789'
```

## 5. 接入飞书

先停止 Gateway，再启动扫码向导，避免配置写入时被旧进程覆盖：

```bash
systemctl stop openclaw-gateway.service
openclaw channels login --channel feishu
```

在向导中：

1. 选择 `Scan a QR code to create a bot automatically`；
2. 选择 `Feishu (feishu.cn)`；
3. 用手机飞书扫描终端中的二维码；
4. 安全策略选择仅允许本人私聊，群聊先禁用或使用 allowlist；
5. 等待向导显示绑定完成。

二维码、App Secret 和 token 都不要粘贴到聊天中。二维码过期时，重新执行上面的
`openclaw channels login --channel feishu` 即可。

绑定后启动并检查：

```bash
systemctl start openclaw-gateway.service
openclaw channels status
openclaw doctor
journalctl -u openclaw-gateway.service -n 100 --no-pager
```

看到 Feishu channel 已连接后，在飞书给机器人发送“你好”进行端到端测试。

## 6. 本地 TUI 和常用维护

root Gateway 已启动时，直接进入本地对话：

```bash
openclaw tui
```

修改 DeepSeek key：

```bash
read -rsp 'New DeepSeek API key: ' DEEPSEEK_API_KEY; echo
printf 'DEEPSEEK_API_KEY=%s\n' "$DEEPSEEK_API_KEY" > /root/.openclaw/gateway.systemd.env
unset DEEPSEEK_API_KEY
chmod 600 /root/.openclaw/gateway.systemd.env
systemctl restart openclaw-gateway.service
```

查看日志或重启：

```bash
systemctl status openclaw-gateway.service --no-pager
journalctl -u openclaw-gateway.service -f
systemctl restart openclaw-gateway.service
```

如果 TUI 报 `WorkspaceVanishedError`，说明配置还指向旧的 `openclaw` 用户目录，
改回 root workspace：

```bash
openclaw config set agents.defaults.workspace /root/.openclaw/workspace
mkdir -p /root/.openclaw/workspace
systemctl restart openclaw-gateway.service
```

如果这是一次有意的迁移且仍提示旧 attestation，可删除 root 下对应的 `.attested`
文件后重启；删除前应确认 workspace 内容已有备份。
