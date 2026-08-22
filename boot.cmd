# Keep the serial console for diagnostics, but make the HDMI DRM connector
# the primary framebuffer console. The ST7789 fbtft device is intentionally
# probed first as fb0; once the HDMI pipeline registers it is fb1, so
# fbcon=map:1 prevents kernel/tty output from remaining on the small panel.
setenv bootargs 'console=ttyS0,115200 console=tty0 video=HDMI-A-1:1920x1080@60D fbcon=map:1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/sbin/init debug panic=30'
fatload mmc 0:1 0x40200000 Image
fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero2.dtb
booti 0x40200000 - 0x4fa00000
