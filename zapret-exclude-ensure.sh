#!/bin/sh
# Keep our entries in zapret's per-host exclude list.
#
# Reads its entries from the repository over HTTPS rather than from a local copy,
# so the repo is the only place an entry is edited and the router needs nothing
# deployed. Zapret's LuCI app rewrites /opt/zapret/ipset/* from its own copy
# whenever somebody presses Save, which silently drops hand edits to
# zapret-hosts-user-exclude.txt; running this script re-asserts the entries.
#
# Entry syntax in that list:
#   +name  keep present and active
#   -name  keep out of the way: an active line gets commented out
#
# A failed download is fatal and the exclude list is left untouched: an ensure
# that ran on an empty list would delete the entries it exists to protect.
#
# Mutating: appends to the exclude list and restarts zapret on change.

HERE=$(dirname "$0")
LIST=/opt/zapret/ipset/zapret-hosts-user-exclude.txt
REPO_URL=${REPO_URL:-https://raw.githubusercontent.com/labi-le/domains.lst/refs/heads/main/zapret-exclude-ensure.lst}
FETCHED="$HERE/zapret-exclude-ensure.lst.fetched"

die() { echo "exclude-ensure: $*" >&2; exit 1; }

data=""
for i in 1 2 3; do
	data=$(curl --connect-timeout 5 --max-time 20 -sSLf "$REPO_URL") && [ -n "$data" ] && break
	data=""
	echo "exclude-ensure: retry $i/3: $REPO_URL" >&2
	sleep 2
done
[ -n "$data" ] || die "cannot fetch $REPO_URL, leaving $LIST unchanged"

printf '%s\n' "$data" > "$FETCHED" || die "cannot write $FETCHED"

[ -f "$LIST" ] || die "missing $LIST"

changed=0

while IFS= read -r line || [ -n "$line" ]; do
	case "$line" in
		''|'#'*) continue ;;
	esac

	entry=${line#?}
	mode=${line%"$entry"}

	case "$mode" in
		+)
			grep -Fxq "$entry" "$LIST" && continue
			printf '%s\n' "$entry" >> "$LIST"
			echo "exclude-ensure: added $entry"
			changed=1
			;;
		-)
			grep -Fxq "$entry" "$LIST" || continue
			escaped=$(printf '%s' "$entry" | sed 's/[.[\*^$]/\\&/g')
			sed -i "s/^${escaped}\$/#&/" "$LIST"
			echo "exclude-ensure: disabled $entry"
			changed=1
			;;
		*)
			echo "exclude-ensure: ignoring malformed line: $line" >&2
			;;
	esac
done < "$FETCHED"

rm -f "$FETCHED"

if [ "$changed" = 1 ]; then
	/etc/init.d/zapret restart >/dev/null 2>&1
	echo "exclude-ensure: zapret restarted"
fi

exit 0
