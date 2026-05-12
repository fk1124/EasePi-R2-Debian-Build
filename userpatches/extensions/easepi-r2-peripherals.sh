# EasePi-R2 Peripherals Extension: IR + AP6255 Bluetooth + systemd-networkd router base
# This extension intentionally keeps the classic userpatches/extensions/*.sh path
# for broad Armbian compatibility, while reading overlay files from the kit's
# userpatches/overlay/easepi-r2-peripherals directory.

function extension_prepare_config__easepi_r2_peripherals() {
	display_alert "Extension: EasePi-R2 Peripherals" "IR + Bluetooth + networkd router base" "info"
}

function pre_customize_image__copy_easepi_r2_peripheral_files() {
	display_alert "EasePi-R2" "Copying peripheral overlay files" "info"

	local OVERLAY_DIR=""

	# Preferred path inside the active Armbian build tree.
	if [[ -n "${SRC:-}" && -d "${SRC}/userpatches/overlay/easepi-r2-peripherals" ]]; then
		OVERLAY_DIR="${SRC}/userpatches/overlay/easepi-r2-peripherals"
	# Fallback: if EXTENSION_DIR is available and overlay sits next to extension.
	elif [[ -n "${EXTENSION_DIR:-}" && -d "${EXTENSION_DIR}/overlay" ]]; then
		OVERLAY_DIR="${EXTENSION_DIR}/overlay"
	fi

	if [[ -z "${OVERLAY_DIR}" || ! -d "${OVERLAY_DIR}" ]]; then
		display_alert "EasePi-R2" "Peripheral overlay not found; skipping IR/BT files" "wrn"
		return 0
	fi

	mkdir -p "${SDCARD}"
	cp -a "${OVERLAY_DIR}/." "${SDCARD}/"
	# eth0-eth3 are aligned by the early easepi-r2-eth-order service. Remove
	# legacy direct .link renames that cannot safely swap eth1 and eth2.
	rm -f "${SDCARD}"/etc/systemd/network/10-easepi-r2-eth{0,1,2,3}.link
	rm -f "${SDCARD}/etc/modprobe.d/99-easepi-r2-panthor-manual-only.conf"
	rm -f "${SDCARD}/usr/local/sbin/easepi-r2-gpu-check"
	chmod +x "${SDCARD}/usr/local/sbin/easepi-r2-eth-order" 2>/dev/null || true

	if [[ -f "${SDCARD}/usr/local/sbin/bluetooth-hciattach.sh" ]]; then
		chmod +x "${SDCARD}/usr/local/sbin/bluetooth-hciattach.sh"
	fi


	if [[ -f "${SDCARD}/usr/local/ir/fix_infrared.sh" ]]; then
		chmod +x "${SDCARD}/usr/local/ir/fix_infrared.sh"
	fi
}

function post_customize_image__enable_easepi_r2_peripheral_services() {
	display_alert "EasePi-R2" "Enabling peripheral services" "info"

	# Armbian's extension path does not consume rootfs/debian/packages-*.txt.
	# Install the router runtime explicitly so first boot has working DHCP/NAT.
	# Important: the overlay already contains /etc/nftables.conf. If nftables is
	# installed after that file exists, dpkg asks a conffile question and Armbian's
	# non-interactive chroot build fails with "end of file on stdin". Temporarily
	# move our custom nftables.conf away, install packages, then restore it. The
	# dpkg options are kept as an additional guard for future conffile changes.
	display_alert "EasePi-R2" "Installing router runtime packages" "info"
	local R2_NFT_BACKUP="${SDCARD}/tmp/easepi-r2-nftables.conf.router"
	mkdir -p "${SDCARD}/tmp"
	if [[ -f "${SDCARD}/etc/nftables.conf" ]]; then
		mv "${SDCARD}/etc/nftables.conf" "${R2_NFT_BACKUP}"
	fi
	chroot_sdcard apt-get update || true
	chroot_sdcard apt-get install -y --no-install-recommends \
		-o Dpkg::Options::=--force-confdef \
		-o Dpkg::Options::=--force-confold \
		iproute2 iputils-ping ethtool bridge-utils \
		dnsmasq nftables iptables \
		ppp pppoe curl ca-certificates \
		wpasupplicant hostapd || true
	if [[ -f "${R2_NFT_BACKUP}" ]]; then
		mv "${R2_NFT_BACKUP}" "${SDCARD}/etc/nftables.conf"
	fi

	if [[ -f "${SDCARD}/etc/systemd/system/ir-keymap.service" ]]; then
		chroot_sdcard systemctl enable ir-keymap.service || true
	fi

	if [[ -f "${SDCARD}/etc/systemd/system/bluetooth-hciattach.service" ]]; then
		chroot_sdcard systemctl enable bluetooth-hciattach.service || true
	fi


	# Router base: systemd-networkd owns WAN/LAN/lte4g, dnsmasq serves br-lan DHCP, nftables does NAT.
	# Disable netplan YAML because generated /run/systemd/network/10-netplan-*.network
	# can win systemd-networkd first-match before EasePi-R2 bridge slave files.
	mkdir -p "${SDCARD}/etc/easepi-r2-router/disabled-netplan-build" "${SDCARD}/etc/easepi-r2-router/disabled-networkd-build"
	if [[ -d "${SDCARD}/etc/netplan" ]]; then
		find "${SDCARD}/etc/netplan" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -exec mv -t "${SDCARD}/etc/easepi-r2-router/disabled-netplan-build" {} + 2>/dev/null || true
	fi
	if [[ -d "${SDCARD}/etc/systemd/network" ]]; then
		for f in "${SDCARD}"/etc/systemd/network/*.network; do
			[[ -e "$f" ]] || continue
			b="$(basename "$f")"
			case "$b" in
				*easepi-r2*.network) ;;
				*) mv "$f" "${SDCARD}/etc/easepi-r2-router/disabled-networkd-build/$b" 2>/dev/null || true ;;
			esac
		done
	fi
	chroot_sdcard systemctl disable NetworkManager.service || true
	# Align RTL8125 interface names before any network manager starts.
	chroot_sdcard systemctl enable easepi-r2-eth-order.service || true
	chroot_sdcard systemctl enable systemd-networkd.service || true
	chroot_sdcard systemctl enable dnsmasq.service || true
	chroot_sdcard systemctl enable nftables.service || true
	# This service only waits for network-online and commonly times out on router
	# devices with unplugged LAN/backup-WAN ports. It is not needed for DHCP/NAT.
	chroot_sdcard systemctl disable systemd-networkd-wait-online.service || true
	chroot_sdcard systemctl mask systemd-networkd-wait-online.service || true

	chroot_sdcard systemctl enable bluetooth.service || true
}
