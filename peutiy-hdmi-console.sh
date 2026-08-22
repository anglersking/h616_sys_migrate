#!/bin/sh
# Keep tty1 on the ST7789 panel after the display drivers have registered.
# The kernel framebuffer console is also mapped to fb0 in boot.cmd, so early
# boot messages and the Debian getty/login prompt use the same small display.
# HDMI is still initialized by DRM and remains available for a desktop or a
# manually selected console; it does not steal tty1 at boot.
set -eu

for _ in $(seq 1 30); do
	ST7789_FB=$(awk '$2 ~ /(fb_st7789v|st7789)/ { print $1; exit }' /proc/fb 2>/dev/null || true)

	if [ -n "$ST7789_FB" ]; then
		/usr/bin/con2fbmap 1 "$ST7789_FB"
		/usr/bin/chvt 1
		exit 0
	fi

	sleep 1
done

exit 0
