#!/bin/sh
# Move tty1 to the DRM framebuffer after the HDMI pipeline has registered.
set -eu

for _ in $(seq 1 30); do
	HDMI_FB=$(awk '$2 ~ /drm/ { print $1; exit }' /proc/fb 2>/dev/null || true)
	if [ -n "$HDMI_FB" ]; then
		/usr/bin/con2fbmap 1 "$HDMI_FB"
		/usr/bin/chvt 1
		exit 0
	fi
	sleep 1
done

exit 0
