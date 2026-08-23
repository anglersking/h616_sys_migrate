# ST7789 小屏适配学习笔记

这份笔记记录本项目从“屏幕不亮”到“启动日志和登录终端可用”的排查路径。
目标不是写一个通用 ST7789 驱动，而是理解本板为什么要这样写设备树、内核配置
和启动参数。

## 1. 先把问题拆成四层

一块 SPI 屏能显示，需要四层同时成立：

```text
接线/电源
   ↓
设备树（SPI 总线、GPIO、分辨率、方向）
   ↓
内核驱动（fb_st7789v + framebuffer console）
   ↓
用户空间（/dev/fb0、tty1、con2fbmap）
```

任何一层出错，现象都可能是“背光亮但全黑”：

- 背光亮只说明 `BL/LED` 有电，不说明 SPI 命令已经送到屏幕；
- `/proc/fb` 没有 `fb_st7789v`，说明设备树或驱动没有注册；
- 有 `fb_st7789v` 但仍全黑，重点检查 CS/DC/RST、SPI 模式、窗口偏移和供电；
- 有 framebuffer 但没有登录提示，重点检查 `fbcon` 映射和 `tty1` 的 framebuffer 绑定。

## 2. 这块 172×320 屏的接线

本板没有原先示例中的 PG6、PG7 和 PH5，所以把控制线改到连续的 PH6–PH10：

| 屏幕引脚 | Peutiy-Pi | 作用 |
| --- | --- | --- |
| VCC | 3.3V | 屏幕电源；不要接 5V |
| GND | GND | 共地 |
| SCL/SCK | PH6 | SPI1 时钟 |
| SDA/MOSI | PH7 | SPI1 主出数据；这里不是 I²C SDA |
| DC | PH8 | 命令/数据选择 |
| CS | PH9 | SPI1 的 GPIO 片选 |
| RES/RST | PH10 | 低有效硬件复位 |
| BL/LED | 3.3V | 当前版本背光常亮 |

ST7789 的 MISO 没有使用。接线或拔线必须在板子断电后进行，VCC、GND 和背光
极性先确认，再检查信号线。

## 3. 为什么用 `fb_st7789v`，不用 DRM panel 驱动

这块模块是带独立 `DC` 和 `RST` 的 4-wire、8-bit SPI 屏，分辨率是 172×320。
Linux 5.16.17 已有 staging/fbtft 的 `fb_st7789v` 驱动，协议正好匹配：

```text
命令/数据通过 MOSI 发送
DC GPIO 区分命令与像素数据
RST GPIO 负责复位
CS GPIO 选择屏幕
```

另一个名字相似的 DRM `panel-sitronix-st7789v` 驱动面向不同的面板描述，常见
实现使用 9-bit SPI 并按 240×320 面板初始化。把它直接套到本模块，通常会出现
驱动不 probe、全黑或颜色/方向错误。因此本项目明确使用：

```text
CONFIG_FB_TFT=y
CONFIG_FB_TFT_ST7789V=y
```

并让设备树的 `compatible = "sitronix,st7789v"` 绑定到 `fb_st7789v`。

## 4. 设备树是怎样把屏幕描述给内核的

核心节点在 `main_sun50i-h616-orangepi-zero2.dts`：

```dts
&spi1 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&spi1_tx_pins>;       /* PH6=SCK, PH7=MOSI */
    /delete-property/ dmas;            /* 本板改用 PIO */
    /delete-property/ dma-names;
    cs-gpios = <&pio 7 9 GPIO_ACTIVE_LOW>; /* PH9 */

    display@0 {
        compatible = "sitronix,st7789v";
        reg = <0>;
        spi-max-frequency = <32000000>;
        dc-gpios = <&pio 7 8 GPIO_ACTIVE_HIGH>;    /* PH8 */
        reset-gpios = <&pio 7 10 GPIO_ACTIVE_LOW>; /* PH10 */
        buswidth = <8>;
        rotate = <90>;
        width = <172>;
        height = <320>;
        y-offset = <34>;
        bgr;
        status = "okay";
    };
};
```

Allwinner GPIO 写法里的 `7` 是 H 这个 GPIO bank，后面的 `6`、`7`、`8`、`9`、
`10` 是 PH6–PH10 的 pin 编号。`reg = <0>` 对应 CS0，不是 GPIO 编号。
`y-offset = <34>` 是这类 172×320 模块的显存窗口偏移；没有它时可能只有一部分
画面或画面位置不对。

同时，设备树还必须保留 HDMI 链路：

```text
display-engine → TCON → HDMI 控制器 → hdmi-connector
```

因此 `&de`、`&hdmi`、`&hdmi_audio`、`&hdmi_phy` 和输出 endpoint 不能因为添加
ST7789 就删掉。两套显示设备分别注册 framebuffer，正常顺序是：

```text
/proc/fb
0 fb_st7789v
1 sun4i-drmdrmfb
```

编号只是本次启动的探测顺序；排查时总是先读 `/proc/fb`。

## 5. 内核日志、登录终端和切屏是三件事

### 内核启动日志

`boot.cmd` 的关键参数是：

```text
console=ttyS0,115200 console=tty0 fbcon=map:0
```

`console=ttyS0,115200` 把日志保留在串口；`console=tty0` 允许 framebuffer
console 接收日志；`fbcon=map:0` 把 framebuffer console 选到 `fb0`，也就是
默认的 ST7789。

### Debian 登录界面

Debian 的 `getty@tty1` 提供登录提示。镜像启用的一次性服务
`peutiy-hdmi-console.service` 会查找名字为 `fb_st7789v` 的 framebuffer，执行：

```text
con2fbmap 1 <ST7789 framebuffer number>
chvt 1
```

所以登录提示和登录后的 shell 默认回到 ST7789，即使 HDMI DRM 已经初始化。

### 手动切到 HDMI

```bash
HDMI_FB=$(awk '$2 ~ /drm/ { print $1; exit }' /proc/fb)
test -n "$HDMI_FB" || { echo "HDMI framebuffer not found"; exit 1; }
con2fbmap 1 "$HDMI_FB"
chvt 1
```

切回小屏：

```bash
ST7789_FB=$(awk '$2 ~ /(fb_st7789v|st7789)/ { print $1; exit }' /proc/fb)
test -n "$ST7789_FB" || { echo "ST7789 framebuffer not found"; exit 1; }
con2fbmap 1 "$ST7789_FB"
chvt 1
```

`con2fbmap` 只改变 tty console 的 framebuffer，不会切换 X11/Wayland 桌面，也不
会让两个屏幕自动镜像。

## 6. 如果想让内核日志显示在 HDMI

在当前正常编号下 HDMI 是 `fb1`，把 `boot.cmd` 中：

```text
fbcon=map:0
```

改成：

```text
fbcon=map:1
```

然后重新制作镜像；构建容器会自动把 `boot.cmd` 生成 `boot.scr`：

```bash
DEBIAN_ONLY=1 sh build_all.sh "$PWD/out-debian-hdmi-console" 1880
```

这会把早期 framebuffer 内核日志指向 HDMI，串口仍然保留。进入 Debian 后，
默认服务仍会把 `tty1` 重新映射到 ST7789；如果登录界面也要留在 HDMI：

```bash
systemctl disable --now peutiy-hdmi-console.service
```

如果设备探测顺序变化，`fb1` 不一定是 HDMI；应以 `/proc/fb` 和
`/sys/class/drm/*HDMI*/status` 为准。标准 `fbcon` 只选择一个 console framebuffer，
要让一份内核日志同时出现在两个屏幕，需要另外的 framebuffer copy/mirror 程序。

## 7. 从源码到可启动镜像的过程

```text
U-Boot + ATF 编译
        ↓
Yuzuki 显示改动 + Linux 5.16.17 编译
        ↓
设备树编译（ST7789 + HDMI + 网络）
        ↓
Debian Bullseye arm64 debootstrap
        ↓
安装 systemd、getty、网络/Wi-Fi/蓝牙工具和 ST7789 console 服务
        ↓
FAT32 boot 分区 + ext4 rootfs 分区 + 8 KiB U-Boot SPL
        ↓
sdcard_debian.img
```

当前分支提供 Debian-only 开关：

```bash
DEBIAN_ONLY=1 sh build_all.sh "$PWD/out-debian" 1880
```

它只跳过 Buildroot，不跳过内核、U-Boot、DTB、内核模块或 Debian rootfs。
Docker Desktop 可在 Intel/Apple Silicon Mac 上运行同一套 `linux/amd64` 构建容器。

## 8. 推荐的排查顺序

上板后从串口登录，按这个顺序可以快速定位是哪一层出了问题：

```bash
cat /proc/fb
ls -l /sys/bus/spi/devices
cat /sys/class/graphics/fb0/name
cat /sys/class/drm/card0-HDMI-A-1/status
dmesg | grep -iE 'spi|fbtft|st7789|drm|hdmi'
```

判断方式：

1. 没有 `spi0.0`：SPI/片选/设备树没有注册；
2. 有 `spi0.0` 但没有 `fb_st7789v`：检查 `compatible`、内核配置和 DC/RST；
3. 有 `fb_st7789v` 但全黑：检查 VCC/GND、BL、CS/DC/RST、旋转和窗口偏移；
4. 小屏有登录但 HDMI 黑：检查 HDMI 连接状态和 DRM 日志，不要先改 `con2fbmap`；
5. 两边显示不同终端：先读 `/proc/fb`，再把同一个 `tty1` 映射到目标 framebuffer。

## 9. 可继续学习的方向

- 把 `BL/LED` 从 3.3V 常亮改成一个确认过的 GPIO，并在设备树中加入背光节点；
- 把 `fb_st7789v` 替换为 DRM panel，但要先确认驱动的 SPI 位宽、初始化序列和
  172×320 偏移与模块一致；
- 在 Debian 中安装 Xorg fbdev 或 Weston fbdev，观察桌面与 `con2fbmap` 的边界；
- 编写 framebuffer copy 程序，把 HDMI 的画面缩放后复制到 ST7789（性能会受 SPI
  带宽和 172×320 分辨率限制）。
