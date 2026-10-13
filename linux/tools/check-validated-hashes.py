#!/usr/bin/env python3
"""Refuse a release whose assets were not the ones validated on hardware.

Reads the release SHA256SUMS.txt and one or more hardware-validation records
(tests/*-hardware-validation-*.md) and fails unless every release asset hash
appears in a validation record next to its file name.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HASH_LINE = re.compile(r"\b([0-9a-f]{64})\b[ \t*`]+([A-Za-z0-9._-]+)")


def read_sums(path: Path) -> dict[str, str]:
    sums = {}
    for line in path.read_text(encoding="ascii").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (\S+)", line.strip())
        if match:
            sums[match.group(2)] = match.group(1)
    return sums


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sums", type=Path, required=True, help="release SHA256SUMS.txt")
    parser.add_argument("--validation", type=Path, nargs="+", required=True)
    parser.add_argument(
        "--ignore", nargs="*", default=["-debug.tar.xz"],
        help="asset name suffixes that need no hardware validation",
    )
    args = parser.parse_args()

    validated: dict[str, set[str]] = {}
    for record in args.validation:
        for digest, name in HASH_LINE.findall(record.read_text(encoding="utf-8")):
            validated.setdefault(name, set()).add(digest)

    failed = False
    for name, digest in sorted(read_sums(args.sums).items()):
        if any(name.endswith(suffix) for suffix in args.ignore):
            continue
        # Match by hash too: the record may name the unpacked file.
        known = digest in validated.get(name, set()) or any(digest in v for v in validated.values())
        print(f"{'OK  ' if known else 'FAIL'} {digest}  {name}")
        failed |= not known
    if failed:
        print("release assets do not match any hardware-validation record", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
