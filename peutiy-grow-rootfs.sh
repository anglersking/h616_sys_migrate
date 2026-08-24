#!/bin/sh
# Expand the partition containing / and its ext4 filesystem on first boot.
# The image stays small for distribution while automatically using the full
# capacity of whichever SD card it is written to.
set -eu

STATE_DIR=/var/lib/peutiy
STATE_FILE=$STATE_DIR/rootfs-expanded

if [ -e "$STATE_FILE" ]; then
	exit 0
fi

ROOT_SOURCE=$(findmnt -n -o SOURCE /)
ROOT_DEVICE=$(readlink -f "$ROOT_SOURCE")
PARENT_NAME=$(lsblk -n -o PKNAME "$ROOT_DEVICE" | head -n 1)
PARTITION_NUMBER=$(lsblk -n -o PARTN "$ROOT_DEVICE" | head -n 1)

if [ -z "$PARENT_NAME" ] || [ -z "$PARTITION_NUMBER" ]; then
	echo "peutiy-grow-rootfs: cannot identify parent disk for $ROOT_DEVICE" >&2
	exit 1
fi

DISK_DEVICE=/dev/$PARENT_NAME
echo "peutiy-grow-rootfs: expanding $ROOT_DEVICE on $DISK_DEVICE"

# growpart reports NOCHANGE with a non-zero status when the partition already
# reaches the end of the card. Treat that case as success so cloned/full-size
# images do not retry forever.
if ! GROW_OUTPUT=$(growpart "$DISK_DEVICE" "$PARTITION_NUMBER" 2>&1); then
	case "$GROW_OUTPUT" in
		*NOCHANGE*) ;;
		*)
			echo "$GROW_OUTPUT" >&2
			exit 1
			;;
	esac
fi
printf '%s\n' "$GROW_OUTPUT"

resize2fs "$ROOT_DEVICE"

mkdir -p "$STATE_DIR"
printf 'root=%s\ndisk=%s\ncompleted=%s\n' \
	"$ROOT_DEVICE" "$DISK_DEVICE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	>"$STATE_FILE"

echo "peutiy-grow-rootfs: expansion complete"
