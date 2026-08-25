#!/bin/sh
# Keep early kernel messages visible, then quiet routine systemd notices on
# the framebuffer console once Debian has reached multi-user.target.
set -eu

# console_loglevel: 1 emerg, 2 alert, 3 crit, 4 err, 5 warning, 6 notice,
# 7 info. Journald and kernel logs remain available through journalctl/dmesg.
printf '4 4 1 4\n' >/proc/sys/kernel/printk 2>/dev/null || true

# Remove journals left by the old UID 1000 OpenClaw user. These filenames are
# harmless but systemd-journald warns about them whenever time is corrected.
if [ -d /var/log/journal ]; then
	find /var/log/journal -maxdepth 2 -type f \
		-name 'user-1000@*.journal*' -delete 2>/dev/null || true
	/usr/bin/systemctl try-restart systemd-journald.service 2>/dev/null || true
fi

exit 0
