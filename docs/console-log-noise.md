# 终端日志降噪

启动阶段仍使用 `console=ttyS0,115200 console=tty0`，所以串口和 ST7789 会显示
内核启动信息。Debian 进入 `multi-user.target` 后，
`peutiy-console-quiet.service` 执行：

- 将 `/proc/sys/kernel/printk` 的 console level 设为 4（只显示 error 及更严重级别）；
- 删除从旧 UID 1000 用户迁移遗留的 `user-1000@*.journal*` 文件；
- 重启 journald，使旧文件名不再被轮转扫描。

镜像还预置了 `journald.conf.d/peutiy-console.conf`，将 journald 转发到 console
的最高级别限制为 `err`。因此 watchdog、压缩、轮转和时间校正等普通提示仍会记录，
但不会持续刷到 ST7789/HDMI 终端。

这只影响“是否打印到当前 console”，不删除正常系统日志；日志仍保存在 journal 中，
可用以下命令查看：

```bash
journalctl -b
journalctl -k -b
dmesg --level=err,warn
```

如果正在调试启动问题，可临时恢复详细 console 输出：

```bash
sysctl -w kernel.printk='7 4 1 7'
```

重启后服务会再次应用降噪设置。
