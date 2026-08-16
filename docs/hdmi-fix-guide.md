# HDMI 与 ST7789 显示适配

本项目使用 Linux 6.0.19。构建时会将仓库内的
`sun50i-h616-yuzuki.dtsi` 安装为内核的 `sun50i-h616.dtsi`，补齐 H616
所需的 display engine、TCON、DesignWare HDMI 和 HDMI PHY 节点；随后用
`main_sun50i-h616-orangepi-zero2.dts` 启用板级连接。

## HDMI

显示链路为：

```
display-engine (de) -> mixer0 -> tcon_top/tcon_tv -> HDMI -> connector
```

以下配置必须同时存在：

- DTS 中 `&de`、`&hdmi` 和 `&hdmi_phy` 的 `status = "okay"`
- HDMI 输出 endpoint 与 `hdmi-connector` 双向连接
- `hvcc-supply = <&reg_bldo1>`，为 HDMI PHY 提供 1.8 V
- 内核配置中的 `CONFIG_DRM_SUN4I=y`、`CONFIG_DRM_SUN8I_DW_HDMI=y`、
  `CONFIG_DRM_SUN8I_MIXER=y`、`CONFIG_DRM_SUN8I_TCON_TOP=y` 和
  `CONFIG_PHY_SUN50I_H616_HDMI=y`

该构建不使用 `apritzel/linux` 的旧 `h616-v13` 分支：该分支基于
5.19-rc1，且其 H616 DTS 没有 HDMI display pipeline，不能和本项目的
6.0.19 配置混用。

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

# framebuffer 编号由探测顺序决定；先查看 /proc/fb，再选择对应编号测试
fbtest --fb /dev/fbN
con2fbmap 1 N
```

如 HDMI connector 编号不是 `card0-HDMI-A-1`，请从 `ls /sys/class/drm/`
的实际输出中选择对应项。
