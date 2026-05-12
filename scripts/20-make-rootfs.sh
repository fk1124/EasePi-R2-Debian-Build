#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [ -z "${SUDO:-}" ]; then
    if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
fi
DIST="${DIST:-debian}"
RELEASE="${RELEASE:-trixie}"
BRANCH="${BRANCH:-current}"
IMAGE_TYPE="${IMAGE_TYPE:-minimal}"
ROOTFS_NAME="${ROOTFS_NAME:-${DIST}-${RELEASE}-${BRANCH}-${IMAGE_TYPE}}"
ROOTFS_DIR="${REPO_DIR}/output/rootfs/${ROOTFS_NAME}"

case "${DIST}" in
    debian)
        COMPONENTS="main,contrib,non-free,non-free-firmware"
        MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
        ;;
    *) echo "ERROR: unsupported DIST: ${DIST}"; exit 1 ;;
esac

printf '\n[2/4] Create Debian %s arm64 rootfs\n' "${RELEASE}"
printf 'Rootfs directory: %s\n' "${ROOTFS_DIR}"

${SUDO} rm -rf "${ROOTFS_DIR}"
${SUDO} mkdir -p "${ROOTFS_DIR}"

${SUDO} debootstrap \
    --arch=arm64 \
    --foreign \
    --variant=minbase \
    --components="${COMPONENTS}" \
    "${RELEASE}" \
    "${ROOTFS_DIR}" \
    "${MIRROR}"

${SUDO} cp /usr/bin/qemu-aarch64-static "${ROOTFS_DIR}/usr/bin/"
${SUDO} chroot "${ROOTFS_DIR}" /debootstrap/debootstrap --second-stage

if [ -f "${REPO_DIR}/rootfs/${DIST}/sources/${RELEASE}.list" ]; then
    ${SUDO} cp "${REPO_DIR}/rootfs/${DIST}/sources/${RELEASE}.list" "${ROOTFS_DIR}/etc/apt/sources.list"
fi

cleanup_mounts() {
    ${SUDO} umount "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    ${SUDO} umount "${ROOTFS_DIR}/dev" 2>/dev/null || true
    ${SUDO} umount "${ROOTFS_DIR}/proc" 2>/dev/null || true
    ${SUDO} umount "${ROOTFS_DIR}/sys" 2>/dev/null || true
}
trap cleanup_mounts EXIT

${SUDO} mount --bind /dev "${ROOTFS_DIR}/dev"
${SUDO} mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
${SUDO} mount -t proc proc "${ROOTFS_DIR}/proc"
${SUDO} mount -t sysfs sysfs "${ROOTFS_DIR}/sys"

${SUDO} cp "${REPO_DIR}/rootfs/${DIST}/packages-minimal.txt" "${ROOTFS_DIR}/tmp/packages-minimal.txt"
if [ "${IMAGE_TYPE}" = "server" ]; then
    ${SUDO} cp "${REPO_DIR}/rootfs/${DIST}/packages-server.txt" "${ROOTFS_DIR}/tmp/packages-server.txt"
else
    ${SUDO} sh -c ": > '${ROOTFS_DIR}/tmp/packages-server.txt'"
fi

${SUDO} chroot "${ROOTFS_DIR}" /bin/bash -e <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
apt-get update
cat /tmp/packages-minimal.txt /tmp/packages-server.txt | grep -vE '^\s*(#|$)' | xargs -r apt-get install -y --no-install-recommends
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/packages-minimal.txt /tmp/packages-server.txt
CHROOT

cleanup_mounts
trap - EXIT

printf 'Rootfs created: %s\n' "${ROOTFS_DIR}"
