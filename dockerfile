FROM ubuntu:22.04
# RUN sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list && \
#     sed -i s@/security.ubuntu.com/@/mirrors.ustc.edu.cn/@g /etc/apt/sources.list && \
#     sed -i s@/ports.ubuntu.com/@/mirrors.ustc.edu.cn/@g /etc/apt/sources.list  && \
#     echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/02apt-speedup && \
#     echo "Acquire::http {No-Cache=True;};" > /etc/apt/apt.conf.d/no-cache && \
#     echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/no-lang
RUN	apt update && \
apt -y install wget bzip2 xz-utils lib32z1 cmake vim 

RUN wget https://ftp.denx.de/pub/u-boot/u-boot-2024.01.tar.bz2
# COPY ./u-boot-2024.01.tar.bz2 /
RUN tar xvf u-boot-2024.01.tar.bz2
RUN rm -r u-boot-2024.01.tar.bz2


RUN wget https://releases.linaro.org/components/toolchain/binaries/7.5-2019.12/aarch64-linux-gnu/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz
RUN tar -xvf gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz
# RUN cd gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu && 
RUN mv gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu /opt/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu
RUN ln -sf /opt/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin/*  /usr/bin/


RUN apt-get install -y bison libncurses-dev flex

# /usr/local/arm64/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu$



RUN apt-get update && apt-get install -y python3 pip swig  git bc libusb-1.0-0-dev pkg-config

RUN git clone https://github.com/ARM-software/arm-trusted-firmware.git
# COPY ./arm-trusted-firmware /arm-trusted-firmware
RUN cd arm-trusted-firmware && make CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50i_h616 DEBUG=1 bl31


RUN  git clone https://github.com/linux-sunxi/sunxi-tools
# COPY ./sunxi-tools /sunxi-tools
RUN apt-get install -y  libfdt-dev
RUN  cd /sunxi-tools && make

RUN apt-get install -y libssl-dev

RUN apt-get install -y usbutils rsync



COPY ./uboot_config /u-boot-2024.01/.config
COPY ./axp305.c /u-boot-2024.01/drivers/power/axp305.c
COPY ./dram_sun50i_h616.c arch/arm/mach-sunxi/dram_sun50i_h616.c
RUN cd u-boot-2024.01 && make CROSS_COMPILE=aarch64-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin orangepi_zero2_defconfig -j8

RUN cd u-boot-2024.01 && make CROSS_COMPILE=aarch64-linux-gnu- BL31=../arm-trusted-firmware/build/sun50i_h616/debug/bl31.bin -j8

RUN wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.0.19.tar.gz
# COPY ./linux-6.0.19.tar.gz /
RUN tar -xvf linux-6.0.19.tar.gz
RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j8 Image
RUN  cd linux-6.0.19/ &&  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j8 dtbs
RUN  cd linux-6.0.19/ && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j8 modules
#RUN  apt install -y depmod
RUN  cd linux-6.0.19/ && mkdir MINSTALL && mkdir HINSTALL
RUN  cd linux-6.0.19/ &&  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=./MINSTALL  modules modules_install
RUN  cd linux-6.0.19/ &&   make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install



RUN wget https://buildroot.org/downloads/buildroot-2022.02.5.tar.gz
RUN tar -xvf buildroot-2022.02.5.tar.gz
COPY ./buildroot.config /buildroot-2022.02.5/.config
RUN apt install -y file cpio unzip
RUN cd /buildroot-2022.02.5 && make -j8

# RUN  git clone -b h616-v13 https://github.com/apritzel/linux
RUN   git clone https://github.com/lwfinger/rtl8723ds
RUN echo "start downloads linux apritzel"

RUN git clone https://github.com/apritzel/linux.git -b h616-v13

# RUN apt install -y dkmop
# RUN make -j8
# RUN git clone -b h616-v13 https://github.com/apritzel/linux
# RUN git clone https://github.com/lwfinger/rtl8723ds 
# RUN cp /rtl8723ds /linux/drivers/net/wireless/realtek/rtl8723ds

# 14  ls
#   115  cd linux-6.0.19/
#   116  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
#   117  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j8 Image
#   118  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j8 dtbs
#   119  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j8 modules
#   120  ls
#   121  mkdir MINSTALL
#   122  mkdir HINSTALL
#   123  ake ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=./MINSTALL  modules modules_install
#   124  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=./MINSTALL  modules modules_install
#   125  make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install
#   126  apt-get install rsync
#   127  make ARCH=arm64 INSTALL_HDR_PATH=HINSTALL headers_install
#   128  sudo dd if=../u-boot-2024.01/u-boot-sunxi-with-spl.bin of=/dev/sdc bs=8K seek=1
#   129  dd if=../u-boot-2024.01/u-boot-sunxi-with-spl.bin of=/dev/sdc bs=8K seek=1
#   130  ls /dev
#   131  sudo /dev/sdd1 /mnt/boot/
#   132  mount /dev/sdd1 /mnt/boot/
#   133  cd /mnt/
#   134  ls
#   135  mkdir boot
#   136  cd /linux-6.0.19/
#   137  ls
#   138  mount /dev/sdd1 /mnt/boot/
#   139  mount /dev/sdc1 /mnt/boot/
#   140  cp ./arch/arm64/boot/Image /mnt/boot/
#   141  cp ./arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb /mnt/boot/
#   142  umount /mnt/boot
#   143  history
# root@yu-Vostro-15-3562:/li


# RUN wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.0.19.tar.gz
# RUN git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git


# /opt/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/aarch64-linux-gnu/libc/usr/include/linux/version.h
# apt install file cpio  unzip
