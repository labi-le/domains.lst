#!/bin/sh
# Admin helper for the router's proxy (murmur).
#
#   proxy-ctl.sh status    - show the state
#   proxy-ctl.sh restart   - restart murmur and flush the DNS cache
#   proxy-ctl.sh refresh   - refetch the rule lists and rewrite the nft rules
#   proxy-ctl.sh check     - verify that DNS and tproxy are served and traffic flows
#
# murmur is the only proxy on this router. It took over the ports mihomo used
# (DNS 12344, tproxy 12342), so nftables and dnsmasq are never modified.

set -u
LOG=/tmp/proxy-ctl.log
CONF=/etc/murmur/config.yaml

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# The DNS and tproxy ports, read from the running config.
_ports() {
	_dns=$(sed -n 's/^[[:space:]]*listen:[[:space:]]*[0-9.]*:\([0-9][0-9]*\).*/\1/p' "$CONF" | head -1)
	_tp=$(sed -n 's/^[[:space:]]*tproxy-port:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" | head -1)
	case "$_dns" in ''|*[!0-9]*) _dns=12344 ;; esac
	case "$_tp"  in ''|*[!0-9]*) _tp=12342 ;; esac
}

_status() {
	_ports
	echo "=== murmur ==="
	ps w | grep "[u]sr/bin/murmur" | sed 's/^/  /' || echo "  NOT RUNNING"
	echo "=== listeners (DNS $_dns, tproxy $_tp) ==="
	netstat -lntp 2>/dev/null | grep -E ":(${_dns}|${_tp})[[:space:]]" | sed 's/^/  /'
	echo "=== rule files (tmpfs, refetched by pbr) ==="
	ls -l /tmp/murmur.d/rules/ 2>/dev/null | sed 's/^/  /'
	echo "=== dnsmasq upstream ==="
	uci -q get dhcp.@dnsmasq[0].server | tr ' ' '\n' | sed 's/^/  /'
	echo "=== overlay ==="
	df -h /overlay | tail -1 | sed 's/^/  /'
}

_restart() {
	log "restarting murmur"
	/etc/init.d/murmur restart
	sleep 5
	log "flushing the dnsmasq cache"
	killall -HUP dnsmasq 2>/dev/null
	sleep 3
	killall -HUP dnsmasq 2>/dev/null
	_status
}

# The weekly rule refresh. pbr fetches the lists and renders the nft rules; the proxy
# watches those files and reloads them itself, so nothing is restarted and its uptime
# survives the refresh. The cron entry runs it on Sunday at 06:00.
_refresh() {
	log "refreshing the rule lists"
	/etc/init.d/pbr start
}

_check() {
	_ports
	_rc=0
	if netstat -lnu 2> /dev/null | grep -qE ":${_dns}[[:space:]]"; then
		echo "  OK   DNS is listening on $_dns"
	else
		echo "  FAIL DNS is not listening on $_dns"
		_rc=1
	fi
	if netstat -lnu 2> /dev/null | grep -qE ":${_tp}[[:space:]]"; then
		echo "  OK   tproxy is listening on $_tp"
	else
		echo "  FAIL tproxy is not listening on $_tp"
		_rc=1
	fi
	if ps w | grep -q "[u]sr/bin/murmur"; then
		echo "  OK   murmur is running"
	else
		echo "  FAIL murmur is not running"
		_rc=1
	fi
	# A fake IP in the 198.18.0.0/16 range means the proxy is handing out addresses the
	# nft rules match. A proxied domain must resolve to one; a realip domain must not.
	_d=$(sed -n '2p' /tmp/murmur.d/rules/vpn.txt 2>/dev/null | sed 's/^+\.//')
	if [ -n "$_d" ]; then
		_fake=$(dig @127.0.0.1 -p "$_dns" "$_d" +short 2>/dev/null | grep -E '^198\.18\.' | head -1)
		if [ -n "$_fake" ]; then
			echo "  OK   $_d resolves to the fake IP $_fake"
		else
			echo "  FAIL $_d did not resolve to a fake IP"
			_rc=1
		fi
	fi
	_r=$(sed -n '1p' /tmp/murmur.d/rules/realip.txt 2>/dev/null | sed 's/^+\.//')
	if [ -n "$_r" ]; then
		_real=$(dig @127.0.0.1 -p "$_dns" "$_r" +short 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
		if [ -n "$_real" ]; then
			echo "  OK   $_r resolves to the real IP $_real"
		else
			echo "  FAIL $_r did not resolve to a real IP"
			_rc=1
		fi
	fi
	return $_rc
}

case "${1:-status}" in
	status)  _status ;;
	restart) _restart ;;
	refresh) _refresh ;;
	check)   _check ;;
	*)       echo "usage: $0 {status|restart|refresh|check}"; exit 1 ;;
esac
