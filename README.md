# Peutiy-Pi (菩提派)

基于全志 H616 的自制 Linux 开发板，从零构建主线 Linux 系统。
基于 Buildroot + 主线 U-Boot + Yuzuki H616 主线内核，完全脱离芯片厂 BSP。

## 硬件

- **SoC**: 全志 H616 (Quad-core Cortex-A53 @ 1.5GHz)
- **开发板**: Peutiy-Pi（菩提派），兼容 Orange Pi Zero2 设计
- **PCB**: 自制六层板
- **电源管理**: AXP305
- **存储**: MicroSD + SPI NOR Flash
- **网络**: 千兆以太网 + WiFi (RTL8723DS / XR829)
- **USB**: USB-A Host（EHCI/OHCI + PC16 VBUS）+ USB-C peripheral/调试口

### 显示输出

| 接口 | 状态 | 说明 |
|------|------|------|
| HDMI | ✅ 支持 | Yuzuki H616 DE/TCON/DesignWare HDMI 显示链路 |
| ST7789 1.47" LCD | ✅ 支持 | SPI1 4-wire（独立 DC/RST）+ fbtft，172×320 |

当前分支 `build/debian-only-st7789-hdmi-sync` 的 Debian 镜像默认把内核启动日志、
Debian `tty1` 登录提示和登录后的终端放在 ST7789 上；HDMI 同时初始化，可用
`con2fbmap` 把 `tty1` 临时切到 HDMI。USB-A Host 键盘已在 Peutiy-Pi 实板上验证。
USB-C 端口保留为 peripheral 模式，不与 USB-A Host 的键盘、鼠标等外设用途混用。

镜像首次启动时会自动扩展 Debian 根分区和 ext4 文件系统，以使用整张 SD 卡。
同一个约 1.88 GB 的镜像可直接写入 16 GB、32 GB、64 GB、128 GB 等容量的卡，
不需要修改 U-Boot，也不需要手动执行扩容命令。原理和检查方法见
[Debian 首次启动自动扩容](docs/rootfs-auto-expand.md)。

OpenClaw、DeepSeek 和飞书接入步骤见
[OpenClaw + 飞书配置指南](docs/openclaw-feishu.md)。

#### 当前显示逻辑

系统同时保留串口和屏幕终端：

1. `boot.cmd` 设置 `console=ttyS0,115200 console=tty0`，所以串口日志始终保留；
   `video=HDMI-A-1:1920x1080@60D` 请求 HDMI 使用 1920×1080@60。
2. `fbcon=map:0` 请求 framebuffer console 使用编号为 `fb0` 的设备。当前正常
   探测顺序是 ST7789=`fb0`、HDMI DRM=`fb1`，所以早期内核启动日志会先显示在
   ST7789；串口日志始终保留。
3. `peutiy-hdmi-console.service` 在 Debian 进入多用户目标后运行一次，把 `tty1`
   映射回 ST7789 并切换到虚拟终端 1。因此 Debian 的登录提示和终端也在小屏上，
   HDMI 仍会初始化，可单独运行桌面或手动把 tty1 切过去。

这套配置故意不让 HDMI 在启动时抢占 tty1。`con2fbmap` 只影响 Linux tty，不会
切换已经运行的 X11/Wayland 桌面。

`chvt 1` 的含义是切换到 Linux 的虚拟终端 1（`tty1`）；它不是 HDMI 专用命令。
因此切屏时总是先找到 framebuffer 编号，再执行 `con2fbmap 1 <编号>` 和
`chvt 1`。framebuffer 编号由驱动探测顺序决定，不能永久假定 HDMI 一定是 `fb1`。

#### 确认当前状态

以下命令请以 root 身份执行：

```bash
cat /proc/fb
ls /sys/class/drm/
cat /sys/class/drm/card0-HDMI-A-1/status  # connected 或 disconnected
systemctl status peutiy-hdmi-console.service
```

预期 framebuffer 类似：

```text
0 fb_st7789v
1 sun4i-drmdrmfb
```

编号由驱动探测顺序决定，不要盲目固定使用 `fb0` 或 `fb1`。

#### 手动切换到 HDMI

```bash
HDMI_FB=$(awk '$2 ~ /drm/ { print $1; exit }' /proc/fb)
test -n "$HDMI_FB" || { echo "HDMI framebuffer not found"; exit 1; }
con2fbmap 1 "$HDMI_FB"
chvt 1
```

#### 手动切换到 ST7789

```bash
ST7789_FB=$(awk '$2 ~ /(fb_st7789v|st7789)/ { print $1; exit }' /proc/fb)
test -n "$ST7789_FB" || { echo "ST7789 framebuffer not found"; exit 1; }
con2fbmap 1 "$ST7789_FB"
chvt 1
```

也可以在需要时让服务重新把 tty1 放回 ST7789：

```bash
systemctl restart peutiy-hdmi-console.service
```

#### 让内核启动日志改为显示在 HDMI

默认 `boot.cmd` 使用 `fbcon=map:0`，即把 framebuffer console 指向 ST7789 的
`fb0`。在当前正常探测顺序（ST7789=`fb0`、HDMI=`fb1`）下，想让内核日志显示
在 HDMI，可把 `boot.cmd` 中的参数改为 `fbcon=map:1`，然后重新生成启动脚本：

```bash
perl -pi -e 's/fbcon=map:0/fbcon=map:1/' boot.cmd
DEBIAN_ONLY=1 sh build_all.sh "$PWD/out-debian-hdmi-console" 1880
```

构建容器会自动用 `mkimage` 把 `boot.cmd` 编译成新的 `boot.scr`，再把它放进
镜像的 FAT 启动分区。串口
日志不会受影响，因为 `console=ttyS0,115200` 仍然存在。进入 Debian 后，已启用的
`peutiy-hdmi-console.service` 会按本分支设计把 `tty1` 再切回 ST7789；如果希望
登录提示也留在 HDMI，执行：

```bash
systemctl disable --now peutiy-hdmi-console.service
HDMI_FB=$(awk '$2 ~ /drm/ { print $1; exit }' /proc/fb)
test -n "$HDMI_FB" || { echo "HDMI framebuffer not found"; exit 1; }
con2fbmap 1 "$HDMI_FB"
chvt 1
```

只想临时测试一次而不改 SD 卡，可在 U-Boot 中断自动启动后手动加载内核，使用
同一组 `bootargs`，把 `fbcon=map:0` 改成 `fbcon=map:1`：

```text
setenv bootargs 'console=ttyS0,115200 console=tty0 video=HDMI-A-1:1920x1080@60D fbcon=map:1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/sbin/init debug panic=30'
fatload mmc 0:1 0x40200000 Image
fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero2.dtb
booti 0x40200000 - 0x4fa00000
```

标准 `fbcon` 是把 console 选到一个 framebuffer；它不会自动把同一份内核日志
复制到两个屏幕。需要两个屏幕同时出现日志时，要额外做 framebuffer mirror/copy，
这不属于当前默认方案。

注意：`fbcon=map:0` 依赖 ST7789 在内核注册为 `fb0`。如果小屏驱动没有注册，
早期 printk 仍可通过串口确认；系统进入用户空间后，服务会等待 ST7789 出现。

当前 Buildroot 配置没有启用 X11 或 Wayland，因此镜像默认提供的是串口/tty
与 framebuffer 应用。任何支持 fbdev 的非桌面程序都可以直接打开
`/dev/fb${ST7789_FB}`；`fbtest` 安装后可用 `fbtest --fb /dev/fb${ST7789_FB}`
测试。

想了解这套适配是怎样从接线、设备树和内核配置一步步定位出来的，参见
[ST7789 小屏适配学习笔记](docs/st7789-adaptation-notes.md)。

ST7789 也可以运行图形桌面，但需另行在 Buildroot 中加入 Xorg fbdev 或
Weston 的 fbdev 后端，并将其显式指向该 framebuffer。它不会自动与 HDMI
镜像；需要两个独立图形会话，或额外的 framebuffer-copy 程序。受限于
172×320 分辨率和 SPI 带宽，适合轻量状态面板/简单桌面，不适合视频或高刷新率桌面。

#### 关闭 ST7789 以节省资源

ST7789 空闲时不会持续占用大量 CPU，但会占用一个 framebuffer、约 110 KiB
显存，以及 SPI/GPIO 驱动资源。只使用 HDMI 时，推荐在设备树中永久关闭它：

```dts
/* main_sun50i-h616-orangepi-zero2.dts 的 &spi1/display@0 节点 */
display@0 {
	status = "disabled";
};
```

然后重新编译内核/DTB 和镜像，再刷入 SD 卡。这样启动后不会创建
`fb_st7789v`，HDMI 会成为唯一的显示 framebuffer。由于 HDMI 此时通常会变成
`fb0`，`boot.cmd` 应保持为：

```text
fbcon=map:0
```

再重新生成 `boot.scr`；否则如果仍使用 `fbcon=map:1`，它会指向不存在的第二个 framebuffer，
早期日志可能不会出现在 HDMI。

只想临时关闭时，在运行中的系统执行：

```bash
echo spi0.0 > /sys/bus/spi/drivers/fb_st7789v/unbind
```

重新启用：

```bash
echo spi0.0 > /sys/bus/spi/drivers/fb_st7789v/bind
```

如果设备编号不是 `spi0.0`，先执行 `ls /sys/bus/spi/devices`。`unbind` 只卸载
驱动，不会断开接到 3.3V 的背光 `BL/LED`；背光要熄灭，需要断开 BL 或单独增加
背光 GPIO 控制。临时 `unbind` 后 framebuffer 编号也可能改变，重新切换前请再
查看 `/proc/fb`，不要继续使用旧编号。

### 以太网、Wi-Fi 和蓝牙

内核和镜像同时包含 H616 千兆以太网 MAC + Realtek PHY、RTL8723DS SDIO
Wi-Fi、Linux Bluetooth/BLE 协议栈、Realtek HCI 驱动，以及 `ip`、`iw`、
`nmcli`、`wpa_supplicant`、`dhclient`、`ping`、`htop`、`rfkill`、
`bluetoothctl` 和 `btattach` 工具。NetworkManager 已设置为开机启动。
启动后可按下面的命令确认硬件是否被枚举：

```bash
ip link                         # 应看到 eth0；有线 DHCP：dhclient eth0
modprobe 8723ds                 # Wi-Fi 模块（若尚未自动加载）
rfkill unblock all
iw dev                          # 应看到 wlan0
ip link set wlan0 up
iw dev wlan0 scan | head

bluetoothctl                    # 蓝牙控制器出现后执行
power on
scan on
```

推荐使用 `nmcli` 连接 WPA/WPA2 Wi-Fi：

```bash
nmcli radio wifi on
nmcli device wifi rescan
nmcli device wifi list
nmcli device wifi connect '你的WiFi名称' password '你的WiFi密码'
nmcli connection show --active
ip -4 addr
ping -c 3 1.1.1.1
```

NetworkManager 会把连接配置保存在 `/etc/NetworkManager/system-connections/`，
以后开机会自动重连。忘记或删除某个连接：

```bash
nmcli connection show
nmcli connection delete '你的WiFi名称'
```

如果 NetworkManager 没识别到无线接口，先执行：

```bash
modprobe 8723ds
rfkill unblock wifi
systemctl restart NetworkManager
nmcli device status
```

下面是不用 NetworkManager、直接调用 `wpa_supplicant` 的备用流程：

```bash
WIFI_SSID='你的WiFi名称'
WIFI_PASSWORD='你的WiFi密码'

modprobe 8723ds 2>/dev/null || true
rfkill unblock wifi
ip link set wlan0 up
wpa_passphrase "$WIFI_SSID" "$WIFI_PASSWORD" | \
  sed '/^[[:space:]]*#psk=/d' > /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
wpa_supplicant -B -D nl80211 -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
dhclient -v wlan0
ip -4 addr show wlan0
ping -c 3 1.1.1.1
```

备用流程的配置文件会保留，重启后需要重新启动连接时执行：

```bash
rfkill unblock wifi
ip link set wlan0 up
wpa_supplicant -B -D nl80211 -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
dhclient wlan0
```

如果接口不叫 `wlan0`，先以 `nmcli device status`、`iw dev` 或 `ip link` 显示的
实际接口名替换命令。不要同时让 NetworkManager 和手动启动的 `wpa_supplicant`
管理同一个接口；使用备用流程前可先执行 `systemctl stop NetworkManager`。

RTL8723DS 的蓝牙部分取决于板上实际连接的 USB/UART HCI 总线：USB HCI 会由
内核自动绑定；若是独立 UART 模块，需要按原理图对应的 `/dev/ttyS*` 手动运行
`btattach`，再进入 `bluetoothctl`。镜像已包含 H4/3-wire/Realtek UART 支持，
但设备树不会猜测未确认的 UART 引脚。

### ST7789 接线

该分支使用板上已引出的连续 PH 接口，不再依赖 PG6、PG7 或 PH5：

| ST7789 | Peutiy-Pi GPIO | 说明 |
|--------|----------------|------|
| GND | GND | 电源地 |
| VCC | 3.3V | 不要接 5V 逻辑电平 |
| SCL/SCK | PH6 | SPI1_CLK |
| SDA/MOSI | PH7 | SPI1_MOSI |
| DC | PH8 | 命令/数据选择，必须连接 |
| CS | PH9 | GPIO 片选，必须按本表连接 |
| RST/RES | PH10 | 低电平复位 |
| BL/LED | 3.3V | 背光常亮 |

ST7789 不需要 MISO。接线和拔线前应关闭开发板电源。实板彩色字符测试确认该屏
使用驱动原生 RGB 顺序，设备树不要添加 `bgr;`，否则红色和蓝色会互换。

![实体板子](./picture/4.jpg)
![PCB布线](./picture/5.png)

## 构建环境

本项目使用 Docker 构建，隔离环境依赖。`yuzuki-h616` 分支使用
`dumtux/Allwinner-H616` 的 H616 显示改动叠加到 Linux 5.16.17 源码上，
与已验证的 Yuzuki H616 主线镜像使用同一套 HDMI 设备树和驱动；本项目仅
叠加 Peutiy-Pi 的 AXP305、网络和 ST7789 配置。

### 构建组件

| 组件 | 版本 | 说明 |
|------|------|------|
| ARM Trusted Firmware | mainline master | BL31 |
| U-Boot | 2024.01 | Bootloader, orangepi_zero2_defconfig |
| Linux Kernel | Yuzuki H616 mainline 5.16.17 | 原生 H616 HDMI PHY 与 fbtft ST7789V |
| GCC 工具链 | ARM 10.3 (aarch64-none-linux-gnu) | 替代已下架的 Linaro 7.5 |
| Buildroot | 2022.02.5 | 可选的另一套 rootfs；Debian-only 模式会跳过 |
| Debian | Bullseye arm64 | 当前推荐 rootfs，包含 systemd、网络、Wi-Fi 和蓝牙工具 |

## 快速开始

### 方式一：只编译 Debian 镜像（当前推荐）

```bash
git clone https://github.com/anglersking/Peutiy-Pi.git
cd Peutiy-Pi
git switch build/debian-only-st7789-hdmi-sync

# 编译 U-Boot、Linux 5.16.17、DTB、内核模块和 Debian Bullseye，
# 跳过 Buildroot，并自动制作可启动的 Debian SD 镜像。
# 1880 MiB 适合本项目的 Debian 镜像；第二个参数可按卡容量调整。
DEBIAN_ONLY=1 sh build_all.sh "$PWD/out-debian" 1880
```

成功后最重要的文件是：

```text
out-debian/sdcard_debian.img
```

这个模式仍然会编译内核、U-Boot 和设备树，不是只打包 rootfs。它只是不下载、
不编译和不导出 Buildroot，因此更适合当前 Debian 测试流程。

如果需要同时生成 Buildroot 镜像，去掉 `DEBIAN_ONLY=1` 即可：

```bash
sh build_all.sh "$PWD/out-all" 1880
```

### macOS（Intel 与 Apple Silicon）

安装并启动 Docker Desktop 后，直接运行：

```bash
DEBIAN_ONLY=1 sh build_all.sh "$PWD/out-debian" 1880
```

脚本在 macOS 上自动使用 `linux/amd64` 容器：Intel Mac 原生执行，Apple
Silicon 通过 Docker Desktop 的模拟执行，因此构建会较慢但与 Linux 使用同一套
交叉工具链。SD 镜像在容器内直接写入文件，不依赖 macOS 不提供的 `losetup` 或
Linux 挂载接口。macOS 的默认输出目录为当前仓库下的 `out/`，也可以将自定义
目录作为第一个参数、镜像大小（MiB）作为第二个参数传入。

### 方式二：只执行 Docker 编译阶段（高级用法）

```bash
docker build --platform=linux/amd64 \
  --build-arg BUILD_DEBIAN_ONLY=1 \
  --network=host -t h616_core_build . 2>&1 | tee build.log
# 编译产物位于容器 /out/；推荐使用上面的 build_all.sh 自动制作 SD 镜像。
```

### 提取构建产物 (方式二后续)

```bash
# 创建 out 目录并运行容器
mkdir -p out
docker run --rm --privileged \
  -v $(pwd)/out:/out \
  h616_core_build \
  /bin/sh -c "cp -r /out/. /mnt_out/"

# 或者直接从 container 拷出
docker cp $(docker create h616_core_build):/out ./
```

### 3. 产物说明

```
out/
├── image/Image                             # Linux 内核镜像
├── dtb/sun50i-h616-orangepi-zero2.dtb      # 设备树二进制
├── bootscr/boot.scr                        # U-Boot 启动脚本
├── uboot/u-boot-sunxi-with-spl.bin         # U-Boot + SPL 镜像
├── modules/lib/modules/                    # 内核模块目录
├── debian-rootfs.tar                       # Debian Bullseye arm64 rootfs
└── sdcard_debian.img                       # ✅ Debian 完整 SD 卡镜像 (双分区, 可直接刷)
```

如果没有设置 `DEBIAN_ONLY=1`，还会额外出现 `buildroot/` 和
`sdcard_buildroot.img`；两种镜像共用同一份内核、DTB 和 U-Boot。

每个 `.img` 文件结构：

```
分区1 (FAT32, 128M):  /Image  /sun50i-h616-orangepi-zero2.dtb  /boot.scr
分区2 (ext4,  剩余空间): rootfs + /lib/modules/
8KB 偏移:              U-Boot SPL
```

### 4. 直接刷入 SD 卡

```bash
# ⚠️ 请确认设备！必须写入整张 SD 卡（/dev/sdX），不要写入 /dev/sdX1。
# Linux 用 lsblk，macOS 用 diskutil list 确认设备。

# Linux：
sudo umount /dev/sdX1 /dev/sdX2 2>/dev/null || true
sudo dd if=out-debian/sdcard_debian.img of=/dev/sdX bs=4M status=progress conv=fsync
sync

# macOS：先执行 diskutil list 找到 N，再执行：
diskutil unmountDisk /dev/diskN
sudo dd if="$PWD/out-debian/sdcard_debian.img" of=/dev/rdiskN bs=4m status=progress
sync
diskutil eject /dev/diskN
```

烧录前后建议校验镜像：

```bash
# macOS
shasum -a 256 out-debian/sdcard_debian.img

# Linux
sha256sum out-debian/sdcard_debian.img
```

刷卡完成后，把 SD 卡插入开发板再上电。默认 hostname 是 `peutiy`，登录账号和
密码都是 `root`，即 `root` / `root`；联网后请立即执行 `passwd` 修改密码。

刷完后插卡到 Orange Pi Zero2 上电即可启动。

### 5. 手动制作 SD 卡（如果想自己分步操作）

```bash
export sdcard=sdc  # ⚠️ 改成你的 SD 卡设备名，不要写错！

# 1. 清空分区表
dd if=/dev/zero of=/dev/$sdcard bs=1M count=10

# 2. 创建双分区 (预留 20MB 给 U-Boot)
fdisk /dev/$sdcard << EOF
n
p
1

+128M
n
p
2


w
EOF

# 3. 写入 U-Boot 到 8KB 偏移
dd if=out-debian/uboot/u-boot-sunxi-with-spl.bin of=/dev/$sdcard bs=8K seek=1

# 4. 格式化
mkfs.fat /dev/${sdcard}1
mkfs.ext4 /dev/${sdcard}2

# 5. 写入 boot 分区
mount /dev/${sdcard}1 /mnt/boot/
cp out-debian/image/Image /mnt/boot/
cp out-debian/dtb/sun50i-h616-orangepi-zero2.dtb /mnt/boot/
cp out-debian/bootscr/boot.scr /mnt/boot/
umount /mnt/boot

# 6. 写入 rootfs 分区

# Buildroot 版:
mount /dev/${sdcard}2 /mnt/rootfs/
tar xf out-all/buildroot/rootfs.tar -C /mnt/rootfs
cp -a out-all/modules/lib/. /mnt/rootfs/lib/
umount /mnt/rootfs

# Debian 版（当前推荐）:
mount /dev/${sdcard}2 /mnt/rootfs/
tar xf out-debian/debian-rootfs.tar -C /mnt/rootfs
cp -a out-debian/modules/lib/. /mnt/rootfs/lib/
umount /mnt/rootfs
```

## Boot 流程

```
BROM → SPL → ATF (BL31) → U-Boot → Linux Kernel → RootFS
```

U-Boot 启动参数 (`boot.cmd` → `boot.scr`)：

```
bootargs: console=ttyS0,115200 console=tty0 video=HDMI-A-1:1920x1080@60D fbcon=map:0 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/sbin/init
bootcmd:  fatload mmc 0:1 0x40200000 Image
          fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero2.dtb
          booti 0x40200000 - 0x4fa00000
```

Debian 镜像的 hostname 是 `peutiy`，因此登录提示显示为 `peutiy login:`，登录后
Shell 提示符为 `root@peutiy`。测试账号和密码都是 `root`。镜像会在 ST7789 的
虚拟终端 `tty1` 显示登录提示；HDMI 仍会初始化。这是硬件测试凭据，连接网络前
应立即运行 `passwd` 修改密码。

成功登录后，PAM 会运行 `/etc/update-motd.d/10-peutiy-header`，用下面的命令生成
与香橙派相同机制的动态字符画和板卡信息：

```bash
TERM=linux toilet -f pagga -F metal "PEUTIY PI"
```

系统网络名保存在 `/etc/hostname`，人类可读的板卡名 `Peutiy Pi` 保存在
`/etc/peutiy-release` 的 `BOARD_NAME` 中；两者用途不同。实现说明见
[Debian 登录欢迎信息笔记](docs/debian-login-banner.md)。

## 调试

```bash
# 串口: UART0 (PH0=TX, PH1=RX), 115200 8N1
screen /dev/ttyUSB0 115200

# HDMI 显示测试
cat /sys/class/drm/card0-HDMI-A-1/status  # 查看 HDMI 连接状态
cat /sys/class/drm/card0-HDMI-A-1/modes   # 查看支持的分辨率

# ST7789 显示测试（先从 /proc/fb 获取实际编号）
ST7789_FB=$(awk '$2 ~ /(fb_st7789v|st7789)/ { print $1; exit }' /proc/fb)
fbtest --fb "/dev/fb${ST7789_FB}"
```

## 项目结构

```
├── dockerfile                     # Docker 构建文件 (主要)
├── buildroot.config               # Buildroot 基础配置
├── buildroot_finally_config       # Buildroot 最终配置 (含无线驱动重编后)
├── linux_main_menuconfig          # Linux 内核 .config
├── linux_main_realtek_Makefile    # Realtek 驱动 Makefile
├── realtek_Kconfig                # Realtek 驱动 Kconfig
├── rtl8Kconfig                    # RTL8723DS Kconfig
├── main_sun50i-h616-orangepi-zero2.dts  # 设备树 overlay
├── boot.cmd                       # U-Boot 启动脚本源文件
├── uboot_config                   # U-Boot defconfig
├── uboot_config                   # U-Boot 配置
├── dram_sun50i_h616.c             # U-Boot DRAM 初始化
├── axp305.c                       # U-Boot AXP305 PMIC 驱动
├── entrypoint.sh                  # 容器入口脚本
├── build.sh                       # Docker 构建脚本
├── auto_write.sh                  # SD 卡自动烧录脚本
├── fixbug/                        # 驱动修复补丁
├── docs/debian-login-banner.md    # hostname、BOARD_NAME 与动态 MOTD
├── docs/st7789-adaptation-notes.md # ST7789 适配学习笔记
├── picture/                       # 项目图片
└── sdcard_make/                   # SD 卡制作脚本
```

## SD 卡镜像制作

推荐始终使用 `build_all.sh`：它会在 Linux 容器内完成分区、FAT32/ext4 格式化、
U-Boot 写入、boot 文件复制和 Debian rootfs 写入。这样 macOS 不需要提供
`losetup` 或 Linux 挂载接口，也不会把宿主机的 `/dev` 设备节点错误地打进 rootfs。

如果确实需要手动制作，分区布局必须保持一致：

```text
MBR 分区表
分区 1：FAT32，起始 sector 40960（20 MiB），大小 128 MiB
分区 2：ext4，从分区 1 结束处开始，占剩余空间
U-Boot SPL：整张卡偏移 8 KiB（sector 16）
```

手动写入 Debian 时，把 `debian-rootfs.tar` 解到分区 2，再把
`modules/lib/.` 复制到分区 2 的 `lib/`；分区 1 只需要 `Image`、DTB 和
`boot.scr`。除非在调试镜像制作脚本，否则不建议手工替代自动化流程。

### 镜像适配小容量 SD 卡

如果镜像大小超出 SD 卡实际可用扇区数（比如标称 2G 的卡实际只有 1.84 GiB），需要缩小分区：

```bash
# 1. 检查 ext4 实际使用量
dumpe2fs -h p2_partition.img 2>/dev/null | grep -E 'Block count|Free blocks|Block size'

# 2. 缩小文件系统（保留余量）
 e2fsck -f p2_partition.img
 resize2fs -f p2_partition.img <new_block_count>

# 3. 修改 MBR 分区表中的 p2 扇区数，截断镜像
# 4. 重新 dd 烧录
```

## 注意事项

- **内核来源**: 使用 Yuzuki H616 显示改动叠加的 Linux 5.16.17；构建时将板级 DTS 编译为 `sun50i-h616-orangepi-zero2.dtb`，提供 H616 的 display engine、TCON、HDMI 和 ST7789 节点。
- **HDMI compatible**: HDMI 控制器复用 `allwinner,sun50i-h6-dw-hdmi`，PHY 使用回移的 `allwinner,sun50i-h616-hdmi-phy` 参数表（H6 初始化流程），由内建的 `CONFIG_DRM_SUN8I_DW_HDMI=y` 驱动绑定。
- **ST7789 驱动选择**: 这块屏是带 DC/RST 的 8-bit/4-wire SPI 模块，必须使用 `CONFIG_FB_TFT_ST7789V=y`、`buswidth = <8>` 与 `rotate`；不能使用只支持 9-bit SPI、240×320 的 DRM `panel-sitronix-st7789v` 驱动。
- **工具链**: ARM 官方 10.3，前缀 `aarch64-none-linux-gnu-`
- **编译并行度**: 默认按容器可见 CPU 数全核构建；Linux 使用标准 Make jobserver，macOS 通过独立作业池兼容 Docker Desktop。
- **rootfs 大小**: Debian 镜像默认按 1880 MiB 制作；如果使用更小的卡，需要先确认卡的实际扇区数再缩小 ext4 和分区。
- **Buildroot 构建源**: 已配置清华 tuna 镜像源加速国内下载
