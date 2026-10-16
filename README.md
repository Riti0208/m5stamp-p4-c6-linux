# M5Stamp ESP32-P4 + C6 SDIO Linux (SMP kernel, experimental dual-core)

[![License](https://img.shields.io/badge/license-GPL--2.0--only-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--P4%20%2B%20ESP32--C6-orange.svg)](https://m5stack.com)
[![CPU](https://img.shields.io/badge/SMP-Experimental%20Dual--Core%20RV32IMAC-yellow.svg)](https://github.com/tsuyoshi-otake/m5stamp-p4-c6-linux/releases)

A reproducible RISC-V NOMMU Linux 6.18 distribution (SMP kernel; the shipped image runs on one core, dual-core is experimental, see below) for the **M5Stack Stamp-P4** carrier board paired with **Stamp-AddOn C6** (via 4-bit SDIO interface).

Boots out-of-the-box into **Wi-Fi SoftAP mode** with automatic DHCP, Dropbear SSH server, BusyBox `vi`, MicroPython (`python3`), and a writable OverlayFS on `/home`, `/root`, and `/var/lib`.

<p align="center">
  <img src="docs/images/ssh-session-dual-core-smp.png" alt="M5Stamp ESP32-P4 + C6 Dual-Core SMP SSH Session" width="650">
  <br>
  <em>Live SSH session on M5Stamp ESP32-P4 + C6 from an experimental dual-core run (CPU0 and CPU1) via SDIO Wi-Fi; the shipped image boots with <code>maxcpus=1</code>.</em>
</p>

---

## Key Features & Verified Hardware Capabilities

- **SoC Target**: ESP32-P4 (Dual-Core RV32IMAC / ilp32, CPU clock 360 MHz as reported by the boot-shim, 32 MiB PSRAM, 16 MiB SPI Flash).
- **SMP (experimental)**: The kernel is built with SMP (`Linux 6.18.35 #1 SMP riscv32 GNU/Linux`), but the shipped DTB boots with `maxcpus=1`, so only CPU0 is online (`/sys/devices/system/cpu/online` = `0`). With `maxcpus=2`, about one boot in five stalls during userland start (issue #5): CPU1 stops accepting any interrupt (timer and IPI stay pending and enabled) and the rest of the system waits on it. Adding `isolcpus=1` to the kernel command line avoided the stall in 17 of 17 boots and a 568 s soak, but leaves CPU1 almost unused; see `linux/tests/m3-lab-hardware-validation-2026-10-14.md`. A stalled board may need a re-flash over USB. `maxcpus` in `/boot/config.txt` is informational and is not read by anything.
- **Wi-Fi Companion**: ESP32-C6 (M5Stack Stamp-AddOn C6) connected via 4-bit SDIO (5 MHz by default, up to 40 MHz with `sdio_mhz=`, see [SDIO clock](#c6-firmware-security-features--regulatory-notes)).
- **Out-of-the-Box SoftAP**:
  - Broadcasts a per-device SSID **`m5-XXXX`** with a WPA2-PSK passphrase generated on first boot (see [Per-device credentials](#per-device-credentials)).
  - Integrated `udhcpd` DHCP server assigning client IPs in `192.168.4.2` – `192.168.4.20` (Gateway: `192.168.4.1`).
- **Pre-installed Developer Tools**:
  - **SSH Server**: Password-enabled Dropbear on TCP port 22 (user `m5`, per-device password from `credentials.txt`). inetd accepts up to 20 new connections a minute, then stops listening for 60 s.
  - **`vi` Editor**: Full-featured BusyBox `vi` with search, undo, visual buffers, and syntax assistance.
  - **MicroPython (`python3`)**: MicroPython v1.22.2 compiled with bFLT Load-to-Ram (`-r`) and position-independent code (`-fPIC`) for stable NOMMU execution.
  - **Writable Filesystem (OverlayFS)**: While the root filesystem is SquashFS (read-only for durability), RAM-backed OverlayFS is mounted on `/home`, `/root`, and `/var/lib` so users can create and edit scripts during the current boot. Its contents are lost when power is removed.
  - **USB Mass Storage (`/boot` drive, optional hardware)**: With the [optional EasyStick carrier](#optional-hardware-easystick-usb-mass-storage-carrier), its Type-A USB connection (GPIO26/27) exposes a FAT-formatted 256KB `/boot` configuration drive to Windows/Mac/Linux hosts. A safe eject applies validated settings immediately; a normal reboot commits the image through redundant A/B flash slots.
- **Kernel & SoC Stabilization**:
  - Full-Speed DWC2 USB OTG driver hardened with PIO mode and dedicated TX FIFO empty interrupt management, eliminating descriptor DMA coherency panics and enabling stable multi-block transfers.
  - Signal delivery `mcause` hardening (`0014`).
  - L2 unified cache & DMA reentrancy hardening (`0015`).
  - Systimer 52-bit atomic multi-word read and missed-alarm mitigation (`0016`).
  - Dual-core systimer lock and CPU1 context switch tracking (`0042`, `0044`, `0045`, `0046`).
  - USB CDC-ACM 64-byte TX FIFO bounded polling (`0062`), eliminating full-screen editor (`vi`) and TUI terminal lockups.
  - Early CRNG entropy initialization via `seedrng` on OverlayFS, preventing `getrandom()` system call stalls.
  - SDIO DW-MMC host controller driver enhancements with software DTO and buffer pacing (`0032`, `0033`, `0060`, `0061`).
  - NOMMU user memory: programs load into a 10 MB reserved pool in two regions (6 MB + 4 MB, `0070`) instead of the fragmented page allocator, so SSH logins, `S40network restart` and console commands no longer fail with `nommu: Allocation of length … failed` (#23). Each BusyBox process still takes about 500 KB, because bFLT programs do not share their text. The m3-lab image therefore runs init, inetd, syslogd and udhcpd from `busybox-daemons`, a second BusyBox built with only those four applets (192 KB each). At idle that leaves about 1 MB more of the pool free, which is one more concurrent SSH session (5–6 instead of 4–5; `linux/tests/busybox-daemons-2026-10-16.md`). `MemAvailable` does not change, because it does not count the pool.

---

## Serial Access, Troubleshooting & Recovery

Linux / macOS serial examples, how to open the console without resetting the board, troubleshooting and flash backup / recovery are in [docs/troubleshooting.md](docs/troubleshooting.md).

## C6 Firmware, Security Features & Regulatory Notes

- **C6 firmware**: Linux expects the ESP32-C6 to run ESP-Hosted NG 1.0.6 (the driver logs `ESP-Hosted Version: NG-1.0.6.0.1`). The release images flash the P4 only; a C6 running another version may fail to attach over SDIO. Check the version in the boot log: a mismatch is logged as `Incompatible ESP Host-firmware release detected` with both versions, and no log line at all means the C6 is not running ESP-Hosted NG. See [Updating the C6](#updating-the-c6).
- **SDIO clock**: the driver requests 5 MHz unless `sdio_mhz=` in `config.txt` picks 1, 2, 10, 20 or 40 (applied at the next boot, logged as `ES_SDIO_CLOCK_APPLY requested_mhz=...` in dmesg). The DTS caps the bus at 40 MHz, and the MMC core enumerates the C6 at 20 MHz before the driver sets its rate. Measured in station mode over the home Wi-Fi (`linux/tests/sdio-clock-2026-10-16.md`): PC to board over raw TCP 300–330 KB/s at 5 MHz, 410–440 KB/s at 40 MHz; SSH 210–220 KB/s at 5 MHz, about 250 KB/s at 40 MHz, where Dropbear's crypto on the single 360 MHz core is the limit. 40 MHz passed the boot checks on 10 resets; it has not been soaked for hours, so 5 MHz stays the default (#21).
- **Secure Boot and flash encryption are disabled.** Physical access allows reading the flash (including Wi-Fi credentials in the boot FAT) and writing arbitrary firmware. See [SECURITY.md](SECURITY.md).
- **Wi-Fi regulatory domain**: no `country=` is set by default, so the world regulatory domain applies. Set `country=` in `config.txt` for your region.
- **Wi-Fi security**: WPA2-PSK only. Protected management frames are opt-in (`wifi_pmf=1`); in station mode the v0.2.2 image joined an access point with it, while a SoftAP client negotiating PMF has not been tested. WPA3-SAE is not built.

### Updating the C6

The C6 on the Stamp AddOn has no USB port of its own; it is updated over the SDIO link from the P4 with a temporary P4 updater image, after which the Linux image is written back.

1. Build the C6 image: `bash linux/m2/build-c6.sh --vendor <out>` (needs the locked ESP-IDF; `EASYSTICK_C6_BT=0` leaves out BLE, which Linux does not use). `<out>/C6_PATCH_MANIFEST.txt` records the `network_adapter.bin` SHA-256 and the applied patches.
2. Build the updater: `bash linux/m2/build-ota-host.sh <external-source-root> <out>/build/network_adapter.bin <ota-out>` (the source root holds `esp_idf` and an `esp_hosted_mcu` checkout). It uses ESP-Hosted-MCU's `host_performs_slave_ota` example.
3. Save a full 16 MB readback of the P4 first, then write the updater with `linux/m2/ota-host/flash-ota-host.ps1` (it refuses to run without `-AllowCandidateWrite` and a matching stock readback). The updater sends the C6 image over SDIO on its next boot.
4. Write the Linux release image again and check the boot log for `ESP-Hosted Version: NG-1.0.6.0.1`.

`tools/readback-c6-ng.ps1` reads the C6 flash through a C6 programmer port, if you have one wired, so the original C6 firmware can be kept. The SDIO update path was used during bring-up (`linux/tests/wlan0-regression-bisect-2026-08-12.md`); it is not part of the release workflow.

## Default Credentials & Connection

| Service | SSID / Host | Username | Password | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Wi-Fi SoftAP** | `m5-XXXX` | — | `psk=` in `credentials.txt` | WPA2-PSK, 2.4 GHz 802.11b/g/n, channel 1/6/11 |
| **SSH (`dropbear`)**| `192.168.4.1:22` | `m5` | `password=` in `credentials.txt` | Default user with home directory `/home/m5` |
| **Runtime status** | SSH / serial | — | — | Read `/run/easystick-status.txt`; the USB FAT image is not modified while exported |
| **Serial Console** | `COMx` (115200 8N1) | *(root shell)* | *(none)* | `ttyGS1` over USB-Serial/JTAG. Press `Enter` to activate |

### Per-device credentials

Every board gets its own credentials on first boot; no SSID or password is shared between boards.

- On first boot `S05easystick-tmpfs` writes `credentials.txt` to the USB drive: `device_id=`, `password=` (SSH/console password of user `m5`), and, while `wpa_supplicant.conf` is still the shipped default, `ssid=m5-<device_id>` and `psk=`. That `wpa_supplicant.conf` is rewritten with the new SSID and passphrase, and `channel=` (1, 6 or 11, chosen from the device id) is added to `config.txt`.
- The same values are printed once on the serial console as `ES_CREDENTIALS NEW: ...` and are readable as root in `/tmp/credentials.txt`. **The serial log then contains the password; redact that line before sharing logs.**
- The generated files are staged and written to flash at the **next normal reboot** (`boot update committed` in the serial log). If power is removed before that reboot, the next boot generates new credentials. Reboot once after first boot.
- `password=` is applied to user `m5` at every boot. To change it, edit `password=` (8-64 characters, no `:`) in `credentials.txt`, safe-eject the drive and reboot. `passwd` over SSH only lasts until the next boot.
- There is no forced password change at first login: the password is already random per device, and the image has no built-in fallback password. If `password=` cannot be applied (`ES_CREDENTIALS` on the console), password login for `m5` stays disabled; SSH keys still work.
- `channel=` (1-13) in `config.txt` sets the SoftAP channel without editing `wpa_supplicant.conf`.
- A custom `wpa_supplicant.conf` (one that is not the shipped `m5` / `m5stamp-p4-c6` default) is never overwritten; only `password=` is generated then.
- **Factory reset**: put an empty file named `factory-reset` (or `factory-reset.txt`) on the USB drive, safe-eject and reboot. The drive is restored to the shipped defaults (`ES_FACTORY_RESET` in the serial log), new credentials are generated, and the result is saved at the next reboot like any first boot.
- **SSH keys**: put an OpenSSH `authorized_keys` file on the USB drive, safe-eject and reboot; it is installed as `/home/m5/.ssh/authorized_keys` at every boot (`ES_SSH_KEYS` in the serial log). With keys installed, `ssh_password_auth=no` in `config.txt` makes Dropbear accept keys only. Without any installed key that setting is ignored so a mistake cannot lock you out.

---

## Quick Start: Flash Pre-Built Release Binaries

### 1. Download Release Package

> **v0.2.2** is the first release built by the tag-driven `release` workflow: the
> assets are the CI build that was flashed and checked on hardware, and the tag run
> refuses any asset whose hash is not in `linux/tests/v0.2.2-hardware-validation-2026-10-15.md`.
> It adds the A/B `/boot` slots and metadata (`boot_alt`, `bootmeta*`) that the
> `v0.2.1-smp` binaries lacked (#8), and ships a debug bundle (`System.map`, `vmlinux`)
> and the GPL corresponding source (`*-legal-info.tar.gz`, #31).

Download either the monolithic 16MB raw flash image or the partition zip package from the [Releases](https://github.com/tsuyoshi-otake/m5stamp-p4-c6-linux/releases) page:
- **`m5stamp-p4-c6-linux-smp-v0.2.2-16mb.bin.gz`**: Single 16MB raw flash image (simplest, flash to `0x0`).
- **`m5stamp-p4-c6-linux-smp-v0.2.2.zip`**: Individual partition binaries with automated PowerShell flash script.

### 2. Flash using `esptool.py`

Connect the M5Stamp-P4 via its USB-C port to your computer. Identify your serial port (e.g., `COM10` on Windows or `/dev/ttyACM0` on Linux/macOS).

#### Option A: Monolithic 16MB Raw Image Flash (Recommended)
```bash
gzip -d m5stamp-p4-c6-linux-smp-v0.2.2-16mb.bin.gz
esptool.py --chip esp32p4 --port COM10 --baud 460800 write_flash 0x0 m5stamp-p4-c6-linux-smp-v0.2.2-16mb.bin
```

#### Option B: Release PowerShell Script
```powershell
.\flash-candidate.ps1 -Port COM10 -AllowCandidateWrite
```

Do not use `-PreserveBoot` for the first upgrade from v0.2.1-smp or older, which have
no A/B slots. It is only for reflashing a v0.2.2 installation whose A/B slots and
metadata are already initialized.

#### Option C: Manual Multi-Partition Flash
```bash
esptool.py --chip esp32p4 --port COM10 --baud 460800 \
    --before default_reset --after no_reset write_flash -z \
    0x002000 bootloader.bin \
    0x008000 partition-table.bin \
    0x010000 boot-shim.bin \
    0x090000 Image \
    0x810000 rootfs.squashfs \
    0x0f10000 easystick-stamp-p4.dtb \
    0x0f40000 boot.img
esptool.py --chip esp32p4 --port COM10 --baud 460800 \
    --before default_reset --after hard_reset erase_region 0xfc0000 0x2000
```

#### Flash Partition Map

| Offset | File | Description |
| :--- | :--- | :--- |
| `0x002000` | `bootloader.bin` | ESP-IDF 1st stage bootloader |
| `0x008000` | `partition-table.bin` | ESP32-P4 Flash partition table |
| `0x010000` | `boot-shim.bin` | Secondary boot-shim (PSRAM, SDIO matrix, CPU1 release, jump to Linux) |
| `0x090000` | `Image` | Linux 6.18 SMP RISC-V kernel binary |
| `0x810000` | `rootfs.squashfs` | Read-only SquashFS root filesystem with Buildroot userland |
| `0x0f10000` | `easystick-stamp-p4.dtb` | Compiled Flattened Device Tree for Stamp-P4 |
| `0x0f40000` | `boot.img` | 256KB FAT12 `/boot` slot 0 exposed via USB Mass Storage (Type-A) |
| `0x0f80000` | — | Inactive 256KB `/boot` slot used for power-loss-safe updates |
| `0x0fc0000` | — | Two redundant 4KB A/B metadata sectors at `0xfc0000` and `0xfc1000` |

### 3. Connect & Use

1. After flashing, the Stamp-P4 automatically reboots and starts SoftAP within ~10 seconds.
2. **Optional USB Mass Storage Configuration**: If using the [EasyStick carrier](#optional-hardware-easystick-usb-mass-storage-carrier), disconnect the Stamp-P4 USB-C cable after flashing, then plug the carrier's USB Type-A connection into your PC. Do not power USB-A and USB-C simultaneously. A 256KB FAT drive (volume `EASYSTICK`) will appear with `cmdline.txt`, `config.txt`, and `wpa_supplicant.conf`. Without this carrier or equivalent USB wiring, skip this step and use Wi-Fi/SSH or the USB-C serial console.
   - Edit and save the configuration, then use the operating system's **Eject / Safely Remove** action. The host-issued SCSI eject transfers ownership of the image back to Linux; only then does `easystick-bootsync` validate the FAT snapshot and reload the network.
   - Do not reconnect or remove power until the serial log reports `USB storage reattached`. Invalid or incomplete FAT images are rejected and the previous runtime configuration remains active.
   - Live network status is available as `/run/easystick-status.txt` over SSH or serial. The exported USB drive is strictly dedicated to boot configuration (`cmdline.txt`, `config.txt`, `wpa_supplicant.conf`).
   - Imported settings are applied immediately and staged in PSRAM. Reboot the board normally to commit the validated image to the inactive flash slot. The boot shim verifies the image CRC, switches metadata only after readback succeeds, and retains the previous slot if power is lost during the flash update.
   - Power loss before that reboot discards the staged change. Wait for `boot update committed` in the serial log before removing power if the setting must survive the next boot.
3. Open `credentials.txt` on the USB drive (or read the `ES_CREDENTIALS NEW` line in the serial log) and connect to the Wi-Fi SSID `ssid=` with the passphrase `psk=`.
4. Your device will receive an IP address such as `192.168.4.2`.
5. Open a terminal and SSH into the board:
   ```bash
   ssh m5@192.168.4.1
   # Password: password= from credentials.txt
   ```
6. You can now edit files and run Python programs immediately:
   ```bash
   vi hello.py
   python3 hello.py
   ```

---

## Optional Hardware: EasyStick USB Mass Storage Carrier

The **EasyStick Stamp-P4 Rev0.15** carrier is an optional convenience board for
using the USB mass-storage configuration drive without separately wiring the
Stamp-P4's Full-Speed USB signals. It is not required for Linux boot, Wi-Fi,
SSH, or the Stamp-P4 USB-C serial console; the Stamp-AddOn C6 and its SDIO
connection are still required for Wi-Fi.

- **Easy configuration from a PC**: plug the carrier's USB-A connection into
  your computer to access the `EASYSTICK` drive with the release firmware.
- **Separate USB functions**: the carrier routes GPIO26 (D−) / GPIO27 (D+)
  for mass storage. The Stamp-P4's USB-C flashing/serial connection is not
  this mass-storage port.
- **Configuration storage, not a general-purpose USB disk**: the drive is
  256KB; follow the safe-eject and normal-reboot procedure above to persist
  changes. It does not expose the root filesystem or RAM-backed home directory.
- **Open hardware files**: [schematic PDF, Gerber ZIP, checksums, and assembly
  notes](board/hardware/README.md), licensed under MIT. Rev0.15 has been
  manufactured and used successfully by the project owner.

Use only one USB power input at a time. The carrier is a separate hardware
option, not a required purchase or a component included in the firmware
download. Equivalent hardware must provide the appropriate USB data, ground,
power, and protection connections; GPIO wiring alone is not sufficient.

---

## Wi-Fi Configuration: Switching Access Points & Modes

The system boots by default into **SoftAP mode** (per-device SSID `m5-XXXX` and passphrase, see `credentials.txt`), allowing immediate configuration from any Wi-Fi-enabled phone or computer without needing a local Wi-Fi router.

However, you can dynamically connect the Stamp-P4 to your existing Wi-Fi network (Station mode), or customize the SoftAP parameters, **directly from the Linux terminal without re-flashing or re-building!**

### 0. The simple way: `config.txt` on the USB drive

Add these lines to `config.txt` on the USB drive and use the host's safe-eject action:

```ini
wifi_ssid=YOUR_WIFI_SSID
wifi_psk=YOUR_WIFI_PASSWORD
```

The board then joins that network as a station (leave `wifi_psk` out for an open network). With `wifi_mode=ap` the same two lines define the SoftAP instead (`channel=` picks the channel). When set, these lines take precedence over `wpa_supplicant.conf`. Invalid values (PSK not 8-63 characters, SSID over 32 bytes, `"` or `\` in either) are reported on the serial console as `M3-lab: CONFIG ERROR: ...` and the board keeps using `wpa_supplicant.conf`.

`wifi_pmf=1` adds optional protected management frames (802.11w, `ieee80211w=1` with `WPA-PSK WPA-PSK-SHA256`) to the generated config, for both station and SoftAP. Peers without PMF still connect. In station mode it was tested with the v0.2.2 image (the board joined, got an address and set the clock from NTP); a client negotiating PMF with the SoftAP has not been tested. If the board stops joining, remove the line.

`sdio_mhz=40` (or 1, 2, 5, 10, 20) sets the SDIO clock to the C6 from the next boot; see [SDIO clock](#c6-firmware-security-features--regulatory-notes). Other values are ignored with `M3-lab: ignoring sdio_mhz=...` on the console.

`country=JP` (any two-letter code) in `config.txt` sets the Wi-Fi regulatory domain (`M3-lab: regulatory domain JP` on the console); `country=` inside `wpa_supplicant.conf` works too. Without it the board uses the restrictive world domain. Set it to the country where the board is used.

The board has no RTC. The clock starts at the image build time; after a station-mode DHCP lease it is set once from `pool.ntp.org` (`M3-lab: clock set from NTP` on the console). `ntp_server=` in `config.txt` picks another server and `ntp_server=none` turns this off.

By default the kernel feeds the hardware watchdog, so the board resets only when the kernel itself hangs. `watchdog=1` in `config.txt` hands the watchdog to a userland feeder: the board then also resets about 120 s (the DTS `timeout-sec`) after userland stops being scheduled, or about 3 minutes after the SSH server (inetd) disappears and does not come back (60 s of checks, then the 120 s timeout). If the feeder itself is killed, the kernel resumes feeding and the board does not reset. `wpa_supplicant` and `udhcpd` are restarted automatically if they exit.

### 1. Connecting to an Existing Wi-Fi Network (Station / Client Mode)

From the terminal (either over serial console or via SSH over default SoftAP `192.168.4.1`), run the following commands:

```bash
# 1. Stop active SoftAP and DHCP server
killall udhcpd wpa_supplicant 2>/dev/null || true
ifconfig wlan0 down

# 2. Write your Wi-Fi credentials to a config file (/tmp is writable)
cat << 'EOF' > /tmp/wpa_supplicant.conf
network={
    ssid="YOUR_WIFI_SSID"
    psk="YOUR_WIFI_PASSWORD"
}
EOF

# 3. Switch interface to managed (station) mode and connect
iw dev wlan0 set type managed
ifconfig wlan0 up
wpa_supplicant -B -i wlan0 -c /tmp/wpa_supplicant.conf

# 4. Wait a few seconds for link association and request an IP via DHCP
sleep 4
udhcpc -i wlan0 -n -t 5 -q
ifconfig wlan0
```

Once connected, `ifconfig wlan0` will show your new local IP address (e.g. `192.168.1.150` or `10.255.10.x`). You can now SSH directly from any PC on your local LAN:

```bash
ssh m5@<YOUR_NEW_IP>
# Password: password= from credentials.txt
```

The board also answers mDNS for `<hostname>.local` (`easystick.local` unless `hostname=` in `config.txt` says otherwise), so `ssh m5@easystick.local` works from hosts with mDNS (macOS, most Linux desktops, Windows 10+). Only the name is published; there is no service discovery.

*(Note: To test link state manually, run `iw dev wlan0 link` to view connection status, SSID, signal level, and BSSID).*

### 2. Customizing the SoftAP (Change SSID / Passphrase)

If you wish to configure a custom SoftAP SSID or passphrase:

```bash
# 1. Stop current Wi-Fi services
killall udhcpd wpa_supplicant 2>/dev/null || true
ifconfig wlan0 down

# 2. Write custom SoftAP configuration (mode=2 enables AP)
cat << 'EOF' > /tmp/wpa_custom_ap.conf
update_config=0
ap_scan=1
network={
    ssid="MyCustomAP"
    mode=2
    frequency=2437
    key_mgmt=WPA-PSK
    proto=RSN
    pairwise=CCMP
    group=CCMP
    psk="MySecurePassword123"
}
EOF

# 3. Bring up interface in AP mode & restart DHCP server
iw dev wlan0 set type __ap
ifconfig wlan0 192.168.4.1 netmask 255.255.255.0 up
wpa_supplicant -B -i wlan0 -c /tmp/wpa_custom_ap.conf
udhcpd -S /etc/udhcpd.conf &
```

---

## Tutorial: Using the `vi` Text Editor

The distribution includes a full-featured BusyBox `vi` text editor compiled with syntax highlighting helpers, visual blocks, search, and multi-level undo.

Combined with the writable **RAM-backed OverlayFS** on `/home/m5` and `/root`, you can author, edit, and modify scripts just like on a standard desktop Linux system.

### Starting `vi`

```bash
cd /home/m5
vi script.py
```

### The Two Modes of `vi`

1. **Command Mode** (default): Keypresses are interpreted as navigation or action commands (e.g., delete line, search, save).
2. **Insert Mode**: Keypresses insert actual text into the document.

### Quick Reference Cheat-Sheet

| Key | Mode | Description |
| :--- | :--- | :--- |
| **`i`** | Command → Insert | Start inserting text before the cursor |
| **`a`** | Command → Insert | Start inserting text after the cursor |
| **`o`** | Command → Insert | Open a new line below and start inserting |
| **`Esc`** | Insert → Command | Exit insert mode back to command mode |
| **`:w`** | Command | Save (write) current file to disk |
| **`:wq`** or **`ZZ`** | Command | Save file and quit `vi` |
| **`:q!`** | Command | Force quit without saving changes |
| **`dd`** | Command | Delete (cut) current line |
| **`yy`** | Command | Copy (yank) current line |
| **`p`** | Command | Paste copied/cut line below cursor |
| **`u`** | Command | Undo last action |
| **`/pattern`** | Command | Search forward for `pattern` (press **`n`** for next match) |
| **`:set number`** | Command | Show line numbers (`:set nonumber` to turn off) |

### Step-by-Step Hands-On Example

1. Open a new shell script in your home directory:
   ```bash
   vi /home/m5/sysinfo.sh
   ```
2. Press **`i`** to enter Insert mode.
3. Type the following text:
   ```bash
   #!/bin/sh
   echo "=== System Information ==="
   uname -a
   echo "=== Memory Usage ==="
   free -m
   echo "=== Disk & OverlayFS Status ==="
   df -h
   ```
4. Press **`Esc`** to return to Command mode.
5. Type **`:wq`** and press **Enter** to save and exit.
6. Make it executable and run it:
   ```bash
   chmod +x /home/m5/sysinfo.sh
   /home/m5/sysinfo.sh
   ```

---

## Tutorial: MicroPython (`python3`) Programming

The image comes pre-installed with **MicroPython v1.22.2** compiled specifically for RISC-V RV32 NOMMU architectures using bFLT Load-to-Ram (`-r`), position-independent code (`-fPIC`), and an expanded 32 KB execution stack.

It is accessible under both `micropython` and the standard `python3` command.

### 1. Interactive REPL (Read-Eval-Print Loop)

Launch the interactive REPL anytime by running `python3`:

```bash
$ python3
MicroPython v1.22.2 on 2026-09-05; linux [RV32-NOMMU] version
Use Ctrl-D to exit, Ctrl-E for paste mode
>>> 2 ** 16
65536
>>> import sys
>>> print("Platform:", sys.platform)
Platform: linux
>>> print("Version :", sys.version)
Version : 3.4.0; MicroPython v1.22.2 on 2026-09-05
>>> [x * x for x in range(8)]
[0, 1, 4, 9, 16, 25, 36, 49]
```

*(Press **`Ctrl-D`** to exit the REPL and return to the shell).*

### 2. Running One-Liners

Execute quick commands or inspect the system with the `-c` flag:

```bash
# Print system information
python3 -c "import os; print('Uname:', os.uname())"

# Perform a quick math calculation
python3 -c "print('Sum 1..10000:', sum(range(10001)))"
```

### 3. Writing and Running a Benchmark Script

Create a Python script using `vi`:

```bash
vi /home/m5/prime_bench.py
```

Insert the following code:

```python
import time
import sys

print("=============================================")
print(" M5Stamp ESP32-P4 + C6 MicroPython Benchmark ")
print("=============================================")
print("System:", sys.platform)
print("Python:", sys.version)

start = time.time()
primes = []
limit = 3000

for num in range(2, limit):
    is_prime = True
    for p in primes:
        if p * p > num:
            break
        if num % p == 0:
            is_prime = False
            break
    if is_prime:
        primes.append(num)

elapsed = time.time() - start
print("\nResults:")
print(f"  Calculated {len(primes)} primes up to {limit}")
print(f"  Largest prime found: {primes[-1]}")
print(f"  Elapsed time       : {elapsed:.3f} seconds")
print("=============================================")
```

Save and exit (`:wq`), then execute it with:

```bash
python3 /home/m5/prime_bench.py
```

### 4. Reading and Writing Files

Because `/home/m5` is backed by OverlayFS in RAM, file I/O operations work naturally:

```python
# Write a file
with open("/home/m5/log.txt", "w") as f:
    f.write("Stamp-P4 Linux record: System operational\n")

# Read it back
with open("/home/m5/log.txt", "r") as f:
    print("Logged message:", f.read().strip())
```

| Signal | ESP32-P4 Pin | ESP32-C6 Pin | Function |
| :--- | :--- | :--- | :--- |
| **C6_PU / RESET** | GPIO 42 | CHIP_PU | Reset line for C6 slave (controlled by boot-shim) |
| **SDIO_CLK** | GPIO 43 | GPIO 19 | SDIO Clock |
| **SDIO_CMD** | GPIO 44 | GPIO 18 | SDIO Command |
| **SDIO_DAT0** | GPIO 45 | GPIO 21 | SDIO Data 0 |
| **SDIO_DAT1 / IRQ**| GPIO 46 | GPIO 22 | SDIO Data 1 / Interrupt |
| **SDIO_DAT2** | GPIO 47 | GPIO 23 | SDIO Data 2 |
| **SDIO_DAT3** | GPIO 48 | GPIO 15 | SDIO Data 3 |

---

## Technical Deep Dive: The "SSH Wedge" & Kernel Stabilization

Bringing up native Linux on early RISC-V NOMMU silicon often uncovers subtle interaction issues between hardware errata and kernel subsystems.

During initial development, a critical failure known as the **"SSH Wedge"** manifested: executing any non-interactive SSH command (`ssh m5@host id`) or child process termination caused an immediate communication lockup, followed by a hardware watchdog reset (`rst:0x7`) ~120–160s later.

While initially suspected to be an SDIO bus saturation or ESP-Hosted-NG flow-control overflow, extensive post-mortem debugging via RTC crash capsules and local loopback reproduction uncovered an unhandled `Load access fault` in `rb_erase()` during child process exit (`timerqueue_del() -> rb_erase()`).

This was resolved by integrating three essential ESP32-P4 SoC hardening patches:
1. **Signal `mcause` hardening (`0014`)**: Fixes interrupt masking register corruption on `SIGCHLD` returns.
2. **L2 Unified Cache hardening (`0015`)**: Prevents silent memory corruption by eliminating blind L2 cache invalidation without write-back.
3. **Systimer atomic read hardening (`0016`)**: Eliminates torn reads on 52-bit hardware counters and missed timer alarms.

👉 **Read the complete engineering post-mortem and root-cause analysis in [docs/deep-dive-ssh-wedge-and-soc-hardening.md](docs/deep-dive-ssh-wedge-and-soc-hardening.md).**

---

## Repository Structure

Optional EasyStick Rev0.15 [schematics and PCB Gerbers](board/hardware/README.md)
are available under the MIT License, with assembly and reproduction notes.

```text
.
├── board/                 # Hardware contract, pinouts, and MIT-licensed schematics/Gerbers
├── docs/                  # Architecture, troubleshooting, and post-mortem deep dives
│   └── deep-dive-ssh-wedge-and-soc-hardening.md
├── linux/                 # Linux kernel, Buildroot, boot-shim, and integration
│   ├── boot-shim/         # ESP-IDF 2nd stage bootloader (PSRAM/SDIO/flash setup)
│   ├── buildroot-external/# Buildroot package definitions & rootfs overlay
│   │   └── package/
│   │       ├── esp-hosted-ng/     # SDIO Wi-Fi kernel driver with AP mode support
│   │       └── micropython-nommu/ # MicroPython port configured for NOMMU bFLT
│   ├── dts/               # Device Tree Source (Stamp-P4)
│   ├── kernel-patches/    # Target-specific Linux kernel & SMP hardening patches
│   ├── c68/               # Dual-core SMP kernel config fragments & patch renderers
│   ├── m3-lab/            # Lab profile overlays (OverlayFS, SoftAP, udhcpd, vi)
│   ├── build-m1.sh        # Reproducible end-to-end containerized build script
│   ├── flash-candidate.ps1# Flashing script for esptool
│   └── flash-layout.json  # Flash partition map
├── tests/                 # Real hardware validation captures, test scripts, and records
├── tools/                 # Environment validation, UART capture, and flashing utilities
├── vendor/                # Pinned upstream Git submodules
├── versions.lock.json     # Immutable commit and toolchain hashes
└── board-contract.json    # Pin assignment & electrical contract
```

---

## Building from Source

The build pipeline is fully automated and uses Docker to provide a reproducible Debian build environment:

```bash
git clone --recursive https://github.com/tsuyoshi-otake/m5stamp-p4-c6-linux.git
cd m5stamp-p4-c6-linux

# Start containerized build
./linux/build-cmd53-bb.sh --vendor /path/to/output --profile m3-lab --smp
```

This compiles:
1. ESP-IDF `boot-shim` for dual-core CPU1 release and SDIO initialization
2. Linux 6.18 SMP kernel with RISC-V P4 patches and Stamp-P4 Device Tree
3. Buildroot root filesystem with Busybox (vi, udhcpd), Dropbear SSH, MicroPython, and ESP-Hosted-NG (`esp32_sdio.ko`)
4. Combined image artifacts ready for flashing

---

## SHA-256 Checksums (v0.2.2)

```text
Raw 16MB Monolithic Image:
75bebaf0cb28ae66a9b49858652c55d9901662419046ec592b553c6295ce22a3  m5stamp-p4-c6-linux-smp-v0.2.2-16mb.bin.gz
70d15a9afb78384c20c539f69e31ece1eefbfda49ab69d3ee0d8f9478b191363  m5stamp-p4-c6-linux-smp-v0.2.2-16mb.bin (uncompressed)

Partition Archive:
532b0f1a90d5d2233676c3952cf71a7ddc9f65b5d4b0f06fe0b7f63e5268916d  m5stamp-p4-c6-linux-smp-v0.2.2.zip

Individual Partitions:
52f83f7d023851c29575b3b323692af3131d2b631719a862a9e5db81de0c90d0  bootloader.bin
7937656f29960d53b63010b51836e233d092e067e320cde5778ec43e04218870  partition-table.bin
66b565c1f0318c1716cfee3daf60a31eb52f588e0753e4f9ce564a0473f9df86  boot-shim.bin
7e10c5578c23e8cb5897b038fe12775b44bfdf5d62193cee5c611d12900a1330  Image
7bdc3763b0aa2e5701166a4c10396f555a603b98dc4d6798e1aaf4039d855d75  rootfs.squashfs
bf8cf6362c11f7d4d6d148564c2fd614be5d02d77d898478e4402876f7a81184  easystick-stamp-p4.dtb
70ca3ae44bef09b089eed7a31ab565e98e05ba8d3f2636a0f602986c922f355e  boot.img
```

---

## Third-party licenses

The images contain third-party software under its own licenses. Corresponding source for GPL components is built from the revisions pinned in `versions.lock.json` plus the patches and configs under `linux/`.

| Component | License |
|---|---|
| Linux 6.18.35 + patches, `esp32_sdio.ko` | GPL-2.0 |
| BusyBox | GPL-2.0 |
| uClibc-ng | LGPL-2.1 |
| Dropbear | MIT |
| wpa_supplicant | BSD-3-Clause |
| ESP-IDF (boot-shim) | Apache-2.0 |
| ESP-Hosted NG host driver (`esp32_sdio.ko`) | GPL-2.0-only (shared headers GPL-2.0-only or Apache-2.0) |
| ESP-Hosted NG C6 firmware (`network_adapter.bin`) | Apache-2.0 |

Releases carry `…-legal-info.tar.gz`, Buildroot's `make legal-info` output for the image: the source archives, patches, configs and license texts of every package in the rootfs and the kernel (`manifest.csv` lists them). Sources of build-host tools (`host-sources`) are left out because they are not shipped. Build it locally with `EASYSTICK_LEGAL_INFO=1 bash linux/build-c68.sh …`; it lands in `<vendor>/buildroot/legal-info`. The boot shim and the C6 firmware are built from the ESP-IDF and ESP-Hosted revisions in `versions.lock.json`. The image itself lists the same pointers in `/usr/share/licenses/README`.

The project's own files are licensed under GPL-2.0-only ([`LICENSE`](LICENSE), #31), except where a file carries its own `SPDX-License-Identifier`: the boot shim (`linux/boot-shim/`) is `Apache-2.0 OR GPL-2.0-only`, and the schematics and Gerbers under `board/hardware/` are MIT ([`board/hardware/LICENSE`](board/hardware/LICENSE)).

## Acknowledgments & References

- [why2025-linux](https://github.com/mrbreaker/why2025-linux) by @mrbreaker for initial ESP32-P4 NOMMU bring-up reference.
- [Espressif ESP-Hosted](https://github.com/espressif/esp-hosted) for the SDIO Wi-Fi slave stack.
- The Buildroot and Linux kernel communities.
