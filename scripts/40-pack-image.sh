#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [ -z "${SUDO:-}" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    else
        SUDO="sudo"
    fi
fi

DIST="${DIST:-debian}"
RELEASE="${RELEASE:-trixie}"
BRANCH="${BRANCH:-current}"
IMAGE_TYPE="${IMAGE_TYPE:-minimal}"

ROOTFS_NAME="${ROOTFS_NAME:-${DIST}-${RELEASE}-${BRANCH}-${IMAGE_TYPE}}"
IMAGE_NAME="${IMAGE_NAME:-EasePi-R2-${DIST}-${RELEASE}-${BRANCH}-${IMAGE_TYPE}}"

ROOTFS_DIR="${REPO_DIR}/output/rootfs/${ROOTFS_NAME}"
BSP_DIR="${REPO_DIR}/output/bsp/${BRANCH}"
IMAGE_DIR="${REPO_DIR}/output/images"
TMP_DIR="${REPO_DIR}/output/tmp/pack-${ROOTFS_NAME}"
IMG="${IMAGE_DIR}/${IMAGE_NAME}.img"

# FAT32 /boot partition size.
#
# Debian minimal normally fits in 256 MB. Increase BOOT_SIZE_MB manually
# if your kernel, firmware, or initramfs becomes larger.
# Armbian native images do not use this BSP pack script.
#
# Manual override example:
#   BOOT_SIZE_MB=512 bash build-bsp-image.sh debian trixie current minimal
BOOT_START_MIB="${BOOT_START_MIB:-16}"
BOOT_SIZE_MB="${BOOT_SIZE_MB:-256}"

BOOT_END_MIB=$((BOOT_START_MIB + BOOT_SIZE_MB))

printf '\n[4/4] Pack bootable image\n'

if [ ! -d "${ROOTFS_DIR}" ]; then
    echo "ERROR: rootfs not found: ${ROOTFS_DIR}"
    exit 1
fi

if [ ! -d "${ROOTFS_DIR}/boot" ]; then
    echo "ERROR: rootfs /boot not found: ${ROOTFS_DIR}/boot"
    exit 1
fi

mkdir -p "${IMAGE_DIR}" "${TMP_DIR}"
rm -f "${IMG}" "${IMG}.xz" "${IMG}.sha" "${IMG}.xz.sha256"

ROOTFS_MB="$(${SUDO} du -sm "${ROOTFS_DIR}" | awk '{print $1}')"

# The image needs space for:
# - rootfs partition
# - dedicated FAT32 /boot partition
# - free space for filesystem metadata, logs, first boot resize, apt cache, etc.
AUTO_SIZE_MB=$((ROOTFS_MB + BOOT_SIZE_MB + 1024))
if [ "${AUTO_SIZE_MB}" -lt 4096 ]; then
    AUTO_SIZE_MB=4096
fi
IMAGE_SIZE_MB="${IMAGE_SIZE_MB:-${AUTO_SIZE_MB}}"

printf 'Rootfs size: %s MB\n' "${ROOTFS_MB}"
printf 'Boot partition: %s MiB - %s MiB (%s MB)\n' "${BOOT_START_MIB}" "${BOOT_END_MIB}" "${BOOT_SIZE_MB}"
printf 'Image size: %s MB\n' "${IMAGE_SIZE_MB}"

truncate -s "${IMAGE_SIZE_MB}M" "${IMG}"

parted -s "${IMG}" mklabel gpt
parted -s "${IMG}" mkpart boot fat32 "${BOOT_START_MIB}MiB" "${BOOT_END_MIB}MiB"
parted -s "${IMG}" set 1 boot on
parted -s "${IMG}" mkpart rootfs ext4 "${BOOT_END_MIB}MiB" 100%

LOOP=""
MNT_ROOT="${TMP_DIR}/root"
MNT_BOOT="${TMP_DIR}/boot"

cleanup() {
    set +e
    ${SUDO} sync 2>/dev/null || true
    ${SUDO} umount "${MNT_BOOT}" 2>/dev/null || true
    ${SUDO} umount "${MNT_ROOT}" 2>/dev/null || true
    if [ -n "${LOOP}" ]; then
        ${SUDO} losetup -d "${LOOP}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

LOOP="$(${SUDO} losetup --find --show --partscan "${IMG}")"
sleep 1

${SUDO} mkfs.vfat -F 32 -n BOOT "${LOOP}p1" >/dev/null
${SUDO} mkfs.ext4 -F -L rootfs "${LOOP}p2" >/dev/null

mkdir -p "${MNT_ROOT}" "${MNT_BOOT}"
${SUDO} mount "${LOOP}p2" "${MNT_ROOT}"
${SUDO} mount "${LOOP}p1" "${MNT_BOOT}"

# --------------------------------------------------------------------
# Copy rootfs and boot files
# --------------------------------------------------------------------
#
# /boot is a FAT32 partition. FAT32 does not support Linux symlinks.
# Armbian kernel packages create normal boot symlinks such as:
#
#   /boot/Image      -> vmlinuz-xxx
#   /boot/vmlinuz    -> vmlinuz-xxx
#   /boot/initrd.img -> initrd.img-xxx
#   /boot/dtb        -> dtb-xxx
#
# Therefore:
#   1. Copy rootfs to ext4 root partition, excluding /boot contents.
#   2. Copy real /boot contents to FAT32, excluding symlink aliases.
#   3. Materialize required aliases as real files/directories.
# --------------------------------------------------------------------

printf 'Copying rootfs to ext4 root partition...\n'
${SUDO} rsync -aHAX --numeric-ids \
    --exclude='/boot/*' \
    "${ROOTFS_DIR}/" "${MNT_ROOT}/"

${SUDO} mkdir -p "${MNT_ROOT}/boot"
${SUDO} mkdir -p "${MNT_BOOT}"

printf 'Copying /boot to FAT32 boot partition...\n'
${SUDO} rsync -rt --delete \
    --no-perms --no-owner --no-group \
    --exclude='/Image' \
    --exclude='/vmlinuz' \
    --exclude='/initrd.img' \
    --exclude='/dtb' \
    --exclude='/vmlinuz.old' \
    --exclude='/initrd.img.old' \
    "${ROOTFS_DIR}/boot/" "${MNT_BOOT}/"

copy_boot_alias_as_real() {
    local alias_name="$1"
    local src="${ROOTFS_DIR}/boot/${alias_name}"
    local dst="${MNT_BOOT}/${alias_name}"

    [ -e "${src}" ] || [ -L "${src}" ] || return 0

    ${SUDO} rm -rf "${dst}"

    if [ -d "${src}" ] && [ ! -L "${src}" ]; then
        ${SUDO} mkdir -p "${dst}"
        ${SUDO} rsync -rt --delete \
            --no-perms --no-owner --no-group \
            "${src}/" "${dst}/"
    else
        # -L dereferences symlinks, so FAT32 receives a real file/directory.
        ${SUDO} cp -aL "${src}" "${dst}"
    fi
}

# U-Boot / Armbian commonly expects these names.
copy_boot_alias_as_real "Image"
copy_boot_alias_as_real "vmlinuz"
copy_boot_alias_as_real "initrd.img"
copy_boot_alias_as_real "dtb"

BOOT_USED_KB="$(${SUDO} du -sk "${MNT_BOOT}" | awk '{print $1}')"
BOOT_USED_MB=$(((BOOT_USED_KB + 1023) / 1024))
printf 'Boot partition used: %s MB / %s MB\n' "${BOOT_USED_MB}" "${BOOT_SIZE_MB}"

if [ "${BOOT_USED_MB}" -ge $((BOOT_SIZE_MB - 16)) ]; then
    echo "ERROR: /boot is almost full after copying files."
    echo "Try a larger boot partition, for example:"
    echo "  BOOT_SIZE_MB=768 bash build-bsp-image.sh ${DIST} ${RELEASE} ${BRANCH} ${IMAGE_TYPE}"
    exit 1
fi

BOOT_UUID="$(${SUDO} blkid -s UUID -o value "${LOOP}p1")"
ROOT_UUID="$(${SUDO} blkid -s UUID -o value "${LOOP}p2")"

${SUDO} tee "${MNT_ROOT}/etc/fstab" >/dev/null <<EOF_FSTAB
UUID=${ROOT_UUID} / ext4 defaults,noatime,commit=600,errors=remount-ro 0 1
UUID=${BOOT_UUID} /boot vfat defaults 0 2
tmpfs /tmp tmpfs defaults,nosuid 0 0
EOF_FSTAB

if [ -f "${MNT_BOOT}/armbianEnv.txt" ]; then
    ${SUDO} sed -i "s/ROOT_UUID/${ROOT_UUID}/g" "${MNT_BOOT}/armbianEnv.txt"
fi

if [ -f "${MNT_BOOT}/extlinux/extlinux.conf" ]; then
    ${SUDO} sed -i "s/ROOT_UUID/${ROOT_UUID}/g" "${MNT_BOOT}/extlinux/extlinux.conf"
fi

# Extract and write Rockchip U-Boot loader.
UBOOT_DEB="$(find "${BSP_DIR}" -maxdepth 1 -type f -name '*u-boot*.deb' | head -n 1 || true)"
if [ -z "${UBOOT_DEB}" ]; then
    echo "ERROR: u-boot deb not found in ${BSP_DIR}"
    exit 1
fi

rm -rf "${TMP_DIR}/u-boot"
mkdir -p "${TMP_DIR}/u-boot"
dpkg-deb -x "${UBOOT_DEB}" "${TMP_DIR}/u-boot"

UBOOT_ROCKCHIP="$(find "${TMP_DIR}/u-boot" -type f -name 'u-boot-rockchip.bin' | head -n 1 || true)"
IDBLOADER="$(find "${TMP_DIR}/u-boot" -type f \( -name 'idbloader.img' -o -name 'idbloader.bin' \) | head -n 1 || true)"
UBOOT_ITB="$(find "${TMP_DIR}/u-boot" -type f -name 'u-boot.itb' | head -n 1 || true)"

if [ -n "${UBOOT_ROCKCHIP}" ]; then
    printf 'Writing U-Boot: %s\n' "${UBOOT_ROCKCHIP}"
    dd if="${UBOOT_ROCKCHIP}" of="${IMG}" bs=32k seek=1 conv=notrunc status=none
elif [ -n "${IDBLOADER}" ] && [ -n "${UBOOT_ITB}" ]; then
    printf 'Writing Rockchip idbloader + u-boot.itb\n'
    dd if="${IDBLOADER}" of="${IMG}" bs=512 seek=64 conv=notrunc status=none
    dd if="${UBOOT_ITB}" of="${IMG}" bs=512 seek=16384 conv=notrunc status=none
else
    echo "ERROR: cannot find u-boot-rockchip.bin or idbloader.img + u-boot.itb in ${UBOOT_DEB}"
    find "${TMP_DIR}/u-boot" -type f | sed 's/^/  /'
    exit 1
fi

cleanup
trap - EXIT

# Shrink ext4 before compression when possible.
set +e
LOOP_SHRINK="$(${SUDO} losetup --find --show --partscan "${IMG}")"
${SUDO} e2fsck -fy "${LOOP_SHRINK}p2" >/dev/null 2>&1
${SUDO} resize2fs -M "${LOOP_SHRINK}p2" >/dev/null 2>&1
${SUDO} losetup -d "${LOOP_SHRINK}" >/dev/null 2>&1
set -e

xz -T0 -z -k -f "${IMG}"
sha256sum "${IMG}.xz" > "${IMG}.xz.sha256"

printf 'Image created:\n'
printf '  %s\n' "${IMG}"
printf '  %s.xz\n' "${IMG}"
printf '  %s.xz.sha256\n' "${IMG}"
