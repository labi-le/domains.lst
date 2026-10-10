#!/bin/sh
# Keep our entries in zapret's per-host exclude list, and survive a LuCI save.
#
# Zapret's LuCI app rewrites /opt/zapret/ipset/* from its own copy whenever
# somebody presses Save, which silently drops hand edits to
# zapret-hosts-user-exclude.txt. The symptom is a client stating "the internet
# broke" again, with nothing in the log naming a cause. This script re-asserts
# the entries listed in zapret-exclude-ensure.lst next to it and restarts zapret
# only when something actually changed, so it is safe to run from cron.
#
# Entry syntax in that list:
#   +name  keep present and active
#   -name  keep out of the way: an active line gets commented out
#
# Mutating: appends to the exclude list and restarts zapret on change.
# Exits 0 either way; exits 1 when the exclude list or this script's own list is
# missing, which is how a botched install shows up in the log.

HERE=$(dirname "$0")
LIST=/opt/zapret/ipset/zapret-hosts-user-exclude.txt
ENTRIES="$HERE/zapret-exclude-ensure.lst"

[ -f "$ENTRIES" ] || { echo "exclude-ensure: missing $ENTRIES" >&2; exit 1; }
[ -f "$LIST" ] || { echo "exclude-ensure: missing $LIST" >&2; exit 1; }

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
done < "$ENTRIES"

if [ "$changed" = 1 ]; then
	/etc/init.d/zapret restart >/dev/null 2>&1
	echo "exclude-ensure: zapret restarted"
fi

exit 0
