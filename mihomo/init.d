#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99

script=$(readlink "$initscript")
NAME="$(basename ${script:-$initscript})"
PROG="/usr/bin/mihomo"
SEED_DIR="/etc/mihomo/rules"

# The workdir is tmpfs, so a reboot wipes every rule-provider file. mihomo tolerates a missing
# file but then matches nothing, and vpn/warp/telegram domains fall through to MATCH,DIRECT and
# egress the raw WAN until pbr finishes refetching. Restore pbr's persisted copy first.
seed_rules() {
	local workdir="$1" user="$2" group="$3"
	local file target

	[ -d "$SEED_DIR" ] || return 0
	mkdir -p "$workdir/rules"
	for file in "$SEED_DIR"/*.txt; do
		[ -s "$file" ] || continue
		target="$workdir/rules/${file##*/}"
		[ -s "$target" ] && continue
		cp "$file" "$target"
	done
	chown -R "$user:$group" "$workdir/rules"
}

# mihomo opens its DNS listener before the rule-providers finish loading, so the first queries
# after a start are answered by MATCH,real-ip. Measured: the very first answer for a `vpn`
# domain is the real address, the next one is already the fake IP. dnsmasq then pins that real
# address for the whole upstream TTL (300s for chatgpt.com), and for those minutes the domain
# never reaches mihomo at all - no rule set, no killswitch, straight out the WAN. Drop the
# cache once mihomo is really serving, and once more later in case the boot was slow.
flush_dns_cache() {
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
	config_get conffile "main" "conffile"
	config_get ifaces "main" "ifaces"
	config_get workdir "main" "workdir" "/etc/mihomo"

	mkdir -p "$workdir"
	local group="$(id -ng "$user")"
	chown "$user:$group" "$workdir"
	seed_rules "$workdir" "$user" "$group"

	procd_open_instance "$NAME.main"
	procd_set_param command "$PROG" -d "$workdir" -f "$conffile"
	procd_set_param user "$user"
	procd_set_param file "$conffile"
	[ -z "$ifaces" ] || procd_set_param netdev $ifaces
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param respawn
	procd_close_instance

	flush_dns_cache "$conffile" &
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
