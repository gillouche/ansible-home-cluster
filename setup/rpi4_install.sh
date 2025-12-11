#!/usr/bin/env bash

# Using a USB device as SD card reader, the device is defined as this on my computer
# the expected identifier for the SD cards are: /dev/mmcblk0 -> /dev/mmcblk0p1 and /dev/mmcblk0p2
# => the formatting and setup is done on the device ID on my computer but the config of the kernel on the device must be on the expected SD cards ID (for fstab and cmdline.txt)
export SDDEV=/dev/sdd
export SDPARTBOOT=/dev/sdd1
export SDPARTROOT=/dev/sdd2
export SDPARTBOOT_RPI=/dev/mmcblk0p1
export SDPARTROOT_RPI=/dev/mmcblk0p2

export SDMOUNT=/mnt/pi
export DOWNLOADDIR=/tmp/pi
export TAR_NAME="ArchLinuxARM-rpi-aarch64-latest.tar.gz"
export DISTURL="http://os.archlinuxarm.org/os/${TAR_NAME}"

export RPI_MODEL=$1

if [ -z $RPI_MODEL ]; then
   echo "Model argument must be provided. Possible values: 4g, 8g"
   exit 1
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
,1024M,0c,
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
echo "${SDPARTBOOT_RPI}  /boot   vfat    defaults        0       0" > ${SDMOUNT}/etc/fstab
echo "${SDPARTROOT_RPI}    /       ext4    defaults    0   0" >> ${SDMOUNT}/etc/fstab

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
fi

echo "Syncing and umounting $SDMOUNT"
sync
umount -R $SDMOUNT

# ssh/physical connect & sudo su, pw root
# ------------------------------
# 1) login as alarm/alarm
# 2) su root
# 3) switch keyboard: localectl set-keymap --no-convert be-latin1
# 4) pacman-key --init
# 5) pacman-key --populate archlinuxarm
# 6) uncomment locale in /etc/locale.gen and generate with locale-gen
# 7) pacman -Syu && pacman -S sudo python3
# 8) update /etc/sudoers to add alarm in user privilege specification like root then exit root session and execute sudo su to get rid of the first warning
# 9) from other laptop -> copy ssh key with ssh-copy-id
#
# The rest of the configuration should be done via the ansible playbooks
