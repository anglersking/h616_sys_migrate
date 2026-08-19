FROM ubuntu:22.04

# ====== 一次性安装所有 apt 包（减少 layer） ======
RUN apt update && \
    apt -y install \
        wget bzip2 xz-utils lib32z1 cmake vim \
        bison libncurses-dev flex \
        python3 pip swig git bc libusb-1.0-0-dev pkg-config \
        libfdt-dev libssl-dev usbutils rsync \
        file cpio unzip u-boot-tools \
        libelf-dev apt-utils kmod dosfstools e2fsprogs fdisk mtools \
        debootstrap qemu-user-static debian-archive-keyring || \
    true

# ====== ARM 10.3 交叉编译器 ======
RUN wget --no-check-certificate https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-a/10.3-2021.07/binrel/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz && \
    tar -xJf gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz && \
    mv gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu /opt/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu && \
    ln -sf /opt/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/* /usr/bin/ && \
    rm gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu.tar.xz

# ====== ARM Trusted Firmware (bl31) ======
RUN git clone https://github.com/ARM-software/arm-trusted-firmware.git && \
    cd arm-trusted-firmware && make CROSS_COMPILE=aarch64-none-linux-gnu- PLAT=sun50i_h616 DEBUG=1 bl31

# ====== sunxi-tools ======
RUN git clone https://github.com/linux-sunxi/sunxi-tools && \
    cd /sunxi-tools && make

# ====== U-Boot ======
RUN wget https://ftp.denx.de/pub/u-boot/u-boot-2024.01.tar.bz2 && \
    tar xvf u-boot-2024.01.tar.bz2 && \
    rm u-boot-2024.01.tar.bz2

COPY ./uboot_config /u-boot-2024.01/.config
COPY ./axp305.c /u-boot-2024.01/drivers/power/axp305.c
COPY ./dram_sun50i_h616.c /u-boot-2024.01/arch/arm/mach-sunxi/dram_sun50i_h616.c
ARG KERNEL_JOBS=auto
RUN cd u-boot-2024.01 && \
    make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin orangepi_zero2_defconfig && \
    jobs="${KERNEL_JOBS}" && \
    if [ "$jobs" = "auto" ]; then jobs="$(nproc)"; fi && \
    make CROSS_COMPILE=aarch64-none-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin -j"$jobs"

# ====== Yuzuki H616 主线内核 ======
# Use the same display patches as the known-good Yuzuki mainline image.  The
# Yuzuki repository is a large hardware archive, so only the kernel portions
# are checked out and overlaid on the matching upstream 5.16.17 source.
ARG YUZUKI_H616_BRANCH=develop
ARG YUZUKI_H616_REPO=https://github.com/dumtux/Allwinner-H616.git
RUN git -c http.version=HTTP/1.1 clone --filter=blob:none --no-checkout --sparse \
        --depth 1 --branch "${YUZUKI_H616_BRANCH}" \
        "${YUZUKI_H616_REPO}" /yuzuki-h616 && \
    git -C /yuzuki-h616 sparse-checkout set \
        kernel/.config \
        kernel/arch/arm64/boot/dts/allwinner \
        kernel/drivers/gpu/drm \
        kernel/drivers/clk \
        kernel/drivers/pinctrl \
        kernel/drivers/phy \
        kernel/include/dt-bindings \
        kernel/include/drm \
        kernel/include/uapi/drm && \
    git -C /yuzuki-h616 checkout --quiet
RUN wget https://mirrors.tuna.tsinghua.edu.cn/kernel/v5.x/linux-5.16.17.tar.xz && \
    tar -xJf linux-5.16.17.tar.xz && \
    rm linux-5.16.17.tar.xz
ENV KERNEL_DIR=/linux-5.16.17
RUN cp -a /yuzuki-h616/kernel/arch/arm64/boot/dts/allwinner/. \
        ${KERNEL_DIR}/arch/arm64/boot/dts/allwinner/ && \
    cp -a /yuzuki-h616/kernel/drivers/gpu/drm/. ${KERNEL_DIR}/drivers/gpu/drm/ && \
    cp -a /yuzuki-h616/kernel/drivers/clk/. ${KERNEL_DIR}/drivers/clk/ && \
    cp -a /yuzuki-h616/kernel/drivers/pinctrl/. ${KERNEL_DIR}/drivers/pinctrl/ && \
    cp -a /yuzuki-h616/kernel/drivers/phy/. ${KERNEL_DIR}/drivers/phy/ && \
    cp -a /yuzuki-h616/kernel/include/dt-bindings/. \
        ${KERNEL_DIR}/include/dt-bindings/ && \
    cp -a /yuzuki-h616/kernel/include/drm/. \
        ${KERNEL_DIR}/include/drm/ && \
    cp -a /yuzuki-h616/kernel/include/uapi/drm/. \
        ${KERNEL_DIR}/include/uapi/drm/ && \
    cp /yuzuki-h616/kernel/.config ${KERNEL_DIR}/.config

# ====== Wi-Fi 驱动 ======
RUN git config --global http.postBuffer 524288000 && \
    git clone https://github.com/lwfinger/rtl8723ds && \
    git clone https://github.com/YuzukiHD/Xradio-XR829.git -b 5.15

# The Yuzuki kernel is 5.16.17; keep the driver sources in-tree so the
# existing Wi-Fi options can be resolved by olddefconfig.

# 无线驱动拷入内核树。XR829 的 5.15 分支需要针对 Linux 5.16 的
# cfg80211 频道切换接口和 AMPDU 常量做兼容处理。
RUN cp -r /rtl8723ds ${KERNEL_DIR}/drivers/net/wireless/realtek/rtl8723ds && \
    cp -r /Xradio-XR829 ${KERNEL_DIR}/drivers/net/wireless/realtek/xr829 && \
    sed -i '27s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        ${KERNEL_DIR}/drivers/net/wireless/realtek/xr829/include/net/mac80211.h && \
    sed -i '96s/#ifdef CONFIG_MAC80211_RC_MINSTREL || CONFIG_XRMAC_RC_MINSTREL/#if defined(CONFIG_MAC80211_RC_MINSTREL) || defined(CONFIG_XRMAC_RC_MINSTREL)/' \
        ${KERNEL_DIR}/drivers/net/wireless/realtek/xr829/umac/rate.h && \
    sed -i -e '1286s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '2764s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '3039s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '3331s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '3584s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '3826s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '3889s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '4219s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '/params->count);/s/params->count);/params->count, false);/' \
        ${KERNEL_DIR}/drivers/net/wireless/realtek/xr829/umac/cfg.c && \
    sed -i -e '1231s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '1421s/KERNEL_VERSION(5, 15, 0)/KERNEL_VERSION(6, 0, 0)/' \
        -e '/csa_ie.count);/s/csa_ie.count);/csa_ie.count, false);/' \
        ${KERNEL_DIR}/drivers/net/wireless/realtek/xr829/umac/mlme.c

COPY ./rtl8Kconfig /linux-5.16.17/drivers/net/wireless/realtek/rtl8723ds/Kconfig
COPY ./realtek_Kconfig /linux-5.16.17/drivers/net/wireless/realtek/Kconfig
COPY ./linux_main_realtek_Makefile /linux-5.16.17/drivers/net/wireless/realtek/Makefile

# The Yuzuki source already contains the matching H616 DE/TCON/HDMI/PHY DTSI.
# Do not replace it with the older 6.0.19 compatibility DTSI.

# ====== 自定义 DTS（Yuzuki HDMI + 4-wire SPI ST7789 + Ethernet/WiFi） ======
COPY ./main_sun50i-h616-orangepi-zero2.dts /linux-5.16.17/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dts

# ====== 内核配置（内建 Yuzuki DRM/DW HDMI 与 fbtft ST7789V） ======
COPY ./yuzuki_kernel.fragment /tmp/yuzuki_kernel.fragment

# ====== 编译内核 ======
RUN cd ${KERNEL_DIR} && \
    jobs="${KERNEL_JOBS}" && \
    if [ "$jobs" = "auto" ]; then jobs="$(nproc)"; fi && \
    scripts/kconfig/merge_config.sh -m .config /tmp/yuzuki_kernel.fragment && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- olddefconfig && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j"$jobs" Image && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j"$jobs" dtbs && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- -j"$jobs" modules && \
    mkdir -p MINSTALL HINSTALL && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- INSTALL_MOD_PATH=./MINSTALL modules_install && \
    make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install

# ====== boot.scr ======
COPY ./boot.cmd /linux-5.16.17/boot.cmd
RUN cd ${KERNEL_DIR} && mkimage -C none -A arm64 -T script -d boot.cmd boot.scr

# ====== Buildroot ======
# Buildroot 2022.02's BusyBox configuration invokes recursive make. Keep the
# Linux default while allowing Docker Desktop to avoid its broken pipe
# jobserver and parallelize each package with all assigned CPUs.
ARG BUILDROOT_JOBS=auto
ARG BUILDROOT_USE_MAKE_WRAPPER=0
ARG BUILDROOT_PRIMARY_SITE=
RUN wget https://buildroot.org/downloads/buildroot-2022.02.5.tar.gz && \
    tar -xvf buildroot-2022.02.5.tar.gz && \
    rm buildroot-2022.02.5.tar.gz
COPY ./buildroot.config /buildroot-2022.02.5/.config
COPY ./make-no-jobserver.sh /usr/local/bin/make-no-jobserver
RUN chmod +x /usr/local/bin/make-no-jobserver
RUN if [ -n "${BUILDROOT_PRIMARY_SITE}" ]; then \
        sed -i "s|^BR2_PRIMARY_SITE=.*|BR2_PRIMARY_SITE=\"${BUILDROOT_PRIMARY_SITE}\"|" /buildroot-2022.02.5/.config; \
    fi && \
    cd /buildroot-2022.02.5 && \
    make olddefconfig && \
    jobs="${BUILDROOT_JOBS}" && \
    if [ "$jobs" = "auto" ]; then jobs="$(nproc)"; fi && \
    if [ "${BUILDROOT_USE_MAKE_WRAPPER}" = "1" ]; then \
        MAKE_NO_JOBSERVER_JOBS="$jobs" MAKEFLAGS= MFLAGS= \
            make MAKE=/usr/local/bin/make-no-jobserver -j1; \
    else \
        MAKEFLAGS= make -j"$jobs"; \
    fi

# Buildroot 第二遍（最终配置）
COPY ./buildroot_finally_config /buildroot-2022.02.5/.config
RUN if [ -n "${BUILDROOT_PRIMARY_SITE}" ]; then \
        sed -i "s|^BR2_PRIMARY_SITE=.*|BR2_PRIMARY_SITE=\"${BUILDROOT_PRIMARY_SITE}\"|" /buildroot-2022.02.5/.config; \
    fi && \
    cd /buildroot-2022.02.5 && \
    make olddefconfig && \
    jobs="${BUILDROOT_JOBS}" && \
    if [ "$jobs" = "auto" ]; then jobs="$(nproc)"; fi && \
    if [ "${BUILDROOT_USE_MAKE_WRAPPER}" = "1" ]; then \
        MAKE_NO_JOBSERVER_JOBS="$jobs" MAKEFLAGS= MFLAGS= \
            make MAKE=/usr/local/bin/make-no-jobserver -j1; \
    else \
        MAKEFLAGS= make -j"$jobs"; \
    fi

# ====== 把内核模块装进 Buildroot target ======
RUN mkdir -p /buildroot-2022.02.5/output/target/lib/modules && \
    cp -r ${KERNEL_DIR}/MINSTALL/lib/modules/* /buildroot-2022.02.5/output/target/lib/modules/

# ====== Debian bullseye rootfs ======
RUN mkdir -p /path/to/rootfs && \
    debootstrap --foreign --arch=arm64 bullseye /path/to/rootfs https://mirrors.tuna.tsinghua.edu.cn/debian/ && \
    cp /usr/bin/qemu-aarch64-static /path/to/rootfs/usr/bin/ && \
    chroot /path/to/rootfs /usr/bin/qemu-aarch64-static /bin/bash -c "/debootstrap/debootstrap --second-stage" || \
    echo "WARNING: debootstrap second-stage failed (need binfmt_misc), skipping Debian rootfs"

COPY ./peutiy-hdmi-console.sh /path/to/rootfs/usr/local/sbin/peutiy-hdmi-console
COPY ./peutiy-hdmi-console.service /path/to/rootfs/etc/systemd/system/peutiy-hdmi-console.service

# Debian's bootstrap root account is locked by default. These credentials are
# solely for first-boot HDMI/serial diagnostics and must be changed afterward.
RUN test ! -f /path/to/rootfs/etc/debian_version || \
    chroot /path/to/rootfs /usr/bin/qemu-aarch64-static /bin/bash -ceu '\
	sed -i -E "s/^(deb(-src)?[[:space:]]+[^[:space:]]+[[:space:]]+bullseye[[:space:]]+).*/\\1main contrib non-free/" /etc/apt/sources.list; \
	DEBIAN_FRONTEND=noninteractive apt-get update; \
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	    kbd fbset iproute2 iw wpasupplicant bluez rfkill wireless-regdb firmware-realtek; \
	apt-get clean; \
	rm -rf /var/lib/apt/lists/*; \
        echo "root:peutiy" | chpasswd; \
        useradd --create-home --shell /bin/bash peutiy; \
        echo "peutiy:peutiy" | chpasswd; \
	chmod 0755 /usr/local/sbin/peutiy-hdmi-console; \
        mkdir -p /etc/systemd/system/getty.target.wants; \
        ln -sf /lib/systemd/system/getty@.service \
	    /etc/systemd/system/getty.target.wants/getty@tty1.service; \
	mkdir -p /etc/systemd/system/multi-user.target.wants; \
	ln -sf /etc/systemd/system/peutiy-hdmi-console.service \
	    /etc/systemd/system/multi-user.target.wants/peutiy-hdmi-console.service'

# ====== 产物整理到 /out ======
RUN grep -q 'sun50i-h616-orangepi-zero2.dtb' \
        ${KERNEL_DIR}/arch/arm64/boot/dts/allwinner/Makefile || \
    printf '\ndtb-$(CONFIG_ARCH_SUNXI) += sun50i-h616-orangepi-zero2.dtb\n' >> \
        ${KERNEL_DIR}/arch/arm64/boot/dts/allwinner/Makefile && \
    make -C ${KERNEL_DIR} ARCH=arm64 CROSS_COMPILE=aarch64-none-linux-gnu- dtbs
RUN mkdir -p /out/buildroot /out/debian /out/image /out/dtb /out/bootscr /out/uboot /out/modules && \
    cp ${KERNEL_DIR}/arch/arm64/boot/Image /out/image/ && \
    cp ${KERNEL_DIR}/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /out/dtb/ && \
    cp ${KERNEL_DIR}/boot.scr /out/bootscr/ && \
    cp -r ${KERNEL_DIR}/MINSTALL/lib /out/modules/ && \
    cp /u-boot-2024.01/u-boot-sunxi-with-spl.bin /out/uboot/ && \
    cp /buildroot-2022.02.5/output/images/rootfs.ext2 /out/buildroot/ && \
    cp /buildroot-2022.02.5/output/images/rootfs.tar /out/buildroot/ && \
    if [ -f /path/to/rootfs/etc/debian_version ]; then cp -a /path/to/rootfs/. /out/debian/; fi

# ====== 入口脚本 ======
COPY ./entrypoint.sh /entrypoint.sh
COPY ./sdcard_make/shuaxie.sh /shuaxie.sh
COPY ./sdcard_make/mksdimg-portable.sh /usr/local/bin/mksdimg-portable
RUN chmod a+x /entrypoint.sh /shuaxie.sh /usr/local/bin/mksdimg-portable
