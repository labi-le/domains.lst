#!/bin/sh /etc/rc.common

USE_PROCD=1
# pbr (START=97) fetches the rule files and rewrites the nft rules. The rule files live
# in tmpfs, so after a reboot they are empty until pbr refetches them. A proxy started
# with empty rule-providers matches nothing and sends those domains to MATCH,DIRECT,
# so the proxy starts after pbr has filled them. murmur watches the rule files and
# reloads them on their own, so a later pbr run does not need a restart.
START=98
STOP=10

script=$(readlink "$initscript")
NAME="$(basename "${script:-$initscript}")"

PROG="/usr/bin/murmur"
WORKDIR="/tmp/murmur.d"
CONF="/etc/murmur/config.yaml"

_log() {
	logger -t murmur "$*"
	echo "$*" >&2
}

start_service() {
	config_load "$NAME"

	local enabled user conffile workdir ifaces watch_config
	config_get_bool enabled "main" "enabled" "0"
	[ "$enabled" -eq "1" ] || return 0

	config_get user "main" "user" "root"
	config_get conffile "main" "conffile" "$CONF"
	config_get workdir "main" "workdir" "$WORKDIR"
	config_get ifaces "main" "ifaces"
	config_get_bool watch_config "main" "watch_config" "1"

	if [ ! -x "$PROG" ]; then
		_log "ERROR: $PROG is missing or not executable"
		return 1
	fi

	mkdir -p "$workdir" "$workdir/rules" "$workdir/providers"
	local group
	group="$(id -ng "$user" 2>/dev/null || echo root)"
	chown "$user:$group" "$workdir" 2> /dev/null || true

	"$PROG" -t -d "$workdir" -f "$conffile" || {
		_log "ERROR: configuration test failed for $conffile"
		return 1
	}

	procd_open_instance "$NAME.main"
	if [ "$watch_config" -eq "1" ]; then
		procd_set_param command "$PROG" --watch-config -d "$workdir" -f "$conffile"
	else
		procd_set_param command "$PROG" -d "$workdir" -f "$conffile"
	fi
	procd_set_param user "$user"
	[ -z "$ifaces" ] || procd_set_param netdev $ifaces
	procd_set_param stdout 1
	procd_set_param stderr 1
	# The resolver, the tproxy relay and every UDP flow share one descriptor budget.
	# The default 1024 soft limit is what murmur hit, so pin it at the hard cap.
	procd_set_param limits nofile="4096 4096"
	procd_set_param respawn 3600 5 5
	procd_set_param term_timeout 30
	procd_close_instance

	_flush_dns_cache "$conffile" &
}

reload_service() {
	procd_send_signal "$NAME" "$NAME.main" HUP
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
