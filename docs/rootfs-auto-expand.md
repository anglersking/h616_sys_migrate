# Debian 首次启动自动扩容

Peutiy Pi 的 Debian 镜像本身约为 1.88 GB，方便保存、下载和烧录。镜像写入
16 GB、32 GB、64 GB 或 128 GB 等更大的 SD 卡后，镜像中的分区表不会因为
`dd` 自动变大，因此必须分别扩展根分区和根文件系统。

这不是 U-Boot 的职责。U-Boot 只负责从卡上装载内核、设备树和启动参数；
Linux 启动后才安全地完成磁盘分区和 ext4 文件系统的在线扩容。

镜像中的 `peutiy-grow-rootfs.service` 会在第一次启动时执行：

1. 使用 `findmnt` 找到当前 `/` 对应的分区；
2. 使用 `lsblk` 找到该分区的父磁盘和分区编号；
3. 使用 `growpart` 把根分区扩展到卡的末尾；
4. 使用 `resize2fs` 在线扩展 ext4 文件系统；
5. 成功后写入 `/var/lib/peutiy/rootfs-expanded`，以后不再重复执行。

检查结果：

```bash
lsblk
df -h /
systemctl status peutiy-grow-rootfs.service
cat /var/lib/peutiy/rootfs-expanded
```

如果曾经删除完成标记并想手动重试：

```bash
rm -f /var/lib/peutiy/rootfs-expanded
systemctl restart peutiy-grow-rootfs.service
```
