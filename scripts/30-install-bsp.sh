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
BSP_DIR="${REPO_DIR}/output/bsp/${BRANCH}"

CREATE_USER="${CREATE_USER:-no}"
IMAGE_USER="${IMAGE_USER:-}"
IMAGE_PASSWORD="${IMAGE_PASSWORD:-}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"
LOCK_ROOT="${LOCK_ROOT:-no}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-easepi-r2}"

printf '\n[3/4] Install EasePi-R2 kernel / DTB / boot files into rootfs\n'

if [ ! -d "${ROOTFS_DIR}" ]; then
    echo "ERROR: rootfs not found: ${ROOTFS_DIR}"
    exit 1
fi

if [ ! -d "${BSP_DIR}" ]; then
    echo "ERROR: BSP directory not found: ${BSP_DIR}"
    exit 1
fi

if ! command -v mkimage >/dev/null 2>&1; then
    echo "ERROR: mkimage not found on build host."
    echo "Please install u-boot-tools first: sudo apt-get install -y u-boot-tools"
    exit 1
fi

cleanup_mounts() {
    ${SUDO} umount "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    ${SUDO} umount "${ROOTFS_DIR}/dev" 2>/dev/null || true
    ${SUDO} umount "${ROOTFS_DIR}/proc" 2>/dev/null || true
    ${SUDO} umount "${ROOTFS_DIR}/sys" 2>/dev/null || true
}
trap cleanup_mounts EXIT

${SUDO} mkdir -p "${ROOTFS_DIR}/tmp/bsp"
${SUDO} cp "${BSP_DIR}"/*.deb "${ROOTFS_DIR}/tmp/bsp/"

${SUDO} mount --bind /dev "${ROOTFS_DIR}/dev"
${SUDO} mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
${SUDO} mount -t proc proc "${ROOTFS_DIR}/proc"
${SUDO} mount -t sysfs sysfs "${ROOTFS_DIR}/sys"

${SUDO} chroot "${ROOTFS_DIR}" /bin/bash -e <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
shopt -s nullglob

DEBS=(/tmp/bsp/linux-image-*.deb /tmp/bsp/linux-dtb-*.deb)
if [ ${#DEBS[@]} -eq 0 ]; then
  echo "ERROR: no linux-image/linux-dtb debs found in /tmp/bsp"
  exit 1
fi

dpkg -i "${DEBS[@]}" || apt-get -f install -y

FW=(/tmp/bsp/armbian-firmware*.deb /tmp/bsp/linux-firmware*.deb)
if [ ${#FW[@]} -gt 0 ]; then
  dpkg -i "${FW[@]}" || apt-get -f install -y || true
fi

# initrd 是启动关键文件。这里不要再 || true，否则 initrd 生成失败也会继续打包。
update-initramfs -u -k all

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/bsp
CHROOT

cleanup_mounts
trap - EXIT

# Copy EasePi-R2 peripheral overlay directly, because this image does not rely on a full Armbian userspace.
if [ -d "${REPO_DIR}/userpatches/overlay/easepi-r2-peripherals" ]; then
    ${SUDO} rsync -a "${REPO_DIR}/userpatches/overlay/easepi-r2-peripherals/" "${ROOTFS_DIR}/"
    # eth0-eth3 are aligned by /usr/local/sbin/easepi-r2-eth-order using
    # /proc/device-tree/eth_order. Remove legacy direct .link renames to avoid
    # eth1 <-> eth2 "File exists" conflicts.
    ${SUDO} rm -f "${ROOTFS_DIR}"/etc/systemd/network/10-easepi-r2-eth{0,1,2,3}.link
    ${SUDO} chmod +x "${ROOTFS_DIR}/usr/local/sbin/easepi-r2-eth-order" 2>/dev/null || true
    ${SUDO} chmod +x "${ROOTFS_DIR}/usr/local/sbin/easepi-r2-gpu-check" 2>/dev/null || true
fi

# Basic system identity and optional account configuration.
${SUDO} tee "${ROOTFS_DIR}/etc/hostname" >/dev/null <<EOF_HOST
${TARGET_HOSTNAME}
EOF_HOST

${SUDO} tee "${ROOTFS_DIR}/etc/hosts" >/dev/null <<EOF_HOSTS
127.0.0.1 localhost
127.0.1.1 ${TARGET_HOSTNAME}

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF_HOSTS

${SUDO} chroot "${ROOTFS_DIR}" /usr/bin/env \
  CREATE_USER="${CREATE_USER}" \
  IMAGE_USER="${IMAGE_USER}" \
  IMAGE_PASSWORD="${IMAGE_PASSWORD}" \
  ROOT_PASSWORD="${ROOT_PASSWORD}" \
  LOCK_ROOT="${LOCK_ROOT}" \
  /bin/bash -e <<'CHROOT_USER'
export DEBIAN_FRONTEND=noninteractive

# 默认不创建普通用户。只有显式 CREATE_USER=yes 时才创建。
if [ "${CREATE_USER}" = "yes" ]; then
  if [ -z "${IMAGE_USER}" ] || [ -z "${IMAGE_PASSWORD}" ]; then
    echo "ERROR: CREATE_USER=yes requires IMAGE_USER and IMAGE_PASSWORD."
    exit 1
  fi

  for g in sudo adm dialout video audio plugdev netdev; do
    getent group "$g" >/dev/null 2>&1 || groupadd "$g"
  done

  if ! id -u "${IMAGE_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,adm,dialout,video,audio,plugdev,netdev "${IMAGE_USER}"
  fi

  printf '%s:%s\n' "${IMAGE_USER}" "${IMAGE_PASSWORD}" | chpasswd
else
  cat >/etc/easepi-r2-no-default-login.txt <<'EOF_NO_LOGIN'
This image was built without a default normal user.
No public default account or password is configured.

To create a user during build, run:
  CREATE_USER=yes IMAGE_USER=fk IMAGE_PASSWORD='your_password' bash build-bsp-image.sh debian trixie current minimal

To set a root password during build, run:
  ROOT_PASSWORD='your_root_password' bash build-bsp-image.sh debian trixie current minimal

If you intentionally want no built-in login account, run:
  LOCK_ROOT=yes bash build-bsp-image.sh debian trixie current minimal
EOF_NO_LOGIN
fi

# root 不设置公开默认密码。
# 默认不创建普通用户时，build-bsp-image.sh 会要求输入/传入 ROOT_PASSWORD，保证刷机后可登录。
# 只有显式 LOCK_ROOT=yes 时才锁定 root。
if [ "${LOCK_ROOT}" = "yes" ]; then
  passwd -l root || true
elif [ -n "${ROOT_PASSWORD}" ]; then
  printf 'root:%s\n' "${ROOT_PASSWORD}" | chpasswd
else
  passwd -l root || true
fi

systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true
# Safety net for custom/minimal rootfs variants: ensure router runtime exists.
# The overlay may already have written /etc/nftables.conf before nftables is
# installed. Move it away during package installation to avoid dpkg's conffile
# prompt in non-interactive chroot builds, then restore our router rules.
if ! command -v dnsmasq >/dev/null 2>&1 || ! command -v nft >/dev/null 2>&1; then
  NFT_BACKUP="/tmp/easepi-r2-nftables.conf.router"
  if [ -f /etc/nftables.conf ]; then
    mv /etc/nftables.conf "$NFT_BACKUP"
  fi
  apt-get update || true
  apt-get install -y --no-install-recommends \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    iproute2 iputils-ping ethtool bridge-utils dnsmasq nftables iptables ppp pppoe curl ca-certificates wpasupplicant hostapd || true
  if [ -f "$NFT_BACKUP" ]; then
    mv "$NFT_BACKUP" /etc/nftables.conf
  fi
fi
# EasePi-R2 is shipped as a router base: systemd-networkd owns the network.
systemctl disable NetworkManager 2>/dev/null || true
# Align EasePi-R2 RTL8125 port names before any network manager starts.
systemctl enable easepi-r2-eth-order.service 2>/dev/null || true
systemctl enable systemd-networkd 2>/dev/null || true
systemctl enable dnsmasq 2>/dev/null || true
systemctl enable nftables 2>/dev/null || true
# Multi-port router images often have unplugged LAN/backup-WAN links; waiting
# for "network-online" causes false boot failures and does not help DHCP/NAT.
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

# Native systemd-networkd router base: disable netplan configs that can generate
# /run/systemd/network/10-netplan-*.network and preempt LAN Bridge=br-lan rules.
mkdir -p /etc/easepi-r2-router/disabled-netplan-build /etc/easepi-r2-router/disabled-networkd-build
if [ -d /etc/netplan ]; then
  for f in /etc/netplan/*.yaml /etc/netplan/*.yml; do
    [ -e "$f" ] || continue
    mv "$f" "/etc/easepi-r2-router/disabled-netplan-build/$(basename "$f")" 2>/dev/null || true
  done
fi
if [ -d /etc/systemd/network ]; then
  for f in /etc/systemd/network/*.network; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    case "$b" in
      *easepi-r2*.network) ;;
      *) mv "$f" "/etc/easepi-r2-router/disabled-networkd-build/$b" 2>/dev/null || true ;;
    esac
  done
fi
rm -f /run/systemd/network/*netplan*.network 2>/dev/null || true

systemctl enable bluetooth-hciattach.service 2>/dev/null || true
systemctl enable ir-keymap.service 2>/dev/null || true

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || true
locale-gen zh_CN.UTF-8 en_US.UTF-8 2>/dev/null || true
update-locale LANG=en_US.UTF-8 2>/dev/null || true
CHROOT_USER

# Network stack is managed by systemd-networkd. NetworkManager is intentionally not configured.

# Create boot environment. ROOT_UUID is replaced during image packing.
${SUDO} mkdir -p "${ROOTFS_DIR}/boot/extlinux"
${SUDO} tee "${ROOTFS_DIR}/boot/armbianEnv.txt" >/dev/null <<'EOF_ENV'
verbosity=1
bootlogo=false
console=both
fdtfile=rockchip/rk3588-easepi-r2.dtb
rootdev=UUID=ROOT_UUID
rootfstype=ext4
extraargs=net.ifnames=1
EOF_ENV

# Prefer Armbian's official RK35xx boot script if the build tree is available.
BOOT_CMD_SRC=""
if [ -n "${ARMBIAN_BUILD_DIR:-}" ] && [ -f "${ARMBIAN_BUILD_DIR}/config/bootscripts/boot-rk35xx.cmd" ]; then
    BOOT_CMD_SRC="${ARMBIAN_BUILD_DIR}/config/bootscripts/boot-rk35xx.cmd"
elif [ -f "${REPO_DIR}/../build/config/bootscripts/boot-rk35xx.cmd" ]; then
    BOOT_CMD_SRC="${REPO_DIR}/../build/config/bootscripts/boot-rk35xx.cmd"
elif [ -f "${HOME}/rk3588_build/build/config/bootscripts/boot-rk35xx.cmd" ]; then
    BOOT_CMD_SRC="${HOME}/rk3588_build/build/config/bootscripts/boot-rk35xx.cmd"
elif [ -f "${REPO_DIR}/work/armbian-build/config/bootscripts/boot-rk35xx.cmd" ]; then
    BOOT_CMD_SRC="${REPO_DIR}/work/armbian-build/config/bootscripts/boot-rk35xx.cmd"
fi

if [ -n "${BOOT_CMD_SRC}" ]; then
    ${SUDO} cp "${BOOT_CMD_SRC}" "${ROOTFS_DIR}/boot/boot.cmd"
    ${SUDO} mkimage -C none -A arm -T script \
      -d "${ROOTFS_DIR}/boot/boot.cmd" \
      "${ROOTFS_DIR}/boot/boot.scr" >/dev/null
else
    echo "WARN: Armbian boot-rk35xx.cmd not found. Falling back to extlinux.conf."
    ${SUDO} tee "${ROOTFS_DIR}/boot/extlinux/extlinux.conf" >/dev/null <<'EOF_EXTLINUX'
default linux
menu title EasePi-R2 Boot Menu
timeout 30

label linux
    menu label Debian for EasePi-R2
    linux /Image
    initrd /uInitrd
    fdt /dtb/rockchip/rk3588-easepi-r2.dtb
    append root=UUID=ROOT_UUID rootfstype=ext4 rootwait rw console=tty1 console=ttyFIQ0,1500000n8 net.ifnames=1
EOF_EXTLINUX
fi

# Stable generic files for Armbian RK35xx boot script, extlinux, and simple boot flows.
LATEST_KERNEL="$(${SUDO} chroot "${ROOTFS_DIR}" /bin/bash -c "ls -1 /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1" | sed 's#^/boot/##')"
LATEST_INITRD="$(${SUDO} chroot "${ROOTFS_DIR}" /bin/bash -c "ls -1 /boot/initrd.img-* 2>/dev/null | sort -V | tail -1" | sed 's#^/boot/##')"

if [ -z "${LATEST_KERNEL}" ]; then
    echo "ERROR: no /boot/vmlinuz-* found after BSP install"
    exit 1
fi

if [ -z "${LATEST_INITRD}" ]; then
    echo "ERROR: no /boot/initrd.img-* found after BSP install"
    exit 1
fi

# /boot/vmlinuz is kept for generic compatibility.
${SUDO} ln -sf "${LATEST_KERNEL}" "${ROOTFS_DIR}/boot/vmlinuz"

# Armbian kernel postinst may already create /boot/Image as a symlink to vmlinuz-*.
# FAT32 boot partition does not preserve symlinks reliably, so force /boot/Image to be a real file.
${SUDO} rm -f "${ROOTFS_DIR}/boot/Image"
${SUDO} cp -f "${ROOTFS_DIR}/boot/${LATEST_KERNEL}" "${ROOTFS_DIR}/boot/Image"

# /boot/initrd.img is kept for generic compatibility.
${SUDO} ln -sf "${LATEST_INITRD}" "${ROOTFS_DIR}/boot/initrd.img"

# Armbian RK35xx boot script loads /boot/uInitrd, not /boot/initrd.img.
# FAT32 boot partition should receive a real uInitrd file.
${SUDO} rm -f "${ROOTFS_DIR}/boot/uInitrd"
${SUDO} mkimage -A arm64 -O linux -T ramdisk -C none -n uInitrd \
  -d "${ROOTFS_DIR}/boot/${LATEST_INITRD}" \
  "${ROOTFS_DIR}/boot/uInitrd"

# Final boot-file sanity check.
for f in \
  armbianEnv.txt \
  Image \
  uInitrd \
  dtb/rockchip/rk3588-easepi-r2.dtb
do
    if [ ! -e "${ROOTFS_DIR}/boot/${f}" ]; then
        echo "ERROR: missing boot file: /boot/${f}"
        exit 1
    fi
done

if [ ! -e "${ROOTFS_DIR}/boot/boot.scr" ] && [ ! -e "${ROOTFS_DIR}/boot/extlinux/extlinux.conf" ]; then
    echo "ERROR: missing boot loader config: /boot/boot.scr or /boot/extlinux/extlinux.conf"
    exit 1
fi

printf 'BSP installed into rootfs.\n'
