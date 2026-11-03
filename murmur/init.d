#!/bin/sh /etc/rc.common

USE_PROCD=1
# pbr (START=97) fetches the rule files and rewrites the nft rules. The rule files live
# in tmpfs, so after a reboot they are empty until pbr refetches them. A proxy started
# with empty rule-providers matches nothing and sends those domains to MATCH,DIRECT,
# so the proxy starts after pbr has filled them. murmur watches the rule files and
# reloads them on their own, so a later pbr run does not need a restart.
START=98

script=$(readlink "$initscript")
NAME="$(basename "${script:-$initscript}")"

# The binary is 25 MB and the overlay has ~10 MB free, so it cannot live in flash
# uncompressed. The compressed copy (xz -6, ~7.6 MB) lives on flash and is unpacked
# into tmpfs (242 MB) on every boot.
BIN_XZ="/etc/proxy/murmur.bin.xz"
BIN="/tmp/murmur.bin"
WORKDIR="/tmp/murmur.d"
CONF="/etc/murmur/config.yaml"
SHA256="c9d2e65d464da8ccf2c7dd540274d2de9e1e3a84151aece5793c90d6c3cfac92"

# Fallback source for the binary, used when the flash copy is missing. The cache host
# is on the LAN, so this only works when it is reachable.
CACHE_IP="192.168.1.2"
CACHE_URL="https://cache.labile.cc/serve/5sfjlphiywgmn76k76q1wzv87xdzaqdf/"

_log() {
	logger -t murmur "$*"
	echo "$*" >&2
}

# Unpacks the binary into tmpfs. The flash copy is the normal path; the network is the
# fallback so a wiped overlay does not leave the router without a proxy.
_prepare_binary() {
	[ -x "$BIN" ] && return 0

	if [ -f "$BIN_XZ" ]; then
		_log "Unpacking murmur from $BIN_XZ"
		if xz -dc "$BIN_XZ" > "$BIN.tmp" 2> /dev/null; then
			echo "$SHA256  $BIN.tmp" | sha256sum -c - > /dev/null 2>&1 || {
				_log "ERROR: unpacked binary failed the checksum, discarding it"
				rm -f "$BIN.tmp"
				return 1
			}
			chmod +x "$BIN.tmp"
			mv "$BIN.tmp" "$BIN"
			return 0
		fi
		rm -f "$BIN.tmp"
		_log "WARNING: could not unpack $BIN_XZ"
	fi

	_log "Falling back to the network copy of the binary"
	local tmp="$BIN.fetch"
	curl -s --resolve cache.labile.cc:443:$CACHE_IP --max-time 300 "$CACHE_URL" -o "$tmp" || {
		_log "ERROR: download failed"
		rm -f "$tmp"
		return 1
	}
	echo "$SHA256  $tmp" | sha256sum -c - > /dev/null 2>&1 || {
		_log "ERROR: checksum mismatch, discarding the download"
		rm -f "$tmp"
		return 1
	}
	chmod +x "$tmp"
	mv "$tmp" "$BIN"
	return 0
}

# The DNS listener opens before the rule-providers finish loading, so the first
# queries are answered by MATCH,real-ip. dnsmasq then pins that real address for the
# whole upstream TTL, and for those minutes the domain never reaches the proxy at
# all. Drop the cache once the proxy is really serving, and once more later.
_flush_dns_cache() {
	local conffile="$1"
	local dnsport i=0

	dnsport=$(sed -n 's/^[[:space:]]*listen:[[:space:]]*[0-9.]*:\([0-9][0-9]*\).*/\1/p' "$conffile" | head -1)
	if [ -n "$dnsport" ]; then
		while [ "$i" -lt 60 ]; do
			netstat -lnu 2> /dev/null | grep -qE ":${dnsport}[[:space:]]" && break
			sleep 1
			i=$((i + 1))
		done
	fi
	sleep 3
	killall -HUP dnsmasq 2> /dev/null
	sleep 12
	killall -HUP dnsmasq 2> /dev/null
}

start_service() {
	config_load "$NAME"

	local enabled user conffile workdir ifaces
	config_get_bool enabled "main" "enabled" "0"
	[ "$enabled" -eq "1" ] || return 0

	config_get user "main" "user" "root"
	config_get conffile "main" "conffile" "$CONF"
	config_get workdir "main" "workdir" "$WORKDIR"
	config_get ifaces "main" "ifaces"

	_prepare_binary || return 1

	mkdir -p "$workdir" "$workdir/rules" "$workdir/providers"
	local group
	group="$(id -ng "$user")"
	chown "$user:$group" "$workdir" 2> /dev/null

	procd_open_instance "$NAME.main"
	procd_set_param command "$BIN" -d "$workdir" -f "$conffile"
	procd_set_param user "$user"
	procd_set_param file "$conffile"
	[ -z "$ifaces" ] || procd_set_param netdev $ifaces
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param respawn
	procd_close_instance

	_flush_dns_cache "$conffile" &
}

service_triggers() {
	local ifaces
	config_load "$NAME"
	config_get ifaces "main" "ifaces"
	procd_open_trigger
	for iface in $ifaces; do
		procd_add_interface_trigger "interface.*.up" $iface /etc/init.d/$NAME restart
	done
	procd_close_trigger
	procd_add_reload_trigger "$NAME"
}
