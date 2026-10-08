#!/usr/bin/env bash
# Apply an AmneziaWG client config to an awg interface on the router over SSH.
#
# Takes the same .conf shape as wg2uci.sh (AmneziaWG/AyuGram export). wg2uci.sh
# stays the only parser; this script turns its UCI fragment into `uci`
# statements, runs them on the router and brings the interface back up.
#
# The conf's `DNS` line is dropped on purpose: the router keeps its own split DNS
# (stubby + LAN resolver + mihomo) and a tunnel-scoped resolver here would
# outrank it.

set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
WG2UCI="$HERE/wg2uci.sh"

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat >&2 <<EOF
Usage:
  $0 <awg.conf> [iface] [host]
  $0 < awg.conf
  cat awg.conf | $0

  iface  awg interface to replace (default: awg1)
  host   ssh target (default: router)
EOF
  exit 1
}

[ -r "$WG2UCI" ] || die "wg2uci.sh not found next to this script"

if [ -z "${1:-}" ]; then
  [ -t 0 ] && usage
  CONF="/dev/stdin"
elif [ -f "$1" ]; then
  CONF="$1"
else
  die "no such file: $1"
fi

IFACE="${2:-awg1}"
HOST="${3:-router}"

case "$IFACE" in
  ''|*[!A-Za-z0-9_]*) die "bad iface name: $IFACE" ;;
esac

command -v ssh >/dev/null 2>&1 || die "ssh not found"

# wg2uci.sh owns the parsing; we only translate its UCI fragment into commands.
# The peer section is created with `uci add`, so it lands anonymous exactly like
# the awg0 and awg2 peers already in /etc/config/network.
# wg2uci.sh emits `option private_key ''` even when it parsed nothing, so an empty,
# wrong or CRLF file would otherwise rebuild the interface with no key material.
FRAGMENT=$(bash "$WG2UCI" "$CONF" "$IFACE") || die "wg2uci.sh failed on $CONF"
for key in private_key public_key endpoint_host; do
  printf '%s\n' "$FRAGMENT" | grep -q "option $key '[^']" \
    || die "no $key parsed from $CONF - refusing to touch the router"
done

BATCH=$(
  printf '%s\n' "$FRAGMENT" | awk -v iface="$IFACE" '
    BEGIN {
      # anonymous peer section, the same shape awg0 and awg2 already use
      print "while uci -q delete " sq("network.@amneziawg_" iface "[0]") " 2>/dev/null; do :; done"
      print "uci -q delete " sq("network." iface) " 2>/dev/null || true"
      print "uci set network." iface "=interface"
    }
    function sq(s) { return "\047" s "\047" }
    /^config[ \t]+interface/   { sec = iface; next }
    /^config[ \t]+amneziawg_/  {
      print "PEERSEC=$(uci add network amneziawg_" iface ")"
      sec = "$PEERSEC"
      next
    }
    /^[ \t]*(option|list)[ \t]/ {
      line = $0
      kind = (line ~ /^[ \t]*list[ \t]/) ? "list" : "option"
      sub(/^[ \t]*(option|list)[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
      p = index(line, "\047")
      if (p < 2) next
      key = substr(line, 1, p - 1)
      sub(/[ \t]+$/, "", key)
      val = substr(line, p + 1)
      sub(/\047$/, "", val)
      if (val == "" || index(val, "\047") > 0) next
      if (kind == "list") {
        if (key == "dns") next
        print "uci add_list network." sec "." key "=" sq(val)
      } else {
        print "uci set network." sec "." key "=" sq(val)
      }
    }
  '
)

# $IFACE and $BATCH have to expand here; the router only runs the result.
# shellcheck disable=SC2029,SC2087
ssh "$HOST" "sh -s -- '$IFACE'" <<REMOTE
#!/bin/sh
set -e
IFACE='$IFACE'
TS=\$(date +%Y%m%d-%H%M%S)

mkdir -p /root/uci-backups
cp /etc/config/network "/root/uci-backups/network.bak.\$IFACE.\$TS"
echo "backup: /root/uci-backups/network.bak.\$IFACE.\$TS"

ifdown "\$IFACE" 2>/dev/null || true
sleep 2

$BATCH

uci commit network
ifup "\$IFACE"

i=0
while [ \$i -lt 12 ]; do
  awg show "\$IFACE" 2>/dev/null | grep -q "latest handshake" && break
  sleep 5
  i=\$((i + 1))
done

echo "--- awg show \$IFACE ---"
awg show "\$IFACE" 2>/dev/null
echo "--- routes ---"
ip route | head -3
REMOTE

echo "--- done: $IFACE on $HOST ---"
