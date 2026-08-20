#!/usr/bin/env bash
# Trace which hosts a process tree talks to, so its domains can be added to a rule list.
#
# DNS is captured system-wide (there is no PID on a DNS packet) and joined to the peers of the
# selected PIDs by IP. Peers with no DNS answer behind them are raw-IP destinations: a
# `behavior: domain` rule-provider can never match those, they need an ipcidr set instead.
set -euo pipefail

ROOT_PIDS=()
DURATION=120
INTERVAL=0.3
FAKEIP_PREFIX="198.18.1."
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

usage() {
	cat << EOF
usage: ${0##*/} -P PID [-P PID ...] [-d SECONDS] [-i POLL_INTERVAL]

  -P  root pid to trace; its descendants are followed too, and re-read every poll
      so a child spawned mid-capture is still attributed. Accepts several pids in one
      argument, so a pgrep that matches more than one process can be passed as is
  -d  capture duration in seconds (default: $DURATION)
  -i  socket poll interval in seconds (default: $INTERVAL)

Pick an ancestor, not the leaf: under Proton the game exe and its wineserver are siblings,
both children of the container shim, so -P with the game pid alone misses wineserver's sockets.

Needs root for packet capture; re-execs itself under sudo when run as a user.

examples:
  # everything Steam launched, client and game alike; the output labels each flow comm[pid]
  ${0##*/} -P "\$(pgrep -x steam)" -d 300

  # only the game's own branch, both halves of it
  ${0##*/} -P "\$(pgrep -x DarkSoulsII.exe)" -P "\$(pgrep -x wineserver)" -d 300

  # the shim that owns both halves, found from the game pid
  ${0##*/} -P "\$(ps -o ppid= -p \$(pgrep -x DarkSoulsII.exe))"
EOF
}

while getopts ':P:d:i:h' opt; do
	case "$opt" in
		P) ROOT_PIDS+=("$OPTARG") ;;
		d) DURATION="$OPTARG" ;;
		i) INTERVAL="$OPTARG" ;;
		h)
			usage
			exit 0
			;;
		*)
			usage >&2
			exit 2
			;;
	esac
done

[ "${#ROOT_PIDS[@]}" -gt 0 ] || {
	usage >&2
	exit 2
}

# One -P may carry a whole pgrep result: several pids, separated by newlines or commas.
PIDS=()
for spec in "${ROOT_PIDS[@]}"; do
	read -r -a parts <<< "$(tr ',\n' '  ' <<< "$spec")"
	for pid in ${parts[@]+"${parts[@]}"}; do
		case "$pid" in
			'' | *[!0-9]*)
				echo "not a pid: $pid" >&2
				exit 2
				;;
		esac
		[ -d "/proc/$pid" ] || {
			echo "no such process: $pid" >&2
			exit 2
		}
		PIDS+=("$pid")
	done
done

[ "${#PIDS[@]}" -gt 0 ] || {
	echo "no pids given" >&2
	exit 2
}

command -v tshark > /dev/null || {
	echo "tshark not found" >&2
	exit 1
}

if [ "$(id -u)" -ne 0 ]; then
	echo "packet capture needs root, re-executing under sudo" >&2
	args=()
	for pid in "${PIDS[@]}"; do args+=(-P "$pid"); done
	exec sudo -- "$0" "${args[@]}" -d "$DURATION" -i "$INTERVAL"
fi

# Descendants, not just the roots: a Proton game is one pid, its wineserver another, and Steam
# reparents things at will. Recomputed per poll because the tree changes under us.
descendants() {
	awk -v roots="$1" '
		BEGIN { n = split(roots, r, ","); for (i = 1; i <= n; i++) want[r[i]] = 1 }
		{
			# comm is unquoted and may hold spaces and parens, so ppid is only findable
			# by anchoring on the LAST ")" in the line.
			pid = $1 + 0
			close_paren = 0
			for (i = length($0); i > 0; i--) if (substr($0, i, 1) == ")") { close_paren = i; break }
			split(substr($0, close_paren + 2), f, " ")
			kids[f[2] + 0] = kids[f[2] + 0] " " pid
		}
		END {
			for (q in want) if (!seen[q + 0]++) queue[++tail_i] = q + 0
			while (head_i < tail_i) {
				cur = queue[++head_i]
				out = out (out ? "," : "") cur
				n = split(kids[cur], k, " ")
				for (i = 1; i <= n; i++) if (k[i] != "" && !seen[k[i] + 0]++) queue[++tail_i] = k[i] + 0
			}
			print out
		}
	' /proc/[0-9]*/stat 2> /dev/null
}

DNS="$WORKDIR/dns.tsv"
FLOWS="$WORKDIR/flows.tsv"
: > "$DNS"
: > "$FLOWS"

# `-i any` also catches a resolver that bypasses the loopback stub.
tshark -i any -f 'udp port 53' -l -Q \
	-T fields -e dns.qry.name -e dns.a -e dns.cname \
	-E occurrence=a > "$DNS" 2> /dev/null &
tshark_pid=$!
trap 'kill "$tshark_pid" 2>/dev/null || true; rm -rf "$WORKDIR"' EXIT

roots=$(
	IFS=,
	echo "${PIDS[*]}"
)
echo "capturing ${DURATION}s for pids $roots and descendants ..." >&2
end=$((SECONDS + DURATION))
while [ "$SECONDS" -lt "$end" ]; do
	ss -tunpH 2> /dev/null | awk -v pids="$(descendants "$roots")" '
		BEGIN { n = split(pids, p, ","); for (i = 1; i <= n; i++) want[p[i]] = 1 }
		{
			proto = $1
			peer = $6
			sub(/^\[/, "", peer)
			sub(/\]:/, ":", peer)
			n = split(peer, a, ":")
			ip = ""
			for (i = 1; i < n; i++) ip = ip (i > 1 ? ":" : "") a[i]
			port = a[n]
			if (port == "*") next
			if (ip ~ /^(127\.|0\.0\.0\.0|::1?$|169\.254\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)/) next
			procs = ""
			line = $0
			while (match(line, /\("[^"]+",pid=[0-9]+/)) {
				hit = substr(line, RSTART + 2, RLENGTH - 2)
				line = substr(line, RSTART + RLENGTH)
				split(hit, f, "\",pid=")
				if (!(f[2] in want)) continue
				procs = procs (procs ? "," : "") f[1] "[" f[2] "]"
			}
			if (procs == "") next
			print proto "\t" ip "\t" port "\t" procs
		}' >> "$FLOWS" || true
	sleep "$INTERVAL"
done

kill "$tshark_pid" 2> /dev/null || true
wait "$tshark_pid" 2> /dev/null || true

echo >&2
awk -F'\t' -v fakeip="$FAKEIP_PREFIX" '
	NR == FNR {
		if ($1 == "" || $2 == "") next
		split($2, ips, ",")
		for (i in ips) if (ips[i] != "") name[ips[i]] = $1
		next
	}
	{
		if (seen[$0]++) next
		if (index($2, fakeip) == 1) {
			proxied[($2 in name ? name[$2] : "?") "\t" $2 "\t" $4] = 1
		} else if ($2 in name) {
			direct[name[$2] "\t" $2 ":" $3 "\t" $4] = 1
		} else {
			raw[$1 "\t" $2 "\t" $3 "\t" $4] = 1
		}
	}
	END {
		print "=== resolved by name, currently DIRECT: add these to the vpn list ==="
		n = 0
		for (d in direct) { split(d, f, "\t"); printf "%-45s %-22s %s\n", f[1], f[2], f[3]; n++ }
		if (!n) print "(none)"
		print ""
		print "=== already inside mihomo (fake-ip " fakeip "0/24), a rule already matches ==="
		n = 0
		for (d in proxied) { split(d, f, "\t"); printf "%-45s %-22s %s\n", f[1], f[2], f[3]; n++ }
		if (!n) print "(none)"
		print ""
		print "=== raw-IP peers: no DNS name, a behavior:domain rule can NEVER match these ==="
		n = 0
		for (r in raw) { split(r, f, "\t"); printf "%-5s %-16s %-7s %s\n", f[1], f[2], f[3], f[4]; n++ }
		if (!n) print "(none)"
	}
' "$DNS" "$FLOWS"
