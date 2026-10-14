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
- Steps 4, 6 (24 h soak), 7: not run.  Step 8 (pstore): see below.

## Issue re-checks on hardware (candidate D unless noted)

- **#15**: load average 0.00, no task in D state.  Over 60 s idle the
  busy delta in `/proc/stat` was 1 tick of 6000 (about 0.02 %; v0.2.1 7.2 %).
- **#19**: `reboot` still resets through the MWDT (`rst:0x7`) but writes no
  CRASH_CAPSULE (`check-boot-log.py --after-reboot` PASS on B and G).  The
  0059 injector is not in the lab image (`/sys/module/esp32p4_wdt` absent).
- **#5**: DTB `maxcpus=1` patched to 2 on D (one byte at 0xf10474).  Output
  stops after `ES_DWC2_STATUS` as reported, then the board stayed silent
  for more than 11 minutes with **no watchdog reset** and the ACM console
  did not answer.  Recovered by re-flashing the original DTB.  Not fixed.
  Repeated on H with `maxcpus=2 loglevel=8` (same DTB length):
  `smp: Brought up 1 node, 2 CPUs`, userland runs up to `ES_SEEDRNG OK`,
  then the console prints `Guru Meditation Error: Core 1 pan` (the ESP-IDF
  panic handler of the boot-shim, not Linux) and the MWDT resets the chip
  mid-line.  The pstore console record of the hung boot ends without any
  Linux oops.  (The ROM line `Core1 Saved PC:0x4ff0160a`, the GO-poll loop
  in `c68_secondary_entry.S`, also appears after a normal UP boot, so it is
  not evidence about the fault.)  The earlier run hung with no reset at all.
  Things ruled out:
  - The `ST_CONF`/`ST_INT_ENA` lock of 0045, which made the 2026-08-19 SMP
    profile pass, is already folded into the current 0042 (`st_lock`).
    0044/0045 no longer apply on top of it.
  - The Type-A USB gadget.  The host enumerates it right before the stop
    (`new device is full-speed`), but candidate J (H with the gadget
    skipped when the command line has `es.nousb`; a staged test change
    that was not committed) still fails with `maxcpus=2 es.nousb=1`: the
    first boot gets past S40 (`ES_SDIO_LOAD_OK`) and then prints the same
    `Guru Meditation Error: Core 1` before an MWDT reset.  The second boot
    reaches `udhcpd started` and then reports
    `rcu_sched kthread starved for 5250 jiffies! ... ->state=0x0 ->cpu=0`:
    the RCU kthread is runnable on CPU0 but never runs.
  The fault follows interrupt/DMA load (USB, then SDIO/Wi-Fi), not a fixed
  init step.  The SMP profile that passed in August had neither USB gadget
  nor Wi-Fi.  A lost cross-CPU wakeup (IPI) is the leading suspect; it is
  not proven.  Root cause not found.
- **#26 pstore** (candidate G = D + `EASYSTICK_PSTORE=1`
  `EASYSTICK_SDIO_MAX_KHZ=5000`; candidate E, the same without 0065,
  panicked at boot with `kernel BUG at mm/nommu.c:311`):
  - `echo c > /proc/sysrq-trigger`: reset via MWDT, then
    `ES_PSTORE OK: 1 record(s)`; `console-ramoops-0` holds the panic and
    call trace.
  - `panic=0` + sysrq: the kernel hangs, the MWDT resets the board within the
    7-minute capture window, and the record survives.  PSRAM keeps ramoops across a
    watchdog reset.
  - G had no `dmesg-ramoops-*` record and the console record stopped at the
    call trace: PSRAM is behind a write-back L1D/L2 that the reset drops.
    Candidate H (G + zone writeback in 0065) after clearing
    `/sys/fs/pstore`: sysrq panic gives `dmesg-ramoops-0` (11672 B) and a
    console record ending in `Rebooting in 5 seconds..`; the panic=0 hang
    reset by the MWDT gives a fresh `dmesg-ramoops-0` (11832 B) containing
    `sysrq triggered crash`.
- **#21-1**: with the cap at 5 MHz, `ES_SDIO_CLOCK_HW ... actual_clock_hz=5000000`;
  cold boot 11/11 and reboot 12/12 PASS.  Throughput (`scp`) and the soak
  were not run (no Wi-Fi client attached), so the DTS default stays 400 kHz.
- Build: an incremental build kept the previous kernel when 0065 was added
  (b89fcbb now dircleans linux when the staged series changes).

Flashing E/G rewrote the boot partition from the template, so the board
generated new credentials (SSID `m5-F314`, then `m5-4D54` after H and
`m5-73D7` after J; see credentials.txt on the USB drive).

## Board state at the end of the session

Running candidate J (H plus the inert `es.nousb` test gate) with the
normal `maxcpus=1` DTB, 11/11 PASS; SoftAP SSID `m5-73D7` at 192.168.4.1.
The backup
above restores the original image.
