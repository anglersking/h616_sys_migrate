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

HDMI 登录界面和 USB-A Host 键盘已在 Peutiy-Pi 实板上验证。USB-C 端口保留为
peripheral 模式，不与 USB-A Host 的键盘、鼠标等外设用途混用。

**HDMI 和 ST7789 双显共存**：系统启动后两个显示设备会注册。编号由驱动探测顺序决定，先用 `cat /proc/fb` 确认，再用 `con2fbmap` 切换 Linux console 输出：

Debian 镜像已包含 `con2fbmap` 和 `chvt`，并会在 HDMI DRM framebuffer
注册后自动将 `tty1` 映射到 HDMI。下列命令用于手动切换或排障；请以 root
身份执行。

启动脚本默认带有 `video=HDMI-A-1:1920x1080@60D fbcon=map:1`。在本板的
驱动探测顺序下，ST7789 是 `fb0`、HDMI DRM 是 `fb1`，因此内核启动日志和
`tty0/tty1` 会优先显示在 HDMI；`console=ttyS0,115200` 仍会保留串口日志。
如果 HDMI 没有接入或没有成功注册，系统会回退到已存在的 framebuffer，届时
仍可通过下面的命令检查并手动切换。

```bash
# 查看 framebuffer 编号（不要假定 HDMI 一定是 fb0）
cat /proc/fb

# 自动找出 fbtft ST7789 对应的 framebuffer 编号并将 tty1 切过去
ST7789_FB=$(awk '$2 ~ /(fb_st7789v|st7789)/ { print $1; exit }' /proc/fb)
test -n "$ST7789_FB" || { echo "ST7789 framebuffer not found"; exit 1; }
con2fbmap 1 "$ST7789_FB"
chvt 1

# 切回 HDMI（sun4i DRM framebuffer）
HDMI_FB=$(awk '$2 ~ /drm/ { print $1; exit }' /proc/fb)
test -n "$HDMI_FB" || { echo "HDMI framebuffer not found"; exit 1; }
con2fbmap 1 "$HDMI_FB"
chvt 1

# 查看显示状态
cat /sys/class/drm/card0-HDMI-A-1/status
```

`con2fbmap` 只切换内核 console，不能切换已经运行的图形桌面。当前
Buildroot 配置没有启用 X11 或 Wayland，因此镜像默认提供的是串口/tty 与
framebuffer 应用。任何支持 fbdev 的非桌面程序都可以直接打开
`/dev/fb${ST7789_FB}`；`fbtest` 安装后可用 `fbtest --fb /dev/fb${ST7789_FB}`
测试。

ST7789 也可以运行图形桌面，但需另行在 Buildroot 中加入 Xorg fbdev 或
Weston 的 fbdev 后端，并将其显式指向该 framebuffer。它不会自动与 HDMI
镜像；需要两个独立图形会话，或额外的 framebuffer-copy 程序。受限于
172×320 分辨率和 SPI 带宽，适合轻量状态面板/简单桌面，不适合视频或高刷新率桌面。

### 以太网、Wi-Fi 和蓝牙

内核和镜像同时包含 H616 千兆以太网 MAC + Realtek PHY、RTL8723DS SDIO
Wi-Fi、Linux Bluetooth/BLE 协议栈、Realtek HCI 驱动，以及 `ip`、`iw`、
`wpa_supplicant`、`rfkill`、`bluetoothctl` 和 `btattach` 工具。启动后可按下面
的命令确认硬件是否被枚举：

```bash
ip link                         # 应看到 eth0；有线 DHCP：udhcpc -i eth0
modprobe 8723ds                # Wi-Fi 模块（若尚未自动加载）
rfkill unblock all
iw dev                          # 应看到 wlan0
ip link set wlan0 up
iw dev wlan0 scan | head

bluetoothctl                    # 蓝牙控制器出现后执行
power on
scan on
```

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

ST7789 不需要 MISO。接线和拔线前应关闭开发板电源。

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
| Buildroot | 2022.02.5 | 根文件系统 + 编译无线驱动后重编内核 |
| Debian | Bullseye arm64 | debootstrap 引导，备选 rootfs |

## 快速开始

### 方式一：一键构建 + 出 SD 镜像（推荐）

```bash
git clone https://github.com/anglersking/Peutiy-Pi.git
cd Peutiy-Pi

# 一条命令：编译 + 提取产物 + 制作 SD img
# 产物自动输出到 /mnt/nvme0n1-4/out/
sh build_all.sh /mnt/nvme0n1-4/out
```

### macOS（Intel 与 Apple Silicon）

安装并启动 Docker Desktop 后，直接运行：

```bash
sh build_all.sh
```

脚本在 macOS 上自动使用 `linux/amd64` 容器：Intel Mac 原生执行，Apple
Silicon 通过 Docker Desktop 的模拟执行，因此构建会较慢但与 Linux 使用同一套
交叉工具链。SD 镜像在容器内直接写入文件，不依赖 macOS 不提供的 `losetup` 或
Linux 挂载接口。macOS 的默认输出目录为当前仓库下的 `out/`，也可以将自定义
目录作为第一个参数、镜像大小（MiB）作为第二个参数传入。

### 方式二：只编译（产物在容器内）

```bash
docker build --network=host -t h616_core_build . 2>&1 | tee build.log
# 产物在容器 /out/ 下，需要手动 docker cp 出来
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
├── buildroot/
│   ├── rootfs.ext2                         # Buildroot 根文件系统 (ext2)
│   └── rootfs.tar                          # Buildroot 根文件系统 (tar)
├── debian-rootfs.tar                       # Debian Bullseye arm64 rootfs
├── sdcard_buildroot.img                    # ✅ Buildroot 完整 SD 卡镜像 (1024M, 双分区, 可直接刷)
└── sdcard_debian.img                       # ✅ Debian 完整 SD 卡镜像 (1024M, 双分区, 可直接刷)
```

每个 `.img` 文件结构：

```
分区1 (FAT32, 128M):  /Image  /sun50i-h616-orangepi-zero2.dtb  /boot.scr
分区2 (ext4,  ~380M):  rootfs + /lib/modules/
8KB 偏移:              U-Boot SPL
```

### 4. 直接刷入 SD 卡

```bash
# ⚠️ 请确认设备！/dev/sdX 是你的 SD 卡
# 用 lsblk 确认你的 SD 卡设备名

# 刷 Buildroot 版本：
dd if=out/sdcard_buildroot.img of=/dev/sdX bs=4M status=progress

# 刷 Debian 版本：
dd if=out/sdcard_debian.img of=/dev/sdX bs=4M status=progress
```

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
dd if=out/uboot/u-boot-sunxi-with-spl.bin of=/dev/$sdcard bs=8K seek=1

# 4. 格式化
mkfs.fat /dev/${sdcard}1
mkfs.ext4 /dev/${sdcard}2

# 5. 写入 boot 分区
mount /dev/${sdcard}1 /mnt/boot/
cp out/image/Image /mnt/boot/
cp out/dtb/sun50i-h616-orangepi-zero2.dtb /mnt/boot/
cp out/bootscr/boot.scr /mnt/boot/
umount /mnt/boot

# 6. 写入 rootfs 分区

# Buildroot 版:
mount /dev/${sdcard}2 /mnt/rootfs/
tar xf out/buildroot/rootfs.tar -C /mnt/rootfs
cp -a out/modules/lib/. /mnt/rootfs/lib/
umount /mnt/rootfs

# Debian 版:
mount /dev/${sdcard}2 /mnt/rootfs/
tar xf out/debian-rootfs.tar -C /mnt/rootfs
cp -a out/modules/lib/. /mnt/rootfs/lib/
umount /mnt/rootfs
```

## Boot 流程

```
BROM → SPL → ATF (BL31) → U-Boot → Linux Kernel → RootFS
```

U-Boot 启动参数 (`boot.cmd` → `boot.scr`)：

```
bootargs: console=ttyS0,115200 console=tty0 video=HDMI-A-1:1920x1080@60D fbcon=map:1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/sbin/init
bootcmd:  fatload mmc 0:1 0x40200000 Image
          fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero2.dtb
          booti 0x40200000 - 0x4fa00000
```

Debian 镜像首次启动的测试账号为 `peutiy`，密码为 `peutiy`；也可使用
`root` / `peutiy` 进行诊断。镜像会在 HDMI 的虚拟终端 `tty1` 显示登录提示。
这是硬件测试凭据，连接网络前应立即修改密码。

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
├── picture/                       # 项目图片
└── sdcard_make/                   # SD 卡制作脚本
```

## SD 卡镜像制作

### 自动化制作（容器内 `shuaxie.sh`）

镜像在容器构建时自动生成，位于 `/out/image/`。结构：

```
分区1 (FAT32, 128M):  /Image  /sun50i-h616-orangepi-zero2.dtb  /boot.scr
分区2 (ext4):          Buildroot rootfs + /lib/modules/
8KB 偏移:              U-Boot SPL
```

### 手动制作（macOS / Linux）

```bash
# 1. 准备空镜像
IMG=sdcard_buildroot.img
dd if=/dev/zero of=$IMG bs=1M count=2048

# 2. 分区 (MBR, 双分区)
#    分区1: 128MB FAT32 (起始 sector 40960 = 20MB, 留给 U-Boot)
#    分区2: ext4 (剩余空间)
fdisk $IMG << EOF
o
n
p
1
40960
+128M
n
p
2


w
EOF

# 3. 写入 U-Boot SPL (8KB 偏移)
dd if=u-boot-sunxi-with-spl.bin of=$IMG bs=8K seek=1 conv=notrunc

# 4. 创建 loop 设备并格式化 (macOS)
# 略 — 推荐用 Linux 或容器内工具完成

# ----- Linux 上继续 -----
LOOP=$(losetup -Pf --show $IMG)
mkfs.fat -F 32 ${LOOP}p1
mkfs.ext4 ${LOOP}p2

# 5. 写入 boot 分区
mount ${LOOP}p1 /mnt/boot
cp Image /mnt/boot/
cp sun50i-h616-orangepi-zero2.dtb /mnt/boot/
cp boot.scr /mnt/boot/
umount /mnt/boot

# 6. 写入 rootfs
mount ${LOOP}p2 /mnt/rootfs
tar xf rootfs.tar -C /mnt/rootfs
mkdir -p /mnt/rootfs/lib/modules
cp -r modules/lib/modules/* /mnt/rootfs/lib/modules/
umount /mnt/rootfs

losetup -d $LOOP
```

### 烧录到 SD 卡

```bash
# ⚠️ 用 diskutil list (macOS) 或 lsblk (Linux) 确认 SD 卡设备！

# macOS (用 rdisk 更快):
 diskutil unmountDisk /dev/diskX
 sudo dd if=sdcard_buildroot.img of=/dev/rdiskX bs=4m status=progress

# Linux:
 sudo dd if=sdcard_buildroot.img of=/dev/sdX bs=4M status=progress conv=fsync
```

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

- **内核来源**: 使用 Linux 6.0.19；构建时以本仓库的 `sun50i-h616-yuzuki.dtsi` 覆盖内核 DTSI，提供 H616 的 display engine、TCON 和 HDMI 节点。
- **HDMI compatible**: HDMI 控制器复用 `allwinner,sun50i-h6-dw-hdmi`，PHY 使用回移的 `allwinner,sun50i-h616-hdmi-phy` 参数表（H6 初始化流程），由内建的 `CONFIG_DRM_SUN8I_DW_HDMI=y` 驱动绑定。
- **ST7789 驱动选择**: 这块屏是带 DC/RST 的 8-bit/4-wire SPI 模块，必须使用 `CONFIG_FB_TFT_ST7789V=y`、`buswidth = <8>` 与 `rotate`；不能使用只支持 9-bit SPI、240×320 的 DRM `panel-sitronix-st7789v` 驱动。
- **工具链**: ARM 官方 10.3，前缀 `aarch64-none-linux-gnu-`
- **编译并行度**: 默认按容器可见 CPU 数全核构建；Linux 使用标准 Make jobserver，macOS 通过独立作业池兼容 Docker Desktop。
- **rootfs 大小**: Buildroot ext2 分区改为 256M (128M 不够放下 sshd 等组件)
- **Buildroot 构建源**: 已配置清华 tuna 镜像源加速国内下载
