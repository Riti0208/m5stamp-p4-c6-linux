# Security policy

Please report vulnerabilities privately through GitHub's
"Report a vulnerability" (private security advisory) feature on this
repository instead of opening a public issue.

Known limitations of the current images (see the issue tracker for details):

- The Wi-Fi PSK and the `m5` SSH password are shared by every unit until
  per-device credentials are implemented (#11, #24). Change them before
  exposing a device.
- Secure Boot and flash encryption are disabled. Anyone with physical access
  can read the flash (including the boot FAT with Wi-Fi credentials) and write
  arbitrary firmware.
- The USB-C serial console (`ttyGS1`) gives an unauthenticated root shell.
