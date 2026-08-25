# Keep serial diagnostics and make the ST7789 fb0 the initial framebuffer
# console. HDMI still initializes as fb1, but tty1/login stays on the panel.
setenv bootargs 'console=ttyS0,115200 console=tty0 video=HDMI-A-1:1920x1080@60D fbcon=map:0 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/sbin/init panic=30'
fatload mmc 0:1 0x40200000 Image
fatload mmc 0:1 0x4fa00000 sun50i-h616-orangepi-zero2.dtb
booti 0x40200000 - 0x4fa00000
