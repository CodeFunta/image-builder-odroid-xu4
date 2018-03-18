#!/bin/bash
set -x
# This script should be run only inside of a Docker container
if [ ! -f /.dockerenv ]; then
  echo "ERROR: script works only in a Docker container!"
  exit 1
fi
# get versions for software that needs to be installed
# shellcheck disable=SC1091
source /workspace/versions.config

### setting up some important variables to control the build process

# place to store our created sd-image file
BUILD_RESULT_PATH="/workspace"

# place to build our sd-image
BUILD_PATH="/build"

ROOTFS_TAR="rootfs-armhf-debian-${HYPRIOT_OS_VERSION}.tar.gz"
ROOTFS_TAR_PATH="${BUILD_RESULT_PATH}/${ROOTFS_TAR}"

# Show TRAVSI_TAG in travis builds
echo TRAVIS_TAG="${TRAVIS_TAG}"

# size of root and boot partion (in MByte)
BOOT_PARTITION_START="3072"

ROOT_PARTITION_START="266240"
ROOT_PARTITION_SIZE="1000"
#---don't change here---
BOOT_PARTITION_OFFSET="$((BOOT_PARTITION_START*512))"
ROOT_PARTITION_OFFSET="$((ROOT_PARTITION_START*512))"
#---don't change here---

# name of the sd-image we gonna create
HYPRIOT_IMAGE_VERSION=${VERSION:="dirty"}
HYPRIOT_IMAGE_NAME="hypriotos-odroid-xu4-${HYPRIOT_IMAGE_VERSION}.img"
IMAGE_ROOTFS_PATH="/image_with_kernel_root.tar.gz"
export HYPRIOT_IMAGE_VERSION



# create build directory for assembling our image filesystem
rm -rf ${BUILD_PATH}
mkdir ${BUILD_PATH}
mkdir -p ${BUILD_PATH}/{boot,root}

# download files
if [ ! -f "${BUILD_RESULT_PATH}/bl1.bin.hardkernel" ]; then
  wget -q -O "${BUILD_RESULT_PATH}/bl1.bin.hardkernel" "https://github.com/hardkernel/u-boot/blob/odroidxu4-v2017.05/sd_fuse/bl1.bin.hardkernel?raw=true"
fi
if [ ! -f "${BUILD_RESULT_PATH}/bl2.bin.hardkernel.720k_uboot" ]; then
  wget -q -O "${BUILD_RESULT_PATH}/bl2.bin.hardkernel.720k_uboot" "https://github.com/hardkernel/u-boot/blob/odroidxu4-v2017.05/sd_fuse/bl2.bin.hardkernel.720k_uboot?raw=true"
fi
if [ ! -f "${BUILD_RESULT_PATH}/tzsw.bin.hardkernel" ]; then
  wget -q -O "${BUILD_RESULT_PATH}/tzsw.bin.hardkernel" "https://github.com/hardkernel/u-boot/blob/odroidxu4-v2017.05/sd_fuse/tzsw.bin.hardkernel?raw=true"
fi
if [ ! -f "${BUILD_RESULT_PATH}/u-boot.bin.hardkernel" ]; then
  wget -q -O "${BUILD_RESULT_PATH}/u-boot.bin.hardkernel" "https://github.com/hardkernel/u-boot/blob/odroidxu4-v2017.05/sd_fuse/u-boot.bin.hardkernel?raw=true"
fi


#---create image file---
dd if=/dev/zero of="/${HYPRIOT_IMAGE_NAME}" bs=1MiB count=${ROOT_PARTITION_SIZE}

signed_bl1_position=1
bl2_position=31
uboot_position=63
tzsw_position=1503
env_position=2015

dd conv=notrunc iflag=dsync oflag=dsync if="${BUILD_RESULT_PATH}/bl1.bin.hardkernel" of="/${HYPRIOT_IMAGE_NAME}" seek=$signed_bl1_position
dd conv=notrunc iflag=dsync oflag=dsync if="${BUILD_RESULT_PATH}/bl2.bin.hardkernel.720k_uboot" of="/${HYPRIOT_IMAGE_NAME}" seek=$bl2_position
dd conv=notrunc iflag=dsync oflag=dsync if="${BUILD_RESULT_PATH}/u-boot.bin.hardkernel" of="/${HYPRIOT_IMAGE_NAME}" seek=$uboot_position
dd conv=notrunc iflag=dsync oflag=dsync if="${BUILD_RESULT_PATH}/tzsw.bin.hardkernel" of="/${HYPRIOT_IMAGE_NAME}" seek=$tzsw_position
#<u-boot env erase>
dd conv=notrunc iflag=dsync oflag=dsync if=/dev/zero of="/${HYPRIOT_IMAGE_NAME}" seek=$env_position bs=512 count=32


echo -e "o\nn\np\n1\n$BOOT_PARTITION_START\n$((ROOT_PARTITION_START-1))\nn\np\n2\n$ROOT_PARTITION_START\n\nt\n1\nc\nw\n" | fdisk "/${HYPRIOT_IMAGE_NAME}"

#-partition #1 - fat32
#losetup -d /dev/loop0 || /bin/true
losetup -o ${BOOT_PARTITION_OFFSET} /dev/loop0 "/${HYPRIOT_IMAGE_NAME}"
mkfs.vfat -n boot /dev/loop0
#//-partition #1 - fat32

#-partition #2 - ex4
#losetup -d /dev/loop1 || /bin/true
losetup -o ${ROOT_PARTITION_OFFSET} /dev/loop1 "/${HYPRIOT_IMAGE_NAME}"
mkfs.ext4 -O ^has_journal -b 4096 -L rootfs -U e139ce78-9841-40fe-8823-96a304a09859 /dev/loop1
#//-partition #1 - ex4

losetup -d /dev/loop0
losetup -d /dev/loop1
sleep 3

#-test mount and write a file
mount -t ext4 -o loop=/dev/loop1,offset=${ROOT_PARTITION_OFFSET} "/${HYPRIOT_IMAGE_NAME}" ${BUILD_PATH}/root
echo "HypriotOS: root partition" > ${BUILD_PATH}/root/root.txt
tree -a ${BUILD_PATH}/
df -h
umount ${BUILD_PATH}/root

# log image partioning
fdisk -l "/${HYPRIOT_IMAGE_NAME}"




# download our base root file system
if [ ! -f "${ROOTFS_TAR_PATH}" ]; then
  wget -q -O "${ROOTFS_TAR_PATH}" "https://github.com/hypriot/os-rootfs/releases/download/${HYPRIOT_OS_VERSION}/${ROOTFS_TAR}"
fi

# verify checksum of our root filesystem
echo "${ROOTFS_TAR_CHECKSUM} ${ROOTFS_TAR_PATH}" | sha256sum -c -

# extract root file system
tar xf "${ROOTFS_TAR_PATH}" -C "${BUILD_PATH}"

# register qemu-arm with binfmt
# to ensure that binaries we use in the chroot
# are executed via qemu-arm
update-binfmts --enable qemu-arm

# set up mount points for the pseudo filesystems
mkdir -p ${BUILD_PATH}/{proc,sys,dev/pts}

mount -o bind /dev ${BUILD_PATH}/dev
mount -o bind /dev/pts ${BUILD_PATH}/dev/pts
mount -t proc none ${BUILD_PATH}/proc
mount -t sysfs none ${BUILD_PATH}/sys

# modify/add image files directly
# e.g. root partition resize script
cp -R /builder/files/* ${BUILD_PATH}/

# make our build directory the current root
# and install the firmware, kernel packages,
# docker tools and some customizations
chroot ${BUILD_PATH} /bin/bash < /builder/chroot-script.sh

# unmount pseudo filesystems
umount -l ${BUILD_PATH}/dev/pts
umount -l ${BUILD_PATH}/dev
umount -l ${BUILD_PATH}/proc
umount -l ${BUILD_PATH}/sys

#####
# package image filesytem into two tarballs - one for bootfs and one for rootfs
# ensure that there are no leftover artifacts in the pseudo filesystems
rm -rf ${BUILD_PATH}/{dev,sys,proc}/*

cp -R /builder/files/boot/* ${BUILD_PATH}/media/boot/
tar -czf /image_with_kernel_boot.tar.gz -C ${BUILD_PATH}/media/boot .
du -sh ${BUILD_PATH}/media/boot

# rm -Rf ${BUILD_PATH}/media/boot
# rm -Rf ${BUILD_PATH}/boot

tar -czf $IMAGE_ROOTFS_PATH -C ${BUILD_PATH} .
du -sh ${BUILD_PATH}
ls -alh /image_with_kernel_*.tar.gz
#####

#---copy rootfs to image file---
mount -t ext4 -o loop=/dev/loop1,offset=${ROOT_PARTITION_OFFSET} "/${HYPRIOT_IMAGE_NAME}" ${BUILD_PATH}/root
tar -xzf ${IMAGE_ROOTFS_PATH} -C ${BUILD_PATH}/root
df -h
umount ${BUILD_PATH}/root
#---copy rootfs to image file---

#---copy bootfs to image file---
mount -t vfat -o loop=/dev/loop0,offset=${BOOT_PARTITION_OFFSET} "/${HYPRIOT_IMAGE_NAME}" ${BUILD_PATH}/boot
tar -xzf /image_with_kernel_boot.tar.gz -C ${BUILD_PATH}/boot
df -h
umount ${BUILD_PATH}/boot

#---copy bootfs to image file---

# log image partioning
fdisk -l "/${HYPRIOT_IMAGE_NAME}"

# ensure that the travis-ci user can access the sd-card image file
umask 0000

# compress image
zip "${BUILD_RESULT_PATH}/${HYPRIOT_IMAGE_NAME}.zip" "${HYPRIOT_IMAGE_NAME}"
cd ${BUILD_RESULT_PATH} && sha256sum "${HYPRIOT_IMAGE_NAME}.zip" > "${HYPRIOT_IMAGE_NAME}.zip.sha256" && cd -

# test sd-image that we have built
#VERSION=${HYPRIOT_IMAGE_VERSION} rspec --format documentation --color ${BUILD_RESULT_PATH}/builder/test
