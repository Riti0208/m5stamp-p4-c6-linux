#!/bin/sh
set -eu

TARGET_DIR=${1:?Buildroot target directory is required}

# The generic module package used to install an unconditional modules-load.d
# entry.  Loading without board parameters locks resetpin=-1/clockspeed=0 for
# the lifetime of this NOMMU kernel, where module unload is unavailable.
rm -f "${TARGET_DIR}/etc/modules-load.d/esp-hosted-ng.conf"

# The production M3 profile performs a writable-/config gate before starting
# SSH.  The lab image deliberately uses a volatile Dropbear key and the
# Raspberry-Pi-style bring-up account, so that gate must not run first on its
# read-only squashfs root.  Keep the production script in m3/ unchanged.
rm -f "${TARGET_DIR}/etc/init.d/S10easystick-config"

for path in \
	"${TARGET_DIR}/etc/init.d/S05easystick-tmpfs" \
	"${TARGET_DIR}/etc/init.d/S40network" \
	"${TARGET_DIR}/etc/init.d/S45bootsync" \
	"${TARGET_DIR}/etc/init.d/S85easystick-ssh" \
	"${TARGET_DIR}/usr/sbin/easystick-bootsync" \
	"${TARGET_DIR}/usr/sbin/easystick-usb-lun" \
	"${TARGET_DIR}/usr/sbin/easystick-update-status" \
	"${TARGET_DIR}/etc/inetd.conf"; do
	if [ ! -f "${path}" ]; then
		echo "M3-lab file missing from rootfs: ${path}" >&2
		exit 1
	fi
done

chmod 0755 "${TARGET_DIR}/etc/init.d/S05easystick-tmpfs"
chmod 0755 "${TARGET_DIR}/etc/init.d/S40network"
chmod 0755 "${TARGET_DIR}/etc/init.d/S45bootsync"
chmod 0755 "${TARGET_DIR}/etc/init.d/S85easystick-ssh"
chmod 0755 "${TARGET_DIR}/usr/sbin/easystick-bootsync"
chmod 0755 "${TARGET_DIR}/usr/sbin/easystick-usb-lun"
chmod 0755 "${TARGET_DIR}/usr/sbin/easystick-update-status"
chmod 0644 "${TARGET_DIR}/etc/inetd.conf"

# BusyBox applet reduction (busybox.fragment) removed start-stop-daemon, ntpd
# and hwclock.  Init scripts that depend on them can only print "applet not
# found" and FAIL, and S01seedrng runs before the /var/lib overlay exists
# (read-only rootfs).  Drop them from the lab image.
rm -f "${TARGET_DIR}/etc/init.d/S01syslogd" \
	"${TARGET_DIR}/etc/init.d/S01seedrng" \
	"${TARGET_DIR}/etc/init.d/S41timesync"

# Remove applet symlinks whose applet is not built into this BusyBox, so users
# get "not found" from the shell instead of "applet not found".
for applet in \
	base32 dnsdomainname link nuke resume setpriv setserial stty zcat \
	freeramdisk hwclock ifdown ifup ip ipaddr iplink iproute mkdosfs mke2fs \
	start-stop-daemon ascii bc bzcat cksum crc32 dos2unix factor fallocate \
	fold getfattr hexedit lsscsi lzcat lzopcat mesg nl nproc od paste \
	setfattr sha1sum sha3sum sha512sum shred svc svok telnet tree truncate \
	ts tsort unix2dos unlink unlzop uudecode uuencode w wget who whoami \
	xzcat arping fsfreeze i2ctransfer mim ntpd partprobe; do
	for dir in bin sbin usr/bin usr/sbin; do
		link="${TARGET_DIR}/${dir}/${applet}"
		if [ -L "${link}" ]; then
			case "$(readlink "${link}")" in
				*busybox) rm -f "${link}" ;;
			esac
		fi
	done
done

# Lock root: an empty root password would give passwordless root as soon as a
# getty/login is used.  SSH already rejects root (-w -g).
if [ -f "${TARGET_DIR}/etc/shadow" ]; then
	sed -i 's/^root:[^:]*:/root:!:/' "${TARGET_DIR}/etc/shadow"
fi

# NOMMU has no stack guard pages: the elf2flt default of 4 KB silently corrupts
# .data/.bss on overflow.  Raise the bFLT stack for the network-facing daemons.
# 32 KB (same as micropython) keeps three Dropbear children within the RAM budget.
FLTHDR="${HOST_DIR:+${HOST_DIR}/bin/flthdr}"
if [ -n "${FLTHDR}" ] && [ -x "${FLTHDR}" ]; then
	for bin in usr/sbin/dropbear usr/bin/dbclient usr/sbin/wpa_supplicant usr/sbin/iw; do
		if [ -f "${TARGET_DIR}/${bin}" ]; then
			"${FLTHDR}" -s 32768 "${TARGET_DIR}/${bin}"
		fi
	done
else
	echo "M3-lab: flthdr not found (HOST_DIR unset); bFLT stack sizes left at default" >&2
fi
