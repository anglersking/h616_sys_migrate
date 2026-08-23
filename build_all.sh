#!/bin/sh
# Peutiy-Pi 一键构建 + SD 镜像制作
# 用法: sh build_all.sh [OUTDIR] [SIZE_MB]
# 默认 OUTDIR: macOS 为当前目录的 out，Linux 为 /mnt/nvme0n1-4/out

set -e

HOST_OS=$(uname -s)
if [ "$#" -ge 1 ]; then
    OUTDIR=$1
elif [ "$HOST_OS" = "Darwin" ]; then
    OUTDIR="$PWD/out"
else
    OUTDIR=/mnt/nvme0n1-4/out
fi
SIZE_MB="${2:-1024}"

# Apple Silicon cannot execute the Dockerfile's x86_64-hosted ARM toolchain
# natively. Docker Desktop's linux/amd64 emulation keeps the build identical
# to the Linux build. Intel Macs also use this path without emulation.
DOCKER_PLATFORM=""
DOCKER_NETWORK="host"
BUILDROOT_BUILD_ARG="--build-arg BUILDROOT_JOBS=auto"
if [ "$HOST_OS" = "Darwin" ]; then
    DOCKER_PLATFORM="--platform=linux/amd64"
    DOCKER_NETWORK="default"
    BUILDROOT_BUILD_ARG="$BUILDROOT_BUILD_ARG --build-arg BUILDROOT_USE_MAKE_WRAPPER=1 --build-arg BUILDROOT_PRIMARY_SITE=https://sources.buildroot.net"
fi

echo "============================================"
echo "  Peutiy-Pi Build & SD Image Maker"
echo "============================================"

# Step 1: Docker build (编译)
echo ""
echo "=== Step 1/3: docker build ==="
BUILD_STATUS_FILE=$(mktemp "${TMPDIR:-/tmp}/peutiy-build-status.XXXXXX")
cleanup_build_status() {
    rm -f "$BUILD_STATUS_FILE"
}
trap cleanup_build_status EXIT HUP INT TERM
(
    set +e
    docker build $DOCKER_PLATFORM $BUILDROOT_BUILD_ARG \
        --network="$DOCKER_NETWORK" -t h616_core_build .
    printf '%s\n' "$?" >"$BUILD_STATUS_FILE"
) 2>&1 | tee build.log
BUILD_STATUS=$(cat "$BUILD_STATUS_FILE")
rm -f "$BUILD_STATUS_FILE"
trap - EXIT HUP INT TERM
if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "ERROR: docker build failed with status $BUILD_STATUS" >&2
    exit "$BUILD_STATUS"
fi
echo "=== Build DONE ==="

# Step 2: 提取产物到宿主机
echo ""
echo "=== Step 2/3: Extract artifacts to ${OUTDIR} ==="
mkdir -p "$OUTDIR"
CID=$(docker create $DOCKER_PLATFORM h616_core_build)
for artifact in image dtb bootscr uboot modules buildroot; do
    docker cp "$CID:/out/$artifact" "$OUTDIR/"
done
docker rm "$CID"

# macOS host filesystems cannot hold Linux device nodes from /dev. Preserve
# them in a tar stream and unpack it only inside the Linux image builder.
if docker run --rm $DOCKER_PLATFORM h616_core_build \
    /bin/sh -c 'test -f /out/debian/etc/debian_version'; then
    docker run --rm $DOCKER_PLATFORM h616_core_build \
        tar -C /out/debian -cf - . >"$OUTDIR/debian-rootfs.tar"
fi
echo "=== Artifacts extracted ==="

# Step 3: 制作 SD 镜像。Linux 保持既有 loop 流程；macOS 使用免 loop 流程。
echo ""
echo "=== Step 3/3: Create SD images ==="
if [ "$HOST_OS" = "Darwin" ]; then
    docker run --rm $DOCKER_PLATFORM \
        -v "$OUTDIR:/out" \
        h616_core_build /usr/local/bin/mksdimg-portable "/out" "$SIZE_MB"
else
    cp sdcard_make/mksdimg.sh "$OUTDIR/"
    chmod +x "$OUTDIR/mksdimg.sh"
    docker run --rm --privileged \
        -v /dev:/dev \
        -v "$OUTDIR:/out" \
        h616_core_build bash /out/mksdimg.sh "/out" "$SIZE_MB"
fi

echo ""
echo "============================================"
echo "  ALL DONE"
echo "  ${OUTDIR}/sdcard_buildroot.img"
echo "  ${OUTDIR}/sdcard_debian.img"
echo "============================================"
ls -lh "$OUTDIR"/sdcard_*.img
