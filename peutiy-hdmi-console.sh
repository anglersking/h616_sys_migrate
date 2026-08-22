#!/bin/sh
# Select the framebuffer for tty1 after the display drivers have registered.
# HDMI wins only when its connector reports "connected"; otherwise use ST7789.
set -eu

for _ in $(seq 1 30); do
	HDMI_CONNECTED=0
	for status_file in /sys/class/drm/*-HDMI-A-*/status; do
		if [ -r "$status_file" ] && [ "$(cat "$status_file")" = connected ]; then
			HDMI_CONNECTED=1
			break
		fi
	done

	HDMI_FB=$(awk '$2 ~ /drm/ { print $1; exit }' /proc/fb 2>/dev/null || true)
	ST7789_FB=$(awk '$2 ~ /(fb_st7789v|st7789)/ { print $1; exit }' /proc/fb 2>/dev/null || true)

	if [ "$HDMI_CONNECTED" -eq 1 ] && [ -n "$HDMI_FB" ]; then
		/usr/bin/con2fbmap 1 "$HDMI_FB"
		/usr/bin/chvt 1
		exit 0
	fi

	if [ -n "$ST7789_FB" ]; then
		/usr/bin/con2fbmap 1 "$ST7789_FB"
		/usr/bin/chvt 1
		exit 0
	fi

	sleep 1
done

exit 0
