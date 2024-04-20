#!/usr/bin/env bash

# https://kiljan.org/2023/11/24/arch-linux-arm-on-a-raspberry-pi-5-model-b/

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
export DISTURL="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz"

echo "Download ${TAR_NAME} image into $DOWNLOADDIR"
mkdir -p $DOWNLOADDIR
if [ ! -f "${DOWNLOADDIR}/${TAR_NAME}" ]; then
 cd $DOWNLOADDIR && curl -JLO $DISTURL
fi

echo "Umount $SDMOUNT"
umount -R $SDMOUNT

echo "Formatting disks $SDDEV"
sfdisk --quiet --wipe always $SDDEV << EOF
,256M,0c,
,,,
EOF

echo "Making partitions"
mkfs.vfat -F 32 $SDPARTBOOT
mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0 -F $SDPARTROOT

echo "Mounting partitions"
mkdir -p $SDMOUNT
mount $SDPARTROOT $SDMOUNT
mkdir -p ${SDMOUNT}/boot
mount $SDPARTBOOT ${SDMOUNT}/boot

echo "Unzipping OS into $SDMOUNT"
bsdtar -xpf ${DOWNLOADDIR}/ArchLinuxARM-rpi-aarch64-latest.tar.gz -C $SDMOUNT --no-same-owner

echo "Updating fstab -> before"
cat ${SDMOUNT}/etc/fstab

echo ""
echo "${SDPARTBOOT_RPI}  /boot   vfat    defaults        0       0" > ${SDMOUNT}/etc/fstab
echo "${SDPARTROOT_RPI}    /       ext4    defaults    0   0" >> ${SDMOUNT}/etc/fstab

echo "Updating fstab -> after"
cat ${SDMOUNT}/etc/fstab

echo "Removing ${SDMOUNT}/boot/*"
rm -rf ${SDMOUNT}/boot/*

echo "Downloading kernel"
mkdir -p ${DOWNLOADDIR}/linux-rpi

echo "Cleaning kernel directory if any"
rm -rf ${DOWNLOADDIR}/linux-rpi/*

pushd ${DOWNLOADDIR}/linux-rpi
curl -JLO http://mirror.archlinuxarm.org/aarch64/core/linux-rpi-6.6.26-2-aarch64.pkg.tar.xz
tar xf *
cp -rf boot/* ${SDMOUNT}/boot/
popd

echo "Sync and umount all"
sync && umount -R $SDMOUNT

# ssh/physical connect & sudo su, pw root
# ------------------------------
# 1) login as alarm/alarm
# 2) the home of alarm user has root permissions so: su root
# 3) chown -R alarm:alarm /home/alarm
# 4) switch keyboard: localectl set-keymap --no-convert be-latin1
# 5) pacman-key --init
# 6) pacman-key --populate archlinuxarm
# 6) uncomment locale in /etc/locale.gen and generate with locale-gen
# 7) pacman -R linux-aarch64 uboot-raspberrypi
# 8) pacman -Syu --overwrite "/boot/*" linux-rpi-16k sudo python3
# 9) update /etc/sudoers to add alarm in user privilege specification like root then exit root session and execute sudo su to get rid of the first warning
# 10) from other laptop -> copy ssh key with ssh-copy-id
# 
# The rest of the configuration should be done via the ansible playbooks
