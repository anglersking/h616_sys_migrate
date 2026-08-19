# HDMI 与 ST7789 显示适配

本分支使用 Linux 5.16.17，并叠加 `dumtux/Allwinner-H616` 中的 H616 显示
相关目录。这样保留 Yuzuki 的 display engine、TCON、DesignWare HDMI 和
HDMI PHY 设备树与驱动；`main_sun50i-h616-orangepi-zero2.dts` 只负责启用
板级连接、供电、网络和 ST7789。不要再用 6.0.19 的兼容 DTSI 或 HDMI PHY
回移补丁覆盖它。

## HDMI

显示链路为：

```
display-engine (de) -> mixer0 -> tcon_top/tcon_tv -> HDMI -> connector
```

以下配置必须同时存在：

- DTS 中 `&de`、`&hdmi`、`&hdmi_audio` 和 `&hdmi_phy` 的 `status = "okay"`
- HDMI 输出 endpoint 与 `hdmi-connector` 双向连接
- `hvcc-supply = <&reg_hdmi_1v8>`，为 HDMI PHY 提供 1.8 V。该固定稳压器
  表示 U-Boot 已开启的板级 HDMI 供电；不能引用 AXP305 RSB 提供的
  `reg_bldo1`，因为该 PMIC 在此内核上注册失败会使 HDMI 永久延迟探测
- 内核配置中的 `CONFIG_DRM_SUN4I=y`、`CONFIG_DRM_SUN8I_DW_HDMI=y`、
  `CONFIG_DRM_SUN8I_MIXER=y` 与 `CONFIG_DRM_SUN8I_TCON_TOP=y`

H616 HDMI 控制器和 PHY 使用 Yuzuki 内核树中的原生
`allwinner,sun50i-h616-dw-hdmi` 与 `allwinner,sun50i-h616-hdmi-phy`，由
`CONFIG_DRM_SUN8I_DW_HDMI=y` 编入内核。这样保持与已验证的 Yuzuki 镜像相同
的显示初始化路径。

## ST7789 1.47 inch (172x320)

这块屏的 DC 和 RST 是独立 GPIO，属于 4-wire、8-bit SPI 设备。DTS 采用
`sitronix,st7789v` compatible，实际绑定到 staging fbtft 的
`fb_st7789v` 驱动：

- `dc-gpios = <&pio 6 6 GPIO_ACTIVE_HIGH>` (PG6)
- `reset-gpios = <&pio 6 7 GPIO_ACTIVE_LOW>` (PG7)
- `buswidth = <8>`、`width = <172>`、`height = <320>`、`rotate = <90>`
- `CONFIG_FB_TFT=y` 与 `CONFIG_FB_TFT_ST7789V=y`

不要启用 DRM 的 `CONFIG_DRM_PANEL_SITRONIX_ST7789V`。它的驱动使用
9-bit SPI 传送命令/数据，并固定为 240x320；在这块带 DC/RST 的 172x320
模块上会因绑定方式和供电属性不符而无法正常 probe。

## 上板验证

```sh
# HDMI DRM 链路
dmesg | grep -iE 'drm|hdmi|mixer|tcon'
ls /sys/class/drm/
cat /sys/class/drm/card0-HDMI-A-1/status

# SPI 和 ST7789 framebuffer
dmesg | grep -iE 'spi|fbtft|st7789'
cat /proc/fb

# 切到 ST7789 的 tty console（按驱动名获取实际 framebuffer 编号）
ST7789_FB=$(awk '$2 ~ /(fb_st7789v|st7789)/ { print $1; exit }' /proc/fb)
test -n "$ST7789_FB" || { echo "ST7789 framebuffer not found"; exit 1; }
con2fbmap 1 "$ST7789_FB"
chvt 1

# 如已安装 fbtest，可直接测试该 framebuffer
fbtest --fb "/dev/fb${ST7789_FB}"
```

如 HDMI connector 编号不是 `card0-HDMI-A-1`，请从 `ls /sys/class/drm/`
的实际输出中选择对应项。

## 图形桌面

当前 Buildroot 配置没有选择 X11、Wayland 或 Weston，所以默认镜像不会启动
桌面。ST7789 仍可作为图形桌面的显示目标：启用 Xorg 的 fbdev 驱动或 Weston
fbdev 后端，并让该图形服务器打开 `/dev/fb${ST7789_FB}`。

这与 `con2fbmap` 无关：后者只切换 tty console。HDMI 与 ST7789 是两个独立
framebuffer，不会自动镜像；如需镜像，需要单独的 framebuffer-copy 程序。
172×320 的 SPI 面板适合简单控制 UI，不适合动画、视频或完整高刷新率桌面。
