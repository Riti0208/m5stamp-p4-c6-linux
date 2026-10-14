# M3-lab hardware validation (2026-10-14)

Board: M5Stamp ESP32-P4 + C6 (SDIO), P4 USB Serial/JTAG on COM10.  Only the
P4 flash was written; the C6 was not touched.

## Recovery point

Full 16 MB read-back before any write, from the image shipped on the board
(v0.2.1 era):

```
backup-2026-10-14.bin  sha256 31b136edcac1c4f9773d455571e01397da8a296c65165a4249c324b54f5afa5b
restore: python -m esptool --chip esp32p4 --port COM10 -b 921600 write_flash 0x0 backup-2026-10-14.bin
```

The restore was exercised once during the bisect below and booted with wlan0.

## Final candidate ("D")

Built by `build-c68.sh --profile m3-lab` from a staged copy of the tree, so
`/etc/easystick-release` reports `git=51decbdca0c1 dirty=1`
(`version=v0.2.1-smp-25-g51decbd`, kernel 6.18.35).  The staged tree matches
commit 20bebd5 for every file that reaches the image.

```
298a618c17d2b63320520d53a5205502ec0c86c37ef6ae0ebfa6b98ebeae3b32  Image
3540fdd5a350953148063244dd0583d186e2a256928130271530c9ae05a5d55c  boot-shim.bin
47a395e21f0dd6eb3990387fcbf0baa0d06a80c415be94a96fbcdf6b281c50ed  boot.img
9581932b9bd542b84e06d43ba7eef997315c3a1cc43abb5c00c9516e6f8ded10  bootloader.bin
cda3cbe1f944e5c6f5dd25dcca2017158cb3248542f8068c8a9bdfbfd9944989  easystick-stamp-p4.dtb
7937656f29960d53b63010b51836e233d092e067e320cde5778ec43e04218870  partition-table.bin
b462a4be7a5c37ce98ae554d1ea97a0730bb0372884f875a5fea25acb276fe79  rootfs.squashfs
```

Flashed with `flash-candidate.ps1 -AllowCandidateWrite` (write + verify passed).

## check-boot-log.py results

| capture | image | result |
|---|---|---|
| boot-orig | image shipped on the board | 9/11: `ES_HOSTKEY GEN_FAIL`, `start-stop-daemon: applet not found` (known, fixed in tree) |
| boot-A | tree without patch 0034, PIO default | 9/11: wlan0 never appears |
| boot-B | DMA default | 11/11 |
| reboot-B | B, `reboot` from the console (`--after-reboot`) | 11/11, no crash capsule |
| boot-C | B + `0<>` fix | 11/11 |
| boot-D | C + modprobe options fix | 11/11 |

## Regressions found and fixed on hardware

1. **wlan0 missing (PIO SDIO default).**  The C6 boot event arrived garbled
   (`Drop invalid pkt len=3 offset=0`), so no wlan0.  Not 0034 and not BT
   (boot-A was built without 0034 and still failed).  The shipped v0.2.1
   used the IDMAC path.  Fixed in 6c341f5: m3-lab defaults to
   `EASYSTICK_SDIO_FORCE_PIO=0`, `EASYSTICK_IDMAC_NONCOHERENT_RING=1`.
2. **/boot mount point missing.**  The squashfs root is read-only, so S05
   could not create it.  Fixed in 78f1c86 (`ES_BOOT_FAT OK`).
3. **Console keystrokes stolen.**  hush applies a bare `<>` to fd 1, so
   `read -t N _ <> fifo` left fd 0 on /dev/console (seen in `/proc/<pid>/fd`).
   Fixed in ca06cf7 (`0<>`, plus a static-check guard).  The console
   takes commands normally afterwards.
4. **USB LUN had no backing file.**  busybox-minimal drops modprobe
   command-line parameters, giving `no file given for LUN0` and bootsync
   `ownership=error`.  The shipped image only worked because of a stale
   `/etc/modprobe.d/g_mass_storage.conf`.  Fixed in 20bebd5.  On D:
   `parameters/file=/tmp/boot.img`, `[bootsync] ownership=host-owned`.

## Smoke-test results (smoke-test.md)

- Step 1–2: boot and reboot pass (table above).
- Step 3: `netstat` shows :22 LISTEN, udp 67 and 5353; `easystick-info` runs;
  MemAvailable 6.3–6.9 MB.
- Step 5 (#17): **not run.**  `CONFIG_SHMEM` depends on MMU, so `tmpfs` is
  ramfs: `size=4M` is ignored and `df /tmp` reports 0.  An 8 MB fill would
  OOM the board.  The dead config lines and the step were corrected in
  9b7a6cf.  #17 item 1 remains open (a brd+ext2 /tmp is one option).
- Steps 4, 6 (24 h soak), 7, 8 (pstore): not run in this session.

## Board state at the end of the session

Running candidate D, SoftAP SSID `m5-6BF3` at 192.168.4.1.  The backup
above restores the original image.
