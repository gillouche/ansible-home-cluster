#!/usr/bin/env bash

export SDDEV=/dev/mmcblk0
export SDPARTBOOT=/dev/mmcblk0p1
export SDPARTROOT=/dev/mmcblk0p2
export SDMOUNT=/mnt/sd
export DOWNLOADDIR=/tmp/pi
export TAR_NAME="ArchLinuxARM-rpi-aarch64-latest.tar.gz"
# export TAR_NAME="ArchLinuxARM-aarch64-latest.tar.gz"
# export TAR_NAME="ArchLinuxARM-armv7-latest.tar.gz"
export DISTURL="http://os.archlinuxarm.org/os/${TAR_NAME}"

export RPI_MODEL=$1

if [ -z $RPI_MODEL ]; then
   echo "Model argument must be provided. Possible values: 4g, 8g"
   exit -1
fi

echo "Umount $SDMOUNT"
umount -R $SDMOUNT

echo "Download ${TAR_NAME} image into $DOWNLOADDIR"
mkdir -p $DOWNLOADDIR
if [ ! -f "${DOWNLOADDIR}/${TAR_NAME}" ]; then
 cd $DOWNLOADDIR && curl -JLO $DISTURL
fi

echo "Formatting disks $SDDEV"
sfdisk --quiet --force --wipe always $SDDEV << EOF
,256M,0c,
,,L,
EOF

echo "Making partitions"
mkfs.vfat -F 32 $SDPARTBOOT
mkfs.ext4 -F $SDPARTROOT

echo "Mounting partitions"
mkdir -p $SDMOUNT
mount $SDPARTROOT $SDMOUNT
mkdir -p ${SDMOUNT}/boot
mount $SDPARTBOOT ${SDMOUNT}/boot

echo "Unzipping OS into $SDMOUNT"
bsdtar -xpf ${DOWNLOADDIR}/${TAR_NAME} -C $SDMOUNT

echo "Updating fstab -> before"
cat ${SDMOUNT}/etc/fstab

echo ""
echo "${SDPARTBOOT}  /boot   vfat    defaults        0       0" > ${SDMOUNT}/etc/fstab
echo "${SDPARTROOT}    /       ext4    defaults    0   0" >> ${SDMOUNT}/etc/fstab

if [ $RPI_MODEL == '4g' ]; then
   sed -i 's/mmcblk0/mmcblk1/g' ${SDMOUNT}/etc/fstab
fi

echo "Updating fstab -> result"
cat ${SDMOUNT}/etc/fstab

if [ $RPI_MODEL == '8g' ]; then
   echo "Updating boot/boot.txt"
   sed -i 's/${fdt_addr_r};/${fdt_addr};/g' ${SDMOUNT}/boot/boot.txt
   cd ${SDMOUNT}/boot/
   mkimage -A arm -T script -O linux -d boot.txt boot.scr
    
   # echo "Updating uboot"
   # mkdir -p ${DOWNLOADDIR}/uboot

   # pushd ${DOWNLOADDIR}/uboot
   # if [ ! -f "${DOWNLOADDIR}/uboot/uboot-raspberrypi-rc-2021.07rc3-1-aarch64.pkg.tar.xz" ]; then
   #     echo "Downloading https://kiljan.org/downloads/pi/uboot-raspberrypi-rc-2021.07rc3-1-aarch64.pkg.tar.xz"
   #     curl -JLO https://kiljan.org/downloads/pi/uboot-raspberrypi-rc-2021.07rc3-1-aarch64.pkg.tar.xz
   #     tar xf *
   # fi

   # echo "Copying kernel to ${SDMOUNT}/boot/"
   # cp boot/kernel8.img ${SDMOUNT}/boot/
   # popd
fi

echo "Syncing and umounting $SDMOUNT"
sync
umount -R $SDMOUNT
