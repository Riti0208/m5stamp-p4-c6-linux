#!/usr/bin/env bash
# Rebuild the Tab5 kernel Image locally from the tab5-build workflow's
# "tab5-kernel-kit" artifact, for quick display/keyboard iterations.
#
#   tools/tab5-kernel-build.sh <kit-dir> <work-dir>
#
# The kit holds the patched kernel tree exactly as Buildroot built it and
# its .config.  The first run extracts it into <work-dir>/linux-custom and
# commits it to a local Git repository, so `git diff` there shows what you
# changed (carry that back into linux/kernel-patches/).  Objects stay in
# <work-dir>/obj, so later runs are incremental.  The build runs in Docker
# with Debian's riscv64-linux-gnu GCC, not the Buildroot toolchain, so
# esp32_sdio.ko in the CI rootfs may refuse to load with this Image; flash
# a full CI image again once the change is settled.
#
# Flash only the kernel partition:
#   esptool.py --chip esp32p4 --port PORT write_flash 0x90000 <work-dir>/obj/arch/riscv/boot/Image
set -euo pipefail

[[ $# -eq 2 ]] || { sed -n '2,17p' "$0" >&2; exit 2; }
kit=$(cd -- "$1" && pwd)
work=$(mkdir -p -- "$2" && cd -- "$2" && pwd)
[[ -f "$kit/linux-tree.tar.zst" && -f "$kit/kernel.config" ]] || {
	echo "not a tab5-kernel-kit directory: $kit" >&2
	exit 1
}

if [[ ! -d "$work/linux-custom" ]]; then
	tar -C "$work" --zstd -xf "$kit/linux-tree.tar.zst"
	git -C "$work/linux-custom" init -q
	git -C "$work/linux-custom" add -A
	git -C "$work/linux-custom" -c user.name=kit -c user.email=kit@localhost \
		commit -qm "tab5-kernel-kit baseline"
fi
mkdir -p "$work/obj"
cp -- "$kit/kernel.config" "$work/obj/.config"

image=tab5-kbuild:bookworm
if ! docker image inspect "$image" >/dev/null 2>&1; then
	docker build -t "$image" - <<'EOF'
FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
	gcc-riscv64-linux-gnu gcc make bc bison flex libssl-dev libelf-dev \
	python3 cpio kmod && rm -rf /var/lib/apt/lists/*
EOF
fi

docker run --rm -v "$work:/w" -w /w/linux-custom "$image" bash -c '
	set -e
	export ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu-
	make -s O=/w/obj olddefconfig
	make O=/w/obj -j"$(nproc)" Image 2>&1 | grep -E "error|warning:|Kernel: " || true
	test -s /w/obj/arch/riscv/boot/Image
'
img="$work/obj/arch/riscv/boot/Image"
size=$(wc -c <"$img")
# kernel partition: 0x90000..0x810000 (linux/m2/flash-layout.json)
(( size <= 0x780000 )) || { echo "Image is $size bytes, larger than the kernel partition" >&2; exit 1; }
echo "Image: $img ($size bytes)"
