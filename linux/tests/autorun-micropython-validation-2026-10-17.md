# Autorun and MicroPython hardware validation (2026-10-17)

Issue #34.  Board: M5Stamp ESP32-P4 + C6 (SDIO), P4 USB Serial/JTAG on
COM10.  Only the P4 flash was written (`flash-candidate.ps1 -PreserveBoot`,
so the USB drive kept its contents); the C6 was not touched.

## Candidate

Built in Docker from commit 4e03b79 (`build-c68.sh --profile m3-lab`,
EXIT=0).  `/usr/bin/micropython` is the new `nommu` variant (431,308 bytes),
`/usr/bin/chpst` points at `busybox-tools`.

```
ac11cac958c4468e96ce821051fe7da545cafd53289d554b2d88c3d9279e4041  Image
fe27b66d7b2be07147928f6b1804969f0832c83f289777727a6d26a95fa1caaf  rootfs.squashfs
bd8b9ea5abe09cfb04f814140dd1473e17cc1db5cb456f0f0ffafb34796ebe57  boot.img
9892921c9d1068140f0b84351b52c535a84e9ad83d062ae7302d38e9f0182a63  boot-shim.bin
a12b18e1347ade36c499c79338ff7125bd4140bf56c64ecfedce8f93b4d3a852  easystick-stamp-p4.dtb
```

Every boot passed `linux/tests/check-boot-log.py` (11 checks) and printed
`ES_AUTORUN STAGED`.  Nothing was bind-mounted over the image: the tests ran
the files that ship in the rootfs.

## Test program

The drive was changed the way a USB host would change it: a root script
loop-mounted a copy of `/tmp/boot.img`, edited it and wrote it back.

`main.py` on the drive:

```python
import json, socket, time
import helper

print("main.py v1 start:", helper.NAME)

ai = [a for a in socket.getaddrinfo("example.com", 80, 0, socket.SOCK_STREAM)
      if a[0] == socket.AF_INET][0]
s = socket.socket(ai[0], ai[1], ai[2])
s.connect(ai[-1])
s.send(b"HEAD / HTTP/1.0\r\nHost: example.com\r\n\r\n")
print("http", s.recv(15))
s.close()

n = 0
while True:
    print(json.dumps({"tick": n, "uptime": helper.uptime()}))
    n += 1
    time.sleep(5)
```

`lib/helper.py` defines `NAME` and `uptime()` (reads `/proc/uptime`).
`config.txt` had no `autorun=` line.

## Results

| Check | Result |
|---|---|
| Drive edit picked up while running | `main.py` started as `m5` (`ps`: `m5 ... SN python3 main.py`) |
| `lib/` import, `json`, `socket` + DNS, `time.sleep` | log: `main.py v1 start: helper from lib/`, `http b'HTTP/1.1 200 OK'`, a JSON line every 5 s |
| Edit `main.py` (v1 → v2) | restarted by itself: `--- autorun: start main.py` / `main.py v2 start` |
| `easystick-autorun restart` / `status` as `m5` | `stopped pid 466`, `started main.py pid 489`, `running: pid 489` |
| `autorun=off` in `config.txt` | `--- autorun: stopped`, status `mode=off` |
| Wi-Fi during the autorun edits | `wlan0` `carrier_changes` stayed 0; no network reload |
| Power-on with `main.py` on the drive | `[bootsync] autorun: started main.py` about 20 s after reset; HTTP 200 and ticks in the log |
| Remove `main.py` and `lib/` | `not running`; `config.txt` md5 back to its original value |

One reset was sent within a few seconds of a drive edit, before bootsync had
written it to flash, and the board came back with the previous drive (and
`mode=off`).  That is the expected behaviour: the drive is saved only after
the `[bootsync] Saved to flash` line, the same as waiting for a USB stick
to finish writing.  After that line, the reset above autostarted the program.
