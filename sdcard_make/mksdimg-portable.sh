#!/bin/sh
# Create the SD image without loop devices or mounts.
# This works in Docker Desktop on macOS as well as on Linux.

set -eu

OUTDIR="${1:-/out}"
SIZE_MB="${2:-1024}"
P1_START=40960
P1_END=303104
P2_START=303105
SECTOR_SIZE=512
P1_SECTORS=$((P1_END - P1_START + 1))
TOTAL_SECTORS=$((SIZE_MB * 1024 * 1024 / SECTOR_SIZE))
P2_SECTORS=$((TOTAL_SECTORS - P2_START))

if [ "$P2_SECTORS" -le 0 ]; then
    echo "ERROR: image size must be larger than $((P2_START * SECTOR_SIZE / 1024 / 1024)) MiB" >&2
    exit 1
fi

for file in \
    "$OUTDIR/uboot/u-boot-sunxi-with-spl.bin" \
    "$OUTDIR/image/Image" \
    "$OUTDIR/dtb/sun50i-h616-orangepi-zero2.dtb" \
    "$OUTDIR/bootscr/boot.scr" \
    "$OUTDIR/modules/lib"; do
    if [ ! -e "$file" ]; then
        echo "ERROR: required artifact is missing: $file" >&2
        exit 1
    fi
done

WORKDIR=$(mktemp -d)
cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT HUP INT TERM

make_img() {
    name="$1"
    rootfs_source="$2"
    rootfs_type="$3"
    image="$OUTDIR/$name"
    boot_image="$WORKDIR/boot.img"
    root_image="$WORKDIR/root.img"
    root_dir="$WORKDIR/rootdir"

    echo "=== Creating $name (${SIZE_MB}M) ==="
    rm -f "$image" "$boot_image" "$root_image"
    rm -rf "$root_dir"
    mkdir -p "$root_dir"

    dd if=/dev/zero of="$image" bs=1M count="$SIZE_MB" status=none
    sfdisk "$image" <<EOF
label: dos
unit: sectors

start=$P1_START, size=$P1_SECTORS, type=c
start=$P2_START, size=$P2_SECTORS, type=83
EOF

    dd if=/dev/zero of="$boot_image" bs="$SECTOR_SIZE" count="$P1_SECTORS" status=none
    mkfs.fat -F 32 "$boot_image" >/dev/null
    mcopy -i "$boot_image" \
        "$OUTDIR/image/Image" \
        "$OUTDIR/dtb/sun50i-h616-orangepi-zero2.dtb" \
        "$OUTDIR/bootscr/boot.scr" ::/

    if [ "$rootfs_type" = "tar" ]; then
        tar xf "$rootfs_source" -C "$root_dir"
    else
        cp -a "$rootfs_source/." "$root_dir/"
    fi
    mkdir -p "$root_dir/lib"
    cp -a "$OUTDIR/modules/lib/." "$root_dir/lib/"

    truncate -s $((P2_SECTORS * SECTOR_SIZE)) "$root_image"
    mkfs.ext4 -F -d "$root_dir" "$root_image" >/dev/null

    dd if="$OUTDIR/uboot/u-boot-sunxi-with-spl.bin" of="$image" bs=8K seek=1 conv=notrunc status=none
    dd if="$boot_image" of="$image" bs="$SECTOR_SIZE" seek="$P1_START" conv=notrunc status=none
    dd if="$root_image" of="$image" bs="$SECTOR_SIZE" seek="$P2_START" conv=notrunc status=none
    echo "=== $name OK ==="
}

make_img sdcard_buildroot.img "$OUTDIR/buildroot/rootfs.tar" tar

if [ -f "$OUTDIR/debian-rootfs.tar" ]; then
    make_img sdcard_debian.img "$OUTDIR/debian-rootfs.tar" tar
elif [ -f "$OUTDIR/debian/etc/debian_version" ]; then
    make_img sdcard_debian.img "$OUTDIR/debian" copy
else
    echo "=== Skipping sdcard_debian.img (no Debian rootfs) ==="
fi

ls -lh "$OUTDIR"/sdcard_*.img
