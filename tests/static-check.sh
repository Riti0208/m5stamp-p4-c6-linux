#!/bin/sh
# Static checks for the rootfs scripts (#28).  Run from the repository root.
#   1. every script parses with sh -n
#   2. no script uses a command that the BusyBox build does not provide
#   3. shellcheck (if installed) reports no errors
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
scripts=$(find "$root/linux/m3-lab/rootfs-overlay" "$root/linux/m3-lab/post-build.sh" \
	-type f \( -path '*/init.d/*' -o -path '*/usr/sbin/*' -o -name post-build.sh \) 2>/dev/null)

# Commands known to be missing from the BusyBox build (see issue #7).
missing="pidof start-stop-daemon hwclock awk free top ip ifup ifdown wget telnet"

fail=0
for f in $scripts; do
	if ! sh -n "$f"; then
		echo "FAIL syntax: $f"
		fail=1
	fi
	# post-build.sh runs on the build host and only lists applet names.
	[ "${f##*/}" = post-build.sh ] && continue
	for cmd in $missing; do
		# Match the command in command position, ignoring comments.
		if grep -v '^[[:space:]]*#' "$f" | grep -Eq "(^|[^A-Za-z0-9_./-])$cmd([[:space:];|&)]|$)"; then
			echo "FAIL missing applet '$cmd' used in $f"
			fail=1
		fi
	done
done

if command -v shellcheck >/dev/null 2>&1; then
	# shellcheck for BusyBox ash: plain sh dialect, errors only.
	for f in $scripts; do
		shellcheck -s sh -S error "$f" || fail=1
	done
else
	echo "note: shellcheck not installed; skipped"
fi

[ "$fail" -eq 0 ] && echo "static checks passed"
exit "$fail"
