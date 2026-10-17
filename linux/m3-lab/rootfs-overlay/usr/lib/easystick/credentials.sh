# Sourced by S05easystick-tmpfs at boot and by easystick-bootsync when the USB
# drive changes.  The caller defines es_log.

# Apply password= from credentials.txt to user m5.  /etc is read-only squashfs,
# so a patched copy of /etc/shadow on /run is bind-mounted over it.  Once it is
# mounted, a new password overwrites that copy in place.
apply_password() {
	[ -f "$1" ] || return 0
	cr=$(printf '\r')
	pw=$(sed -e "s/$cr\$//" "$1" | sed -n 's/^password=//p' | head -n1)
	case "$pw" in
		''|*:*) es_log "ES_CREDENTIALS: no usable password= in credentials.txt"; return 0 ;;
	esac
	if [ "${#pw}" -lt 8 ] || [ "${#pw}" -gt 64 ]; then
		es_log "ES_CREDENTIALS: password= must be 8-64 characters; m5 password login stays disabled"
		return 0
	fi
	hash=$(printf '%s\n' "$pw" | cryptpw -m sha512 2>/dev/null) || hash=""
	case "$hash" in
		'$6$'*) ;;
		*) es_log "ES_CREDENTIALS FAIL: cryptpw unavailable; m5 password login stays disabled"; return 0 ;;
	esac
	if ! sed "s|^m5:[^:]*:|m5:${hash}:|" /etc/shadow > /run/shadow.new ||
		! chmod 600 /run/shadow.new; then
		rm -f /run/shadow.new
		es_log "ES_CREDENTIALS FAIL: could not apply the password; m5 password login stays disabled"
		return 0
	fi
	if grep -q ' /etc/shadow ' /proc/mounts; then
		cat /run/shadow.new > /run/shadow && rm -f /run/shadow.new &&
			es_log "ES_CREDENTIALS: m5 password applied from credentials.txt" && return 0
	elif mv -f /run/shadow.new /run/shadow && mount --bind /run/shadow /etc/shadow; then
		es_log "ES_CREDENTIALS: m5 password applied from credentials.txt"
		return 0
	fi
	rm -f /run/shadow.new
	es_log "ES_CREDENTIALS FAIL: could not apply the password; m5 password login stays disabled"
}

# authorized_keys on the USB drive -> /home/m5/.ssh (#25).  /home is a tmpfs
# overlay, so this runs every boot and the drive stays the source of truth.
install_keys() {
	[ -f "$1" ] || return 0
	d=/home/m5/.ssh
	cr=$(printf '\r')
	mkdir -p "$d"
	sed -e "s/$cr\$//" "$1" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' > "$d/authorized_keys" || true
	chown -R 1000:1000 "$d" 2>/dev/null || true
	chmod 700 "$d"
	chmod 600 "$d/authorized_keys"
	n=$(grep -c '' "$d/authorized_keys" || true)
	es_log "ES_SSH_KEYS: $n key(s) installed for m5 from authorized_keys"
}
