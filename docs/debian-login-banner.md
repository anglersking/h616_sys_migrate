# Debian 登录欢迎信息适配笔记

本项目参考 Orange Pi 的动态 MOTD 做法，在登录成功后显示 `PEUTIY PI` 字符画、
板卡名称、系统版本、内核版本、hostname 和 IP 地址。

## hostname 和 BOARD_NAME 的区别

这两个名字用途不同：

| 名称 | 保存位置 | 作用 |
| --- | --- | --- |
| `peutiy` | `/etc/hostname` | Linux 网络主机名、`login:` 前缀和 Shell 提示符 |
| `Peutiy Pi` | `/etc/peutiy-release` 的 `BOARD_NAME` | 给用户看的板卡产品名 |

所以启动后会看到：

```text
peutiy login:
```

root 登录后的提示符通常是：

```text
root@peutiy:~#
```

而欢迎信息中显示的是 `Board: Peutiy Pi`。

## 为什么使用 `/etc/update-motd.d`

Debian 的 `/etc/pam.d/login` 会调用 `pam_motd.so`。PAM 在用户认证成功后运行
`/etc/update-motd.d/` 下的可执行脚本，生成 `/run/motd.dynamic`，因此欢迎信息
可以在每次登录时读取当前内核、hostname 和 IP，而不是把这些内容写死在
`/etc/motd`。

本项目的脚本是：

```text
/etc/update-motd.d/10-peutiy-header
```

板卡信息文件是：

```text
/etc/peutiy-release
```

这种结构与 Orange Pi 的 `10-orangepi-header` 和 `BOARD_NAME` 思路一致，但脚本
内容只依赖 Debian Bullseye 中实际安装的工具。

## toilet 命令

Docker 构建 Debian rootfs 时安装 `toilet` 软件包。字符画使用：

```bash
TERM=linux toilet -f pagga -F metal "PEUTIY PI"
```

`-f pagga` 选择字体；`-F metal` 选择金属色彩效果。第二个参数必须是大写的
`-F`，写成第二个 `-f metal` 会把 `metal` 当成字体名。

`pagga` 只有三行高，适合 320×172 的 ST7789 横屏终端。脚本还提供纯文本回退：
如果 `toilet` 或效果执行失败，至少会显示 `PEUTIY PI`，不会影响登录。

## 构建时写入了什么

`dockerfile` 在 Debian rootfs 中完成以下操作：

1. 安装 `toilet` 和 `isc-dhcp-client`；
2. 写入 `/etc/hostname` 和 `/etc/hosts`；
3. 写入 `/etc/machine-info` 的 `PRETTY_HOSTNAME`；
4. 把 root 测试密码设为 `root`；
5. 安装并启用 `10-peutiy-header`；
6. 清空 Debian 静态 `/etc/motd`，避免动态欢迎信息后重复显示旧文本；
7. 禁用默认 `10-uname`，因为新脚本已经显示内核版本。

这是面向首次上板验证的简单凭据。设备接入网络后应立即执行：

```bash
passwd
```

## 手动测试欢迎信息

不用退出当前 Shell，可以直接测试动态脚本：

```bash
run-parts /etc/update-motd.d
```

也可以只测试字符画：

```bash
TERM=linux toilet -f pagga -F metal "PEUTIY PI"
```

检查配置：

```bash
hostname
cat /etc/hostname
cat /etc/peutiy-release
ls -l /etc/update-motd.d/
```
